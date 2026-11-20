--[[
	CrazyDClass (Script) — à placer dans ServerScriptService.
	Nécessite SCPCodex (ServerScriptService), SCPTips (ReplicatedStorage) et le décor
	Workspace.Hub.Decor.CelluleIsolement (repère FouSpot, néon CellTube).

	D-0451 « Le Fou » : Classe D enfermé dans la cellule d'isolement du hall de transit.
	On lui parle à travers les barreaux (ProximityPrompt « Parler »). Il donne des conseils
	sur les anomalies que le joueur a déjà rencontrées (dossier SCPCodex), un conseil par conversation.

	Le PNJ est construit au démarrage (Players:CreateHumanoidModelFromDescription), en combinaison orange,
	immobile, avec des tics de tête et un balancement. Pendant une conversation, il se tourne vers le joueur.

	Ambiance du hall gérée ici aussi : néon de la cellule qui grésille, voyants des caméras qui clignotent.

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

local Tips = require(ReplicatedStorage:WaitForChild("SCPTips"))

local CONFIG = {
	MATRICULE = "D-0451",
	ORANGE = Color3.fromRGB(226, 110, 20),
	SKIN = Color3.fromRGB(214, 170, 138),
	PROMPT_DISTANCE = 9,
	TALK_COOLDOWN = 1.5, -- entre deux conversations d'un même joueur (s)
	TALK_TIMEOUT = 40, -- conversation considérée finie sans réponse du client (s)
	VOICE_SOUND_ID = nil, -- ex. "rbxassetid://123456" : marmonnement à chaque réplique
}

local hub = workspace:WaitForChild("Hub")
local decor = hub:WaitForChild("Decor")
local cell = decor:WaitForChild("CelluleIsolement")
local spot = cell:WaitForChild("FouSpot")

local remote = ReplicatedStorage:FindFirstChild("FouDialog") or Instance.new("RemoteEvent")
remote.Name = "FouDialog"
remote.Parent = ReplicatedStorage

---------------------------------------------------------------------------
-- Le PNJ
---------------------------------------------------------------------------
local function buildNPC()
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = CONFIG.SKIN
	desc.TorsoColor = CONFIG.ORANGE
	desc.LeftArmColor = CONFIG.ORANGE
	desc.RightArmColor = CONFIG.ORANGE
	desc.LeftLegColor = CONFIG.ORANGE
	desc.RightLegColor = CONFIG.ORANGE
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
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			-- combinaison orange (la HumanoidDescription seule donne un orange trop clair)
			if d.Name ~= "Head" and d.Name ~= "HumanoidRootPart" then
				d.Color = CONFIG.ORANGE
			end
		end
	end
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
	-- Matricule sur la poitrine, comme les Classe D du bloc
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.8, 0.3)
		label.Position = UDim2.fromScale(0.1, 0.12)
		label.Font = Enum.Font.Michroma
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(25, 25, 25)
		label.Text = CONFIG.MATRICULE
		label.Parent = gui
		gui.Parent = torso
	end
	-- Posé au sol, au repère FouSpot
	model:PivotTo(spot.CFrame)
	local cf, size = model:GetBoundingBox()
	local floorY = spot.Position.Y - spot.Size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (cf.Y - size.Y / 2), 0))
	model.Parent = cell
	return model
end

local npc = buildNPC()
if not npc then
	return
end
local root = npc:WaitForChild("HumanoidRootPart")
local homeCF = root.CFrame

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Parler"
prompt.ObjectText = Tips.SPEAKER
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = CONFIG.PROMPT_DISTANCE
prompt.RequiresLineOfSight = false
prompt.HoldDuration = 0
prompt.Parent = root

---------------------------------------------------------------------------
-- Tics : tête qui part de travers, balancement d'avant en arrière
---------------------------------------------------------------------------
-- Pose procédurale : les rigs récents ont des articulations AnimationConstraint (pas de C0 à modifier)
-- et le serveur n'a pas d'animations. Toutes les parts sont donc ancrées et replacées à la main,
-- en pivotant le haut du corps autour de la taille et la tête autour du cou.
local UPPER = {
	UpperTorso = true,
	Head = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}
local rest = {} -- part -> CFrame au repos, relatif à la racine
for _, d in ipairs(npc:GetDescendants()) do
	if d:IsA("BasePart") and d ~= root then
		d.Anchored = true
		rest[d] = root.CFrame:ToObjectSpace(d.CFrame)
	end
end
local function pivotOf(partName, attName)
	local part = npc:FindFirstChild(partName)
	local att = part and part:FindFirstChild(attName)
	local pos = att and att.WorldPosition or (part and part.Position) or root.Position
	return root.CFrame:ToObjectSpace(CFrame.new(pos) * root.CFrame.Rotation)
end
local waistRel = pivotOf("UpperTorso", "WaistRigAttachment")
local neckRel = pivotOf("Head", "NeckRigAttachment")

-- Angles en degrés ; lean < 0 = penché en avant, pitch < 0 = tête baissée
local pose = { lean = 0, pitch = 0, yaw = 0, roll = 0 }
local target = { lean = 0, pitch = 0, yaw = 0, roll = 0 }
local headSpeed = 4 -- vitesse de rattrapage de la tête (grand = tic brusque)

local function applyPose()
	local rootCF = root.CFrame
	local waist = rootCF * waistRel
	local bend = waist * CFrame.Angles(math.rad(pose.lean), 0, 0) * waist:Inverse()
	local neck = bend * (rootCF * neckRel)
	local turn = neck * CFrame.Angles(math.rad(pose.pitch), math.rad(pose.yaw), math.rad(pose.roll)) * neck:Inverse()
	for part, rel in pairs(rest) do
		local cf = rootCF * rel
		if UPPER[part.Name] then
			cf = bend * cf
			if part.Name == "Head" then
				cf = turn * cf
			end
		end
		part.CFrame = cf
	end
end

local talkingTo = nil -- joueur en conversation (le PNJ le regarde)

-- Tics de la tête : mouvement lent, ou tic brusque une fois sur quatre
task.spawn(function()
	while npc.Parent do
		if not talkingTo then
			if math.random() < 0.25 then
				target.pitch, target.yaw, target.roll = math.random(-25, 10), math.random(-60, 60), math.random(-25, 25)
				headSpeed = 30
			else
				target.pitch, target.yaw, target.roll = math.random(-20, -5), math.random(-20, 20), math.random(-8, 8)
				headSpeed = 3
			end
		end
		task.wait(0.6 + math.random() * 2.2)
	end
end)

-- Balancement d'avant en arrière + rendu de la pose (15 images/s)
task.spawn(function()
	local t = 0
	while npc.Parent do
		local dt = task.wait(1 / 15)
		t += dt
		if not talkingTo then
			target.lean = -(6 + math.sin(t * 2.2) * 7)
		end
		local a = math.min(1, dt * headSpeed)
		pose.lean += (target.lean - pose.lean) * math.min(1, dt * 8)
		pose.pitch += (target.pitch - pose.pitch) * a
		pose.yaw += (target.yaw - pose.yaw) * a
		pose.roll += (target.roll - pose.roll) * a
		applyPose()
	end
end)

---------------------------------------------------------------------------
-- Conversation
---------------------------------------------------------------------------
local function pick(list)
	return list[math.random(1, #list)]
end

local function buildLines(player)
	local data = Codex.get(player)
	-- Anomalie dont il va parler : celle dont le joueur a entendu le moins de conseils
	local best, bestHeard
	for _, id in ipairs(Tips.ORDER) do
		local entry = Tips.ENTRIES[id]
		if data.seen[id] and entry then
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

local busy = {} -- player -> os.clock() du début de la conversation
local lastTalk = {}

local function endTalk(player)
	busy[player] = nil
	lastTalk[player] = os.clock()
	if talkingTo == player then
		talkingTo = nil
		root.CFrame = homeCF
	end
end

prompt.Triggered:Connect(function(player)
	if busy[player] or os.clock() - (lastTalk[player] or 0) < CONFIG.TALK_COOLDOWN then
		return
	end
	busy[player] = os.clock()
	-- Se tourne vers le joueur et le fixe
	local char = player.Character
	local pr = char and char:FindFirstChild("HumanoidRootPart")
	if pr then
		talkingTo = player
		local flat = Vector3.new(pr.Position.X, root.Position.Y, pr.Position.Z)
		root.CFrame = CFrame.lookAt(root.Position, flat)
		target.lean, target.pitch, target.yaw, target.roll = -10, -6, 0, 14 -- tête penchée, il le fixe
		headSpeed = 12
	end
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
	remote:FireClient(player, "Open", Tips.SPEAKER, buildLines(player))
	-- Sécurité : si le client ne répond pas
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
	endTalk(player)
	lastTalk[player] = nil
end)

---------------------------------------------------------------------------
-- Ambiance : néon de la cellule qui grésille, voyants des caméras
---------------------------------------------------------------------------
local tube = cell:FindFirstChild("CellTube")
local tubeLight = tube and tube:FindFirstChildOfClass("PointLight")
if tube and tubeLight then
	task.spawn(function()
		while tube.Parent do
			task.wait(2 + math.random() * 6)
			for _ = 1, math.random(2, 6) do
				local on = math.random() > 0.5
				tubeLight.Enabled = on
				tube.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
				task.wait(0.04 + math.random() * 0.1)
			end
			tubeLight.Enabled = true
			tube.Material = Enum.Material.Neon
		end
	end)
end

local leds = {}
for _, d in ipairs(decor:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("Blink") then
		table.insert(leds, d)
	end
end
task.spawn(function()
	local on = true
	while true do
		on = not on
		for _, led in ipairs(leds) do
			led.Transparency = on and 0 or 0.85
		end
		task.wait(on and 0.25 or 1.4)
	end
end)
