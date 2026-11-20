--[[
	BreachCutsceneClient (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.
	Partie client de la cinématique de brèche (voir ServerScriptService.BreachCutscene).

	  - caméra en mode Scriptable, plans enchaînés :
	      « Armory » dans l'armurerie, les gardes de dos (travelling) ;
	      « Wide »   plongée devant l'armurerie, caméra de surveillance (travelling) ;
	      « Follow » caméra qui suit les gardes de dos, sans jamais traverser un mur (Spherecast) ;
	      « Door »   gros plan sur la porte de la SALLE 001, travelling lent (TweenService) ;
	  - bandes noires en haut et en bas de l'écran pendant toute la scène ;
	  - le joueur ne peut pas bouger (contrôles désactivés) ;
	  - ESPACE / ENTRÉE / bouton A de la manette, ou le bouton « PASSER », pour passer la scène.

	Pendant la scène, l'attribut local InCutscene du joueur vaut true (DClassHUD masque alors ses cases,
	sauf les annonces d'alerte).
]]

-- Ne tourne que sur un serveur de partie, pas dans le hall de transit (voir HubServer).
while workspace:GetAttribute("ServerMode") ~= "Match" do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("BreachCutscene")

-- Contrôles par défaut, s'ils existent dans cette place (PlayerModule). Sinon on fige le personnage
-- en ancrant sa racine côté client (le client possède la physique de son personnage).
local controls = nil
local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3)
if playerModule then
	controls = require(playerModule):GetControls()
end

local function freezePlayer(frozen)
	if controls then
		if frozen then
			controls:Disable()
		else
			controls:Enable()
		end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = frozen
	end
end

local CONFIG = {
	BAR_HEIGHT = 0.11, -- hauteur de chaque bande noire (part de l'écran)
	BAR_TIME = 0.6,
	FADE_TIME = 0.35,
	FOLLOW_DISTANCE = 9, -- plan de dos : distance derrière le groupe
	FOLLOW_HEIGHT = 3.5, -- hauteur au-dessus des gardes
	FOLLOW_RADIUS = 0.6, -- marge entre la caméra et les murs (studs)
	FOLLOW_LOOK_AHEAD = 7,
	FOLLOW_SMOOTH = 4, -- plus grand = caméra plus réactive
	SKIP_KEYS = { Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA },
}

---------------------------------------------------------------------------
-- Interface : bandes noires, fondu, bouton « Passer »
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CinemaBars"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 3 -- sous le HUD (4) : la case d'alerte reste lisible par-dessus la bande du bas
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function bar(anchorY)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0, anchorY)
	f.Position = UDim2.fromScale(0, anchorY)
	f.Size = UDim2.fromScale(1, 0)
	f.ZIndex = 2
	f.Parent = gui
	return f
end
local topBar = bar(0)
local bottomBar = bar(1)

local fade = Instance.new("Frame")
fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Size = UDim2.fromScale(1, 1)
fade.ZIndex = 5
fade.Parent = gui

local skipButton = Instance.new("TextButton")
skipButton.AnchorPoint = Vector2.new(1, 0.5)
skipButton.Position = UDim2.new(1, -20, 0.5, 0)
skipButton.Size = UDim2.fromOffset(190, 30)
skipButton.BackgroundTransparency = 1
skipButton.Font = Enum.Font.GothamMedium
skipButton.TextSize = 14
skipButton.TextColor3 = Color3.fromRGB(200, 200, 200)
skipButton.TextXAlignment = Enum.TextXAlignment.Right
skipButton.Text = "PASSER  ›  [ESPACE]"
skipButton.ZIndex = 3
skipButton.Parent = topBar

local function tween(obj, t, props, style)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end

---------------------------------------------------------------------------
-- Caméra
---------------------------------------------------------------------------
local camera = workspace.CurrentCamera
local active = false
local camTween = nil
local followConn = nil

local function stopShot()
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	if followConn then
		followConn:Disconnect()
		followConn = nil
	end
end

-- Plan fixe avec travelling : de « from » à « to » en « time » secondes
local function travelling(data)
	camera.CFrame = data.from
	camTween = TweenService:Create(camera, TweenInfo.new(data.time or 6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = data.to,
	})
	camTween:Play()
end

-- Plan de dos : derrière le groupe, dans le sens de sa course
local function follow(guards)
	local heading = nil
	local function groupState()
		local sum, n, vel = Vector3.zero, 0, Vector3.zero
		for _, m in ipairs(guards) do
			local root = m.Parent and m:FindFirstChild("HumanoidRootPart")
			if root then
				sum += root.Position
				vel += root.AssemblyLinearVelocity
				n += 1
			end
		end
		if n == 0 then
			return nil
		end
		return sum / n, Vector3.new(vel.X, 0, vel.Z)
	end
	local center, vel = groupState()
	if not center then
		return
	end
	heading = (vel.Magnitude > 2 and vel.Unit) or Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
	-- Anti-mur : on lance une sphère du groupe vers la position voulue, la caméra s'arrête avant le premier obstacle
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local function refreshIgnore()
		local ignore = table.clone(guards)
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
	end
	refreshIgnore()
	local function safe(focus, wanted)
		local offset = wanted - focus
		if offset.Magnitude < 0.1 then
			return wanted
		end
		local hit = workspace:Spherecast(focus, CONFIG.FOLLOW_RADIUS, offset, params)
		if hit then
			return focus + offset.Unit * math.max(0.5, hit.Distance - 0.1)
		end
		return wanted
	end
	-- Point visé : centre du groupe, sauf s'il est derrière un mur (groupe étalé dans un virage) :
	-- on prend alors le garde de tête, toujours en terrain dégagé
	local function leaderPos()
		for _, m in ipairs(guards) do
			local root = m.Parent and m:FindFirstChild("HumanoidRootPart")
			if root then
				return root.Position
			end
		end
	end
	local function focusOf(c)
		local f = c + Vector3.new(0, 1.5, 0)
		local lead = leaderPos()
		if not lead then
			return f
		end
		lead += Vector3.new(0, 1.5, 0)
		if workspace:Raycast(lead, f - lead, params) then
			return lead
		end
		return f
	end
	local function wantedPos(c)
		return c - heading * CONFIG.FOLLOW_DISTANCE + Vector3.new(0, CONFIG.FOLLOW_HEIGHT, 0)
	end
	local function lookPoint(c)
		return c + heading * CONFIG.FOLLOW_LOOK_AHEAD + Vector3.new(0, 0.5, 0)
	end
	-- Position lissée hors murs ; la vérification se fait sur la position lissée, pas seulement sur la cible
	local smoothed = wantedPos(center)
	camera.CFrame = CFrame.lookAt(safe(focusOf(center), smoothed), lookPoint(center))
	local lastRefresh = os.clock()
	followConn = RunService.RenderStepped:Connect(function(dt)
		local c, v = groupState()
		if not c then
			return
		end
		if os.clock() - lastRefresh > 1 then
			refreshIgnore()
			lastRefresh = os.clock()
		end
		if v.Magnitude > 2 then
			local a = math.min(1, dt * 2.5)
			heading = (heading:Lerp(v.Unit, a)).Unit
		end
		smoothed = smoothed:Lerp(wantedPos(c), math.min(1, dt * CONFIG.FOLLOW_SMOOTH))
		camera.CFrame = CFrame.lookAt(safe(focusOf(c), smoothed), lookPoint(c))
	end)
end

---------------------------------------------------------------------------
-- Début / fin
---------------------------------------------------------------------------
local function setBars(open)
	local h = open and CONFIG.BAR_HEIGHT or 0
	tween(topBar, CONFIG.BAR_TIME, { Size = UDim2.fromScale(1, h) })
	return tween(bottomBar, CONFIG.BAR_TIME, { Size = UDim2.fromScale(1, h) })
end

local function restoreCamera()
	stopShot()
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
end

local stop -- défini plus bas

local function onSkipAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		stop(true)
	end
	return Enum.ContextActionResult.Sink
end

local function start()
	if active then
		return
	end
	active = true
	player:SetAttribute("InCutscene", true)
	freezePlayer(true)
	camera.CameraType = Enum.CameraType.Scriptable
	gui.Enabled = true
	fade.BackgroundTransparency = 0
	tween(fade, CONFIG.FADE_TIME * 2, { BackgroundTransparency = 1 })
	setBars(true)
	ContextActionService:BindActionAtPriority(
		"SkipBreachCutscene",
		onSkipAction,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		table.unpack(CONFIG.SKIP_KEYS)
	)
end

function stop(skipped)
	if not active then
		return
	end
	active = false
	ContextActionService:UnbindAction("SkipBreachCutscene")
	if skipped then
		remote:FireServer("Skip")
	end
	-- Fondu au noir, retour à la caméra du joueur, puis on rouvre l'image
	tween(fade, CONFIG.FADE_TIME, { BackgroundTransparency = 0 }).Completed:Wait()
	restoreCamera()
	freezePlayer(false)
	player:SetAttribute("InCutscene", false)
	tween(fade, CONFIG.FADE_TIME, { BackgroundTransparency = 1 })
	setBars(false).Completed:Wait()
	if not active then
		gui.Enabled = false
	end
end

skipButton.Activated:Connect(function()
	stop(true)
end)

remote.OnClientEvent:Connect(function(msg, name, data)
	if msg == "Start" then
		start()
	elseif msg == "Shot" and active then
		stopShot()
		if name == "Follow" then
			follow(data.guards)
		elseif data and data.from then
			travelling(data)
		end
	elseif msg == "End" then
		stop(false)
	end
end)

-- Sécurité : si le personnage réapparaît pendant la scène, on garde la caméra de la scène
player.CharacterAdded:Connect(function()
	if active then
		task.defer(function()
			camera.CameraType = Enum.CameraType.Scriptable
			freezePlayer(true)
		end)
	end
end)
