--[[
	CrazyDClass (Script) — à placer dans ServerScriptService.
	Nécessite SCPCodex (ServerScriptService), SCPTips (ReplicatedStorage) et le décor
	Workspace.Hub.Decor.CelluleIsolement (repères FouSpot et FouGrab, néon CellTube).

	D-0451 « Le Fou » : Classe D enfermé dans la cellule de détention du hall de transit.

	Serveur (ce script) :
	  - construit le PNJ : avatar R15, articulations converties en Motor6D, combinaison orange sale
	    et déchirée, cheveux en bataille (parts simples, aucun asset) ;
	  - choisit qui il fixe (attribut Focus = UserId du joueur le plus proche, 0 sinon) ;
	  - gère son état (attribut State) : Idle, Rush (il se jette sur les barreaux), Grab (agrippé),
	    Return (retourne au fond de la cellule) et déplace sa racine entre FouSpot et FouGrab ;
	  - conversation : ProximityPrompt « Parler », répliques choisies selon le dossier SCPCodex.
	Client (CrazyDClassAnim) : animation procédurale des Motor6D selon State et Focus
	(posture voûtée, balancement, tics nerveux, regard, mains agrippées aux barreaux).

	Serveur → client : RemoteEvent ReplicatedStorage.FouDialog ("Open", speaker, lignes)
	Client → serveur : ("Close") à la fin de la conversation.
]]

-- Charge le dossier des anomalies sur tous les serveurs (hall et parties)
local Codex = require(script.Parent:WaitForChild("SCPCodex"))

while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Tips = require(ReplicatedStorage:WaitForChild("SCPTips"))
local FaceKit = require(game:GetService("ServerStorage"):WaitForChild("FaceKit"))

local CONFIG = {
	MATRICULE = "D-0451",
	SUIT = Color3.fromRGB(176, 92, 36), -- orange terni
	SKIN = Color3.fromRGB(176, 128, 98), -- teint terne, pas blanc
	HAIR = Color3.fromRGB(46, 38, 32),
	PROMPT_DISTANCE = 12, -- depuis la ligne jaune devant la cellule, il est au fond (studs)
	FOCUS_RANGE = 18, -- il fixe le joueur le plus proche dans ce rayon (studs)
	RUSH_TIME = 0.4, -- course jusqu'aux barreaux (s)
	RETURN_TIME = 2.4, -- retour au fond de la cellule (s)
	TALK_COOLDOWN = 1.5,
	TALK_TIMEOUT = 45,
	VOICE_SOUND_ID = nil, -- ex. "rbxassetid://123456" : marmonnement à chaque conversation
}

local hub = workspace:WaitForChild("Hub")
local cell = hub:WaitForChild("Decor"):WaitForChild("CelluleIsolement")
local homeMarker = cell:WaitForChild("FouSpot")
local grabMarker = cell:WaitForChild("FouGrab")

local remote = ReplicatedStorage:FindFirstChild("FouDialog") or Instance.new("RemoteEvent")
remote.Name = "FouDialog"
remote.Parent = ReplicatedStorage

---------------------------------------------------------------------------
-- Construction du PNJ
---------------------------------------------------------------------------
-- Les avatars récents utilisent des AnimationConstraint : on les remplace par des Motor6D classiques,
-- que le client anime à la main (Motor6D.Transform).
local function convertJoints(model)
	for _, c in ipairs(model:GetDescendants()) do
		if c:IsA("AnimationConstraint") and c.Attachment0 and c.Attachment1 then
			local a0, a1 = c.Attachment0, c.Attachment1
			local m = Instance.new("Motor6D")
			m.Name = c.Name
			m.Part0 = a0.Parent
			m.Part1 = a1.Parent
			m.C0 = a0.CFrame
			m.C1 = a1.CFrame
			m.Parent = a1.Parent
		end
	end
	for _, c in ipairs(model:GetDescendants()) do
		if c:IsA("Constraint") then
			c:Destroy()
		end
	end
end

local function rng(a, b)
	return a + math.random() * (b - a)
end

-- Taches et déchirures dessinées sur une face d'une part (SurfaceGui, aucun asset)
local function grime(part, face, stains, tears)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Grime"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = part
	for _ = 1, stains do
		local s = Instance.new("Frame")
		local w = rng(0.15, 0.45)
		s.Size = UDim2.fromScale(w, w * rng(0.5, 1.2))
		s.Position = UDim2.fromScale(rng(-0.1, 0.9), rng(-0.1, 0.9))
		s.Rotation = rng(0, 180)
		s.BorderSizePixel = 0
		s.BackgroundColor3 = Color3.fromRGB(math.random(60, 90), math.random(48, 64), math.random(30, 42))
		s.BackgroundTransparency = rng(0.4, 0.75)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = s
		s.Parent = gui
	end
	for _ = 1, tears do
		-- déchirure : trou dentelé qui laisse voir la peau, bordé de tissu effiloché
		local cx, cy = rng(0.1, 0.8), rng(0.15, 0.85)
		for k = 1, 4 do
			local t = Instance.new("Frame")
			t.Size = UDim2.fromScale(rng(0.08, 0.2), rng(0.04, 0.09))
			t.Position = UDim2.fromScale(cx + rng(-0.06, 0.06), cy + (k - 2) * 0.035)
			t.Rotation = rng(-35, 35)
			t.BorderSizePixel = 0
			t.BackgroundColor3 = CONFIG.SKIN:Lerp(Color3.fromRGB(90, 55, 40), 0.35)
			t.Parent = gui
		end
		local edge = Instance.new("Frame")
		edge.Size = UDim2.fromScale(0.26, 0.025)
		edge.Position = UDim2.fromScale(cx - 0.04, cy - 0.06)
		edge.Rotation = rng(-20, 20)
		edge.BorderSizePixel = 0
		edge.BackgroundColor3 = Color3.fromRGB(110, 58, 26)
		edge.Parent = gui
	end
end

local function weldTo(base, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = base.Parent
	return p
end

local function buildNPC()
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = CONFIG.SKIN
	desc.TorsoColor = CONFIG.SUIT
	desc.LeftArmColor = CONFIG.SUIT
	desc.RightArmColor = CONFIG.SUIT
	desc.LeftLegColor = CONFIG.SUIT
	desc.RightLegColor = CONFIG.SUIT
	-- silhouette émaciée : épaules étroites, corps maigre, tête un peu trop grosse
	desc.WidthScale = 0.78
	desc.DepthScale = 0.8
	desc.HeadScale = 1.06
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[CrazyDClass] PNJ non créé :", model)
		return nil
	end
	model.Name = CONFIG.MATRICULE
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	hum.EvaluateStateMachine = false -- simple marionnette : pas de physique d'humanoïde
	for _, n in ipairs({ "Animate", "Health" }) do
		local s = model:FindFirstChild(n)
		if s then
			s:Destroy()
		end
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy() -- rien ne doit écraser les Motor6D.Transform du client
	end
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
	convertJoints(model)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			if d.Name == "LeftHand" or d.Name == "RightHand" or d.Name == "Head" then
				d.Color = CONFIG.SKIN
			elseif d.Name == "LeftFoot" or d.Name == "RightFoot" then
				d.Color = Color3.fromRGB(58, 54, 50) -- chaussons gris crasseux
			elseif d.Name ~= "HumanoidRootPart" then
				d.Color = CONFIG.SUIT
				d.Material = Enum.Material.Fabric
			end
		end
	end

	-- Combinaison sale et déchirée
	math.randomseed(451)
	local F, B = Enum.NormalId.Front, Enum.NormalId.Back
	local function get(n)
		return model:FindFirstChild(n)
	end
	grime(get("UpperTorso"), F, 6, 1)
	grime(get("UpperTorso"), B, 5, 1)
	grime(get("LowerTorso"), F, 3, 0)
	for _, n in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }) do
		grime(get(n), F, 2, n:find("Lower") and 1 or 0)
		grime(get(n), B, 2, 0)
	end
	for _, n in ipairs({ "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }) do
		grime(get(n), F, 3, n == "RightLowerLeg" and 1 or 0)
		grime(get(n), B, 2, 0)
	end

	-- Matricule à moitié effacé sur la poitrine
	local torso = get("UpperTorso")
	local tag = Instance.new("SurfaceGui")
	tag.Face = F
	tag.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tag.PixelsPerStud = 60
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.8, 0.28)
	label.Position = UDim2.fromScale(0.1, 0.1)
	label.Rotation = -4
	label.Font = Enum.Font.Michroma
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(30, 26, 22)
	label.TextTransparency = 0.25
	label.Text = CONFIG.MATRICULE
	label.ZIndex = 2
	label.Parent = tag
	tag.Parent = torso

	-- Cheveux en bataille : mèches de travers soudées à la tête
	local head = get("Head")
	weldTo(head, "HairBase", Vector3.new(1.3, 0.42, 1.32), CFrame.new(0, 0.47, 0.1), CONFIG.HAIR, Enum.Material.Fabric)
	weldTo(head, "HairBack", Vector3.new(1.28, 0.7, 0.3), CFrame.new(0, 0.2, 0.55), CONFIG.HAIR, Enum.Material.Fabric)
	for _ = 1, 16 do
		-- mèches courtes, couchées dans tous les sens, réparties sur le crâne
		-- jamais sur le front (sinon les mèches cachent le visage)
		local a = rng(-math.pi * 0.1, math.pi * 1.1)
		local r = rng(0.1, 0.55)
		weldTo(
			head,
			"HairTuft",
			Vector3.new(rng(0.18, 0.3), rng(0.25, 0.5), rng(0.18, 0.3)),
			CFrame.new(math.cos(a) * r, rng(0.6, 0.74), math.sin(a) * r + 0.15)
				* CFrame.Angles(math.sin(a) * rng(0.7, 1.4), rng(0, 3), -math.cos(a) * rng(0.7, 1.4)),
			CONFIG.HAIR:Lerp(Color3.fromRGB(90, 80, 70), rng(0, 0.3)),
			Enum.Material.Fabric
		)
	end
	-- Visage : yeux exorbités injectés de sang, pupilles en tête d'épingle, sourcils de travers,
	-- sourire trop large, cernes, barbe sale, cicatrice, sueur (animé par NPCFaces)
	FaceKit.apply(head, {
		skin = CONFIG.SKIN,
		iris = Color3.fromRGB(120, 140, 130),
		eyeSize = 1.4,
		pupil = 0.26,
		lids = 0,
		brows = { -22, 16 },
		browThick = 0.05,
		browColor = CONFIG.HAIR,
		mouth = "grin",
		bags = 1,
		bloodshot = true,
		stubble = 0.9,
		stubbleColor = Color3.fromRGB(60, 50, 42),
		scar = true,
		sweat = true,
		crazy = true,
	})

	-- Griffures sur les avant-bras (il se gratte jusqu'au sang) et bandage sale au poignet
	for _, n in ipairs({ "LeftLowerArm", "RightLowerArm" }) do
		local arm = get(n)
		local g = Instance.new("SurfaceGui")
		g.Face = F
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 60
		g.Parent = arm
		for k = 1, 4 do
			local s = Instance.new("Frame")
			s.BorderSizePixel = 0
			s.BackgroundColor3 = Color3.fromRGB(150, 30, 30)
			s.BackgroundTransparency = 0.2
			s.Size = UDim2.fromScale(0.8, 0.025)
			s.Position = UDim2.fromScale(0.1, 0.3 + k * 0.08)
			s.Rotation = -25 + k * 4
			s.Parent = g
		end
	end
	local wrist = get("LeftLowerArm")
	weldTo(
		wrist,
		"Bandage",
		Vector3.new(wrist.Size.X + 0.08, 0.35, wrist.Size.Z + 0.08),
		CFrame.new(0, -wrist.Size.Y / 2 + 0.25, 0),
		Color3.fromRGB(200, 192, 170),
		Enum.Material.Fabric
	)

	-- Posé au sol, au repère FouSpot
	model:PivotTo(homeMarker.CFrame)
	local cf, size = model:GetBoundingBox()
	local floorY = homeMarker.Position.Y - homeMarker.Size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (cf.Y - size.Y / 2), 0))
	model:SetAttribute("State", "Idle")
	model:SetAttribute("Focus", 0)
	model.Parent = cell
	return model
end

local npc = buildNPC()
if not npc then
	return
end
local root = npc:WaitForChild("HumanoidRootPart")
local homeCF = root.CFrame
-- Contre les barreaux : même hauteur, orientation du repère FouGrab
local grabCF = CFrame.new(Vector3.new(grabMarker.Position.X, homeCF.Y, grabMarker.Position.Z)) * grabMarker.CFrame.Rotation

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Parler"
prompt.ObjectText = Tips.SPEAKER
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = CONFIG.PROMPT_DISTANCE
prompt.RequiresLineOfSight = false
prompt.HoldDuration = 0
prompt.Parent = root

---------------------------------------------------------------------------
-- Regard : joueur le plus proche
---------------------------------------------------------------------------
local talkingTo = nil

task.spawn(function()
	while npc.Parent do
		local focus = 0
		if talkingTo then
			focus = talkingTo.UserId
		else
			local best
			for _, p in ipairs(Players:GetPlayers()) do
				local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if r then
					local d = (r.Position - root.Position).Magnitude
					if d < CONFIG.FOCUS_RANGE and (not best or d < best) then
						best, focus = d, p.UserId
					end
				end
			end
		end
		if npc:GetAttribute("Focus") ~= focus then
			npc:SetAttribute("Focus", focus)
		end
		task.wait(0.2)
	end
end)

---------------------------------------------------------------------------
-- Déplacements : se jeter sur les barreaux, revenir au fond
---------------------------------------------------------------------------
local moveTween = nil
local function moveRoot(cf, t, style)
	if moveTween then
		moveTween:Cancel()
	end
	moveTween = TweenService:Create(root, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf })
	moveTween:Play()
	return moveTween
end

local function rushToBars(player)
	npc:SetAttribute("State", "Rush")
	local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local target = grabCF
	if r then
		-- se plaque contre les barreaux en face du joueur (sans sortir de la cellule)
		local z = math.clamp(r.Position.Z, grabMarker.Position.Z - 5, grabMarker.Position.Z + 5)
		target = CFrame.new(grabCF.Position.X, grabCF.Y, z) * grabCF.Rotation
	end
	local tw = moveRoot(target, CONFIG.RUSH_TIME, Enum.EasingStyle.Quart)
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and npc:GetAttribute("State") == "Rush" then
			npc:SetAttribute("State", "Grab")
		end
	end)
end

local function backToCorner()
	npc:SetAttribute("State", "Return")
	local tw = moveRoot(homeCF, CONFIG.RETURN_TIME, Enum.EasingStyle.Sine)
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and npc:GetAttribute("State") == "Return" then
			npc:SetAttribute("State", "Idle")
		end
	end)
end

---------------------------------------------------------------------------
-- Conversation
---------------------------------------------------------------------------
local function pick(list)
	return list[math.random(1, #list)]
end

local function buildLines(player)
	local data = Codex.get(player)
	-- Il parle de ce que le joueur a vécu : l'anomalie dont il a entendu le moins de conseils
	local best, bestHeard
	for _, id in ipairs(Tips.ORDER) do
		if data.seen[id] and Tips.ENTRIES[id] then
			local heard = data.heard[id] or 0
			if not bestHeard or heard < bestHeard then
				best, bestHeard = id, heard
			end
		end
	end
	if not best then
		return table.clone(pick(Tips.NOTHING))
	end
	local entry = Tips.ENTRIES[best]
	local deaths = data.seen[best].deaths or 0
	local lines = {}
	if deaths >= 2 and entry.greetDeaths and math.random() < 0.5 then
		table.insert(lines, (string.format(pick(entry.greetDeaths), deaths, deaths)))
	else
		table.insert(lines, pick(entry.greet))
	end
	local index, isRepeat = Codex.takeTip(player, best, #entry.tips)
	local tip = entry.tips[index]
	if isRepeat then
		tip = pick(Tips.REPEAT) .. " " .. tip
	end
	table.insert(lines, tip)
	table.insert(lines, pick(Tips.BYE))
	return lines
end

local busy = {}
local lastTalk = {}

local function endTalk(player)
	busy[player] = nil
	lastTalk[player] = os.clock()
	if talkingTo == player then
		talkingTo = nil
		npc:SetAttribute("Talking", false)
		task.delay(0.6, function()
			if not talkingTo then
				backToCorner()
			end
		end)
	end
end

prompt.Triggered:Connect(function(player)
	if busy[player] or talkingTo or os.clock() - (lastTalk[player] or 0) < CONFIG.TALK_COOLDOWN then
		return
	end
	busy[player] = os.clock()
	talkingTo = player
	npc:SetAttribute("Focus", player.UserId)
	rushToBars(player)
	if CONFIG.VOICE_SOUND_ID then
		local s = Instance.new("Sound")
		s.SoundId = CONFIG.VOICE_SOUND_ID
		s.RollOffMaxDistance = 30
		s.Parent = root
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
	local lines = buildLines(player)
	task.wait(CONFIG.RUSH_TIME * 0.8) -- la fenêtre s'ouvre quand il arrive aux barreaux
	npc:SetAttribute("Talking", true) -- la bouche bouge (NPCFaces)
	remote:FireClient(player, "Open", Tips.SPEAKER, lines, root)
	local started = busy[player]
	task.delay(CONFIG.TALK_TIMEOUT, function()
		if busy[player] == started then
			endTalk(player)
		end
	end)
end)

remote.OnServerEvent:Connect(function(player, msg)
	if msg == "Close" and busy[player] then
		endTalk(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if busy[player] or talkingTo == player then
		endTalk(player)
	end
	lastTalk[player] = nil
end)

---------------------------------------------------------------------------
-- Néon grillagé de la cellule : grésille de temps en temps
---------------------------------------------------------------------------
local tube = cell:FindFirstChild("CellTube")
local housing = cell:FindFirstChild("LampHousing")
local lampLight = housing and housing:FindFirstChildOfClass("SurfaceLight")
if tube and lampLight then
	task.spawn(function()
		local base = lampLight.Brightness
		while tube.Parent do
			task.wait(rng(4, 11))
			for _ = 1, math.random(3, 8) do
				local on = math.random() > 0.45
				lampLight.Brightness = on and base or base * 0.08
				tube.Material = on and Enum.Material.Neon or Enum.Material.Glass
				task.wait(rng(0.03, 0.12))
			end
			lampLight.Brightness = base
			tube.Material = Enum.Material.Neon
		end
	end)
end
