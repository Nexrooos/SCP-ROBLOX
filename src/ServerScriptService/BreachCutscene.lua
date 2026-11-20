--[[
	BreachCutscene (ModuleScript) — à placer dans ServerScriptService, à côté de DClassLobby.
	Nécessite ServerStorage.FoundationGuard et le dossier Workspace.DClassBlock.BreachCutscene
	(créé par tools/breach-cutscene/SetupBreachCutscene.lua).

	Cinématique de la brèche, pilotée par le serveur. DClassLobby l'appelle au début de la brèche :
	  1. Alarme : néons du bloc en rouge clignotant, message « BRÈCHE DE CONFINEMENT DÉTECTÉE »
	     dans la case d'alerte du HUD (canal LobbyPA). La sirène est lancée par DClassLobby.
	  2. Quatre gardes sortent de l'armurerie (la porte pivote) et courent en formation
	     jusqu'à la porte de la SALLE 001 (Humanoid:MoveTo, points de passage BreachCutscene.Waypoints).
	  3. La porte Room001Door s'ouvre avec la fonction slideDoor de DClassLobby, les gardes la franchissent
	     un par un, puis elle se referme.
	  4. Fin : les gardes sont retirés, les lumières et les portes reviennent à leur état d'avant.

	Les clients (LocalScript BreachCutsceneClient) gèrent la caméra, les bandes noires et le bouton « Passer ».
	Échanges sur le RemoteEvent ReplicatedStorage.BreachCutscene :
	  serveur → clients : "Start" ; "Shot", nom, données ; "End"
	  client → serveur  : "Skip" (quand tous les joueurs ont passé la scène, elle s'arrête tout de suite)

	Utilisation (DClassLobby) :
		BreachCutscene.play({
			slideDoor = slideDoor,        -- function(door, open, duration)
			securityDoor = securityDoor,  -- function(name) -> Model
			setLights = setLights,        -- function(level, color)
			announce = announce,          -- function(text, kind, hold), peut céder
		})  -- rend la main à la fin de la scène
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local FoundationGuard = require(ServerStorage:WaitForChild("FoundationGuard"))

local CONFIG = {
	ALERT_TEXT = "BRÈCHE DE CONFINEMENT DÉTECTÉE",
	RED = Color3.fromRGB(255, 30, 20),
	FLASH_PERIOD = 0.45, -- demi-période du clignotement rouge (s)
	OPENING_SHOT = "Armory", -- premier plan (repères Shots.Armory_Start / Armory_End)
	SHOT_MIN_SHARE = 0.8, -- part minimale d'un travelling montrée avant le plan suivant
	GUARDS_START = 2.4, -- départ des gardes après le début (s)
	ARMORY_DOOR_OPEN = 1.0, -- ouverture de la porte de l'armurerie (s après le début)
	CONTAINMENT_DOOR = "Room001Door", -- porte de confinement (tag SecurityDoor)
	ACCESS_DOORS = { "HallDoor", "TestDoor", "InnerDoor" }, -- portes ouvertes pour laisser passer les gardes
	PASS_THROUGH = { "TempBackWall" }, -- parts du sas sans collision pendant la scène (mur provisoire derrière la porte)
	DOOR_OPEN_TIME = 3, -- même durée que l'ouverture forcée de la SALLE 001 dans DClassLobby
	DOOR_CLOSE_TIME = 2.6,
	CROSS_INTERVAL = 0.75, -- écart entre deux gardes au passage de la porte (s)
	HOLD_TIMEOUT = 25, -- sécurité : temps max pour rejoindre la porte (s)
	CROSS_TIMEOUT = 10,
	END_FADE = 0.5, -- laisse le fondu des clients se faire avant le nettoyage (s)
}

local block = workspace:WaitForChild("DClassBlock")
local stage = block:WaitForChild("BreachCutscene")

local remote = ReplicatedStorage:FindFirstChild("BreachCutscene") or Instance.new("RemoteEvent")
remote.Name = "BreachCutscene"
remote.Parent = ReplicatedStorage

-- Les repères sont visibles dans Studio pour pouvoir les déplacer, invisibles en jeu.
for _, d in ipairs(stage:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Transparency = 1
	end
end

local function ordered(folderName)
	local list = stage:WaitForChild(folderName):GetChildren()
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

---------------------------------------------------------------------------
-- Porte de l'armurerie : simple battant qui pivote vers le couloir
---------------------------------------------------------------------------
local armoryDoor = block:FindFirstChild("GuardPost") and block.GuardPost:FindFirstChild("ArmoryDoor")
local armoryClosed, armoryHinge
if armoryDoor then
	armoryClosed = armoryDoor:GetPivot()
	local cf, size = armoryDoor:GetBoundingBox()
	armoryHinge = cf * CFrame.new(0, 0, -size.Z / 2) -- charnière côté opposé à la poignée
end

local function swingArmoryDoor(open, duration)
	if not armoryDoor then
		return
	end
	local angle = Instance.new("NumberValue")
	angle.Value = open and 0 or -90
	local function apply(a)
		armoryDoor:PivotTo(armoryHinge * CFrame.Angles(0, math.rad(a), 0) * armoryHinge:Inverse() * armoryClosed)
	end
	angle.Changed:Connect(apply)
	local tween = TweenService:Create(angle, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = open and -90 or 0,
	})
	tween.Completed:Once(function()
		angle:Destroy()
	end)
	tween:Play()
end

---------------------------------------------------------------------------
-- Cinématique
---------------------------------------------------------------------------
local BreachCutscene = {}
local playing = false

function BreachCutscene.isPlaying()
	return playing
end

function BreachCutscene.play(ctx)
	if playing then
		return
	end
	playing = true

	local cancelled = false
	local viewers, skipped = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		viewers[p] = true
	end

	local function allSkipped()
		for p in pairs(viewers) do
			if p.Parent and not skipped[p] then
				return false
			end
		end
		return next(viewers) ~= nil
	end
	local skipConn = remote.OnServerEvent:Connect(function(player, msg)
		if msg == "Skip" and viewers[player] then
			skipped[player] = true
			if allSkipped() then
				cancelled = true
			end
		end
	end)

	-- Attente interrompue par « Passer » : renvoie false si la scène a été annulée.
	local function sleep(t)
		local t0 = os.clock()
		while os.clock() - t0 < t and not cancelled do
			task.wait(0.05)
		end
		return not cancelled
	end
	local function waitUntil(cond, timeout)
		local t0 = os.clock()
		while not cond() and not cancelled and os.clock() - t0 < timeout do
			task.wait(0.1)
		end
		return not cancelled
	end

	local shots = stage:WaitForChild("Shots")

	local door = ctx.securityDoor(CONFIG.CONTAINMENT_DOOR)
	local airlock = door and door.Parent -- Workspace.DClassBlock.Airlock

	-- Gardes
	local actors = Instance.new("Folder")
	actors.Name = "BreachCutsceneActors"
	actors.Parent = workspace
	local guards = {}
	for i, spawnPart in ipairs(ordered("Spawns")) do
		local g = FoundationGuard.new({ name = "Garde_" .. i, cframe = spawnPart.CFrame, parent = actors, skin = i })
		g.index = i
		g.lateral = (i % 2 == 1) and -1 or 1 -- formation 2 × 2
		g.back = math.floor((i - 1) / 2) * 2.6
		table.insert(guards, g)
	end
	local models = {}
	for _, g in ipairs(guards) do
		table.insert(models, g.model)
	end

	-- Données d'un plan : travelling si les repères <Nom>_Start / <Nom>_End existent, sinon plan de dos
	local function shotData(name)
		local a, b = shots:FindFirstChild(name .. "_Start"), shots:FindFirstChild(name .. "_End")
		if a and b then
			return { from = a.CFrame, to = b.CFrame, time = a:GetAttribute("Time") or 5, guards = models }
		end
		return { guards = models }
	end

	-- Enchaînement des plans : un travelling n'est jamais coupé avant SHOT_MIN_SHARE de sa durée.
	-- shot() passe tout de suite (et annule les plans en attente), queueShot() attend son tour.
	local shotEpoch, nextFreeAt = 0, 0
	local function holdOf(data)
		return data.from and (data.time or 5) * CONFIG.SHOT_MIN_SHARE or 0
	end
	local function shot(name, data)
		shotEpoch += 1
		remote:FireAllClients("Shot", name, data)
		nextFreeAt = os.clock() + holdOf(data)
	end
	local function queueShot(name)
		local data = shotData(name)
		local at = math.max(os.clock(), nextFreeAt)
		nextFreeAt = at + holdOf(data)
		local epoch = shotEpoch
		task.delay(at - os.clock(), function()
			if not cancelled and epoch == shotEpoch then
				remote:FireAllClients("Shot", name, data)
			end
		end)
	end

	-- 1. Alarme
	remote:FireAllClients("Start")
	shot(CONFIG.OPENING_SHOT, shotData(CONFIG.OPENING_SHOT))
	task.spawn(ctx.announce, CONFIG.ALERT_TEXT, "alert", 4)

	local flashing = true
	task.spawn(function()
		local on = true
		while flashing do
			ctx.setLights(on and 1 or 0.12, CONFIG.RED)
			on = not on
			task.wait(CONFIG.FLASH_PERIOD)
		end
	end)

	-- 2. Les gardes sortent de l'armurerie et courent vers la SALLE 001
	local route = ordered("Waypoints")

	local function moveTo(g, target, tolerance)
		local hum, root = g.humanoid, g.root
		hum:MoveTo(target)
		local issued, lastPos, lastMove = os.clock(), root.Position, os.clock()
		while not cancelled and g.model.Parent do
			if flat(root.Position - target).Magnitude < tolerance then
				return
			end
			if (root.Position - lastPos).Magnitude > 0.4 then
				lastPos, lastMove = root.Position, os.clock()
			elseif os.clock() - lastMove > 2.5 then
				-- Coincé (porte pas encore ouverte, autre garde…) : on le recale sur sa cible
				g.model:PivotTo(CFrame.new(target.X, root.Position.Y, target.Z) * root.CFrame.Rotation)
				return
			end
			if os.clock() - issued > 6 then -- MoveTo expire au bout de 8 s
				hum:MoveTo(target)
				issued = os.clock()
			end
			task.wait(0.05)
		end
	end

	local function runRoute(g)
		local prev = g.root.Position
		for _, wp in ipairs(route) do
			if cancelled then
				return
			end
			local single = wp:GetAttribute("SingleFile") == true
			local hold = wp:GetAttribute("Hold") == true
			if single then
				while not g.released and not cancelled do
					task.wait(0.05)
				end
			end
			local dir = flat(wp.Position - prev)
			dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(1, 0, 0)
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local spread = single and 0 or (wp:GetAttribute("Spread") or 0)
			local target = wp.Position + right * g.lateral * spread
			if hold then
				target -= dir * g.back
			end
			moveTo(g, target, hold and 0.9 or 1.8)
			prev = wp.Position
			if hold then
				g.humanoid:MoveTo(g.root.Position) -- s'arrête net
				g.atHold = true
			end
			local shotName = wp:GetAttribute("Shot")
			if g.index == 1 and shotName and shotName ~= "Door" then
				queueShot(shotName)
			end
		end
		g.done = true
	end

	local function finish()
		flashing = false
		remote:FireAllClients("End")
		skipConn:Disconnect()
		task.wait(CONFIG.END_FADE)
		for _, g in ipairs(guards) do
			g:destroy()
		end
		actors:Destroy()
		if door and door:GetAttribute("Open") then
			ctx.slideDoor(door, false, 0.8)
		end
		for _, name in ipairs(CONFIG.ACCESS_DOORS) do
			local d = ctx.securityDoor(name)
			if d then
				ctx.slideDoor(d, false, 1.2)
			end
		end
		swingArmoryDoor(false, 1.2)
		if airlock then
			for _, name in ipairs(CONFIG.PASS_THROUGH) do
				local p = airlock:FindFirstChild(name)
				if p and p:GetAttribute("CutsceneCanCollide") ~= nil then
					p.CanCollide = p:GetAttribute("CutsceneCanCollide")
					p:SetAttribute("CutsceneCanCollide", nil)
				end
			end
		end
		task.wait(CONFIG.FLASH_PERIOD)
		ctx.setLights(1)
		playing = false
	end

	if not sleep(CONFIG.ARMORY_DOOR_OPEN) then
		return finish()
	end
	swingArmoryDoor(true, 1.1)
	-- Les portes du trajet s'ouvrent devant les gardes (badge d'accès)
	for _, name in ipairs(CONFIG.ACCESS_DOORS) do
		local d = ctx.securityDoor(name)
		if d then
			ctx.slideDoor(d, true, 2.5)
		end
	end
	if not sleep(CONFIG.GUARDS_START - CONFIG.ARMORY_DOOR_OPEN) then
		return finish()
	end
	for i, g in ipairs(guards) do
		task.delay((i - 1) * 0.3, runRoute, g)
	end

	local allAtHold = function()
		for _, g in ipairs(guards) do
			if not g.atHold then
				return false
			end
		end
		return true
	end
	if not waitUntil(allAtHold, CONFIG.HOLD_TIMEOUT) then
		return finish()
	end

	-- 3. Gros plan : la porte de confinement s'ouvre, les gardes passent un par un, elle se referme
	local doorShotTime = CONFIG.DOOR_OPEN_TIME + #guards * CONFIG.CROSS_INTERVAL + CONFIG.DOOR_CLOSE_TIME + 3
	shot("Door", { from = shots.Door_Start.CFrame, to = shots.Door_End.CFrame, time = doorShotTime })
	if not sleep(0.8) then
		return finish()
	end
	if airlock then
		for _, name in ipairs(CONFIG.PASS_THROUGH) do
			local p = airlock:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p:SetAttribute("CutsceneCanCollide", p.CanCollide)
				p.CanCollide = false
			end
		end
	end
	if door then
		ctx.slideDoor(door, true, CONFIG.DOOR_OPEN_TIME)
	end
	if not sleep(CONFIG.DOOR_OPEN_TIME * 0.8) then
		return finish()
	end
	for _, g in ipairs(guards) do
		g.released = true
		if not sleep(CONFIG.CROSS_INTERVAL) then
			return finish()
		end
	end
	local allThrough = function()
		for _, g in ipairs(guards) do
			if not g.done then
				return false
			end
		end
		return true
	end
	if not waitUntil(allThrough, CONFIG.CROSS_TIMEOUT) or not sleep(0.3) then
		return finish()
	end
	if door then
		ctx.slideDoor(door, false, CONFIG.DOOR_CLOSE_TIME)
	end
	sleep(CONFIG.DOOR_CLOSE_TIME + 1)

	-- 4. Retour au jeu
	return finish()
end

return BreachCutscene
