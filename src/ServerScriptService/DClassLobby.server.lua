--[[
	DClassLobby (Script) — à placer dans ServerScriptService.

	Spawn / lobby du bloc cellulaire des Classe D (1 à 4 joueurs).
	Nécessite le modèle Workspace.DClassBlock (cellules taguées "PlayerCell", portes "CellDoor" / "SecurityDoor",
	néons "BlockLight" / "CellLight", gyrophares "AlarmLight", écrans "GuardScreen", horloges "WallClock",
	tableau "TestBoard").

	Déroulé :
	  1. Chaque joueur reçoit une cellule (1 à 4) et un matricule (D-XXXX), et porte la combinaison orange.
	  2. Attente des autres joueurs (WAIT_FOR_PLAYERS s max, ou dès que la cellule 4 est occupée).
	  3. Appel au haut-parleur : « D-9341, préparez-vous pour le test. »
	  4. Brèche : cinématique (ServerScriptService.BreachCutscene) — alarme, quatre gardes sortent de
	     l'armurerie et entrent dans la SALLE 001. Puis les lumières clignotent, l'alarme se déclenche, les écrans du poste de garde grésillent,
	     les portes des cellules s'ouvrent toutes seules, puis les portes vers le briefing et le sas.
	  5. Quand tous les joueurs vivants sont regroupés dans le sas (ou après REGROUP_TIMEOUT s),
	     la porte de la SALLE 001 s'ouvre et ServerStorage.LobbyFinished est déclenché.
]]

-- Ne tourne que sur un serveur de partie, pas dans le hall de transit (voir HubServer).
while workspace:GetAttribute("ServerMode") ~= "Match" do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local BreachCutscene = require(script.Parent:WaitForChild("BreachCutscene"))

local CONFIG = {
	MAX_PLAYERS = 4,
	WAIT_FOR_PLAYERS = RunService:IsStudio() and 8 or 25, -- attente max après le 1er joueur (s)
	REGROUP_TIMEOUT = 90, -- ouverture forcée de la SALLE 001 (s)
	START_CLOCK = 8 * 60 + 57, -- 08:57 (minutes)
	TEST_SCP = "SCP-173",
	PA_SOUND_ID = nil, -- ex. "rbxassetid://123456" : bip d'annonce
	ALARM_SOUND_ID = nil, -- sirène (en boucle)
	DOOR_SOUND_ID = nil, -- porte blindée qui coulisse
	ORANGE = Color3.fromRGB(226, 110, 20),
}

local block = workspace:WaitForChild("DClassBlock")
local airlock = block:WaitForChild("Airlock")

-- Communication avec les clients (sous-titres du haut-parleur)
local paRemote = ReplicatedStorage:FindFirstChild("LobbyPA") or Instance.new("RemoteEvent")
paRemote.Name = "LobbyPA"
paRemote.Parent = ReplicatedStorage

local finished = ServerStorage:FindFirstChild("LobbyFinished") or Instance.new("BindableEvent")
finished.Name = "LobbyFinished"
finished.Parent = ServerStorage

local function setState(state)
	workspace:SetAttribute("LobbyState", state)
end
setState("Waiting")

---------------------------------------------------------------------------
-- Cellules et matricules
---------------------------------------------------------------------------
local playerCells = {} -- index -> cellule
for _, cell in ipairs(CollectionService:GetTagged("PlayerCell")) do
	playerCells[cell:GetAttribute("PlayerCell")] = cell
end

local usedNumbers = {}
for _, cell in ipairs(block.Cells:GetChildren()) do
	local n = tonumber(string.match(cell:GetAttribute("Matricule") or "", "%d+"))
	if n then
		usedNumbers[n] = true
	end
end

local assigned = {} -- player -> index de cellule
local cellOwner = {} -- index -> player

local function newMatricule()
	local n
	repeat
		n = math.random(1000, 9999)
	until not usedNumbers[n]
	usedNumbers[n] = true
	return "D-" .. n
end

local function setCellSign(cell, text)
	local label = cell.MatriculeSign:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Text")
	label.Text = text
end

local function updateBoard()
	local lines = { "<b>TESTS DU JOUR — 19/11</b>", "" }
	local minutes = 9 * 60
	for i = 1, CONFIG.MAX_PLAYERS do
		local p = cellOwner[i]
		if p then
			table.insert(lines, string.format("%s → %s → %02dh%02d", p:GetAttribute("Matricule"), CONFIG.TEST_SCP, minutes // 60, minutes % 60))
			minutes += 15
		end
	end
	if #lines == 2 then
		table.insert(lines, "—")
	end
	for _, board in ipairs(CollectionService:GetTagged("TestBoard")) do
		board:FindFirstChildOfClass("SurfaceGui").Text.Text = table.concat(lines, "\n")
	end
end

local function assignCell(player)
	local index
	for i = 1, CONFIG.MAX_PLAYERS do
		if not cellOwner[i] and playerCells[i] then
			index = i
			break
		end
	end
	if not index then
		-- Plus de 4 joueurs : on partage les cellules (règle MaxPlayers = 4 dans les paramètres du jeu)
		index = (#Players:GetPlayers() - 1) % CONFIG.MAX_PLAYERS + 1
	else
		cellOwner[index] = player
	end
	assigned[player] = index
	local cell = playerCells[index]
	local matricule = newMatricule()
	player:SetAttribute("Matricule", matricule)
	player:SetAttribute("CellName", string.match(cell.Name, "Cell_(.+)") or cell.Name)
	setCellSign(cell, matricule)
	updateBoard()
end

local function releaseCell(player)
	local index = assigned[player]
	assigned[player] = nil
	if index and cellOwner[index] == player then
		cellOwner[index] = nil
		setCellSign(playerCells[index], "D-????")
	end
	updateBoard()
end

---------------------------------------------------------------------------
-- Combinaison orange + apparition dans la cellule
---------------------------------------------------------------------------
local CLOTHING_TYPES = {
	[Enum.AccessoryType.Shirt] = true,
	[Enum.AccessoryType.TShirt] = true,
	[Enum.AccessoryType.Pants] = true,
	[Enum.AccessoryType.Shorts] = true,
	[Enum.AccessoryType.Jacket] = true,
	[Enum.AccessoryType.Sweater] = true,
	[Enum.AccessoryType.DressSkirt] = true,
	[Enum.AccessoryType.LeftShoe] = true,
	[Enum.AccessoryType.RightShoe] = true,
}

local function dressAsDClass(player, character)
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic") then
			item:Destroy()
		elseif item:IsA("Accessory") and CLOTHING_TYPES[item.AccessoryType] then
			item:Destroy()
		end
	end
	local bc = character:FindFirstChildOfClass("BodyColors")
	if bc then
		bc.TorsoColor3 = CONFIG.ORANGE
		bc.LeftArmColor3 = CONFIG.ORANGE
		bc.RightArmColor3 = CONFIG.ORANGE
		bc.LeftLegColor3 = CONFIG.ORANGE
		bc.RightLegColor3 = CONFIG.ORANGE
	end
	-- matricule imprimé sur la poitrine
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and not torso:FindFirstChild("MatriculeTag") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "MatriculeTag"
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
		label.Text = player:GetAttribute("Matricule") or "D-????"
		label.Parent = gui
		gui.Parent = torso
	end
end

local function placeInCell(player, character)
	local index = assigned[player]
	local cell = index and playerCells[index]
	if not cell then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		character:PivotTo(cell.Spawn.CFrame + Vector3.new(0, 3, 0))
	end
end

local function onPlayerAdded(player)
	assignCell(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(placeInCell, player, character)
	end)
	player.CharacterAppearanceLoaded:Connect(function(character)
		dressAsDClass(player, character)
	end)
	if player.Character then
		task.defer(placeInCell, player, player.Character)
		dressAsDClass(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end
Players.PlayerRemoving:Connect(releaseCell)

---------------------------------------------------------------------------
-- Effets : portes, lumières, haut-parleurs, écrans, horloges
---------------------------------------------------------------------------
local function playAt(part, id, volume, looped)
	if not id or not part then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.Looped = looped or false
	s.RollOffMaxDistance = 120
	s.Parent = part
	s:Play()
	if not looped then
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
	return s
end

-- Position fermée de chaque porte, relevée au démarrage (les portes sont fermées dans la place).
-- On ne se fie pas à une position enregistrée : si le bloc est déplacé dans Studio, ça reste juste.
local closedCF = {}
for _, tag in ipairs({ "CellDoor", "SecurityDoor" }) do
	for _, door in ipairs(CollectionService:GetTagged(tag)) do
		if door.PrimaryPart then
			closedCF[door] = door.PrimaryPart.CFrame
		end
	end
end

local function slideDoor(door, open, duration)
	local main = door.PrimaryPart
	local closed = closedCF[door] or main.CFrame
	closedCF[door] = closed
	local slide = door:GetAttribute("Slide") or 6
	local offset = door:GetAttribute("SlideAxis") == "X" and CFrame.new(slide, 0, 0) or CFrame.new(0, 0, slide)
	local target = open and (closed * offset) or closed
	TweenService:Create(main, TweenInfo.new(duration or 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = target }):Play()
	playAt(main, CONFIG.DOOR_SOUND_ID, 0.8)
	door:SetAttribute("Open", open)
end

local function securityDoor(name)
	for _, d in ipairs(CollectionService:GetTagged("SecurityDoor")) do
		if d.Name == name then
			return d
		end
	end
end

-- Lumières du bloc (néons du couloir + des cellules)
local lights = {}
for _, tag in ipairs({ "BlockLight", "CellLight" }) do
	for _, tube in ipairs(CollectionService:GetTagged(tag)) do
		local l = tube:FindFirstChildOfClass("SurfaceLight")
		if l then
			table.insert(lights, { tube = tube, light = l, base = tube:GetAttribute("BaseBrightness") or l.Brightness })
		end
	end
end

local function setLights(level, color)
	for _, e in ipairs(lights) do
		e.light.Enabled = level > 0
		e.light.Brightness = e.base * level
		e.light.Color = color or Color3.fromRGB(235, 242, 255)
		e.tube.Material = level > 0 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		e.tube.Color = level > 0 and (color or Color3.fromRGB(235, 245, 255)) or Color3.fromRGB(90, 92, 96)
	end
end

local function flicker(duration)
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		for _, e in ipairs(lights) do
			local on = math.random() > 0.45
			e.light.Enabled = on
			e.tube.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
		task.wait(0.05 + math.random() * 0.12)
	end
end

local function setAlarm(on)
	for _, dome in ipairs(CollectionService:GetTagged("AlarmLight")) do
		for _, l in ipairs(dome:GetChildren()) do
			if l:IsA("Light") then
				l.Enabled = on
			end
		end
		dome.Material = on and Enum.Material.Neon or Enum.Material.Glass
		dome.Color = on and Color3.fromRGB(255, 40, 30) or Color3.fromRGB(90, 15, 15)
	end
end

local speakers = CollectionService:GetTagged("PASpeaker")
local function announce(text, kind, hold)
	paRemote:FireAllClients(text, kind or "pa", hold or 4)
	for _, s in ipairs(speakers) do
		playAt(s, CONFIG.PA_SOUND_ID, 0.6)
	end
	task.wait(hold or 4)
end

local function screensLost()
	for _, scr in ipairs(CollectionService:GetTagged("GuardScreen")) do
		local gui = scr:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if not label then
			continue
		end
		label.Text = "▓▒░ SIGNAL PERDU ░▒▓\n" .. (scr:GetAttribute("Label") or "")
		label.TextColor3 = Color3.fromRGB(255, 90, 80)
		label.BackgroundColor3 = Color3.fromRGB(40, 40, 42)
	end
	for _, b in ipairs(CollectionService:GetTagged("DoorButton")) do
		b.Color = Color3.fromRGB(255, 40, 30)
	end
	for _, led in ipairs(CollectionService:GetTagged("DoorStatusLed")) do
		led.Color = Color3.fromRGB(40, 255, 80)
	end
end

-- Horloges murales (le temps passe, à partir de 08:57)
local clockStart = os.clock()
task.spawn(function()
	local clocks = CollectionService:GetTagged("WallClock")
	for _, c in ipairs(clocks) do
		local label = c:FindFirstChildOfClass("SurfaceGui").Text
		label.TextWrapped = false
	end
	while true do
		local minutes = CONFIG.START_CLOCK + math.floor((os.clock() - clockStart) / 20) -- 1 min de jeu = 20 s
		local text = string.format("%02d:%02d", (minutes // 60) % 24, minutes % 60)
		for _, c in ipairs(clocks) do
			c:FindFirstChildOfClass("SurfaceGui").Text.Text = text
		end
		task.wait(1)
	end
end)

---------------------------------------------------------------------------
-- Déroulé
---------------------------------------------------------------------------
local function alivePlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			table.insert(list, p)
		end
	end
	return list
end

local function inAirlock(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	-- Le sas va de la porte TestDoor à la porte SALLE 001 (positions relevées au démarrage)
	local a, b = closedCF[securityDoor("TestDoor")], closedCF[securityDoor("Room001Door")]
	if not (a and b) then
		return false
	end
	local p = root.Position
	return p.X > a.X and p.X < b.X - 0.4 and math.abs(p.Z - a.Z) < 4.5
end

local function run()
	-- Nuit : lumières tamisées, puis réveil du bloc
	setLights(0.25)
	while #Players:GetPlayers() == 0 do
		task.wait(0.5)
	end
	task.wait(2)
	setLights(1)
	announce("Réveil du bloc D. Restez dans vos cellules.", "pa", 4)

	-- Attente des autres Classe D (taille du groupe choisie dans le sas du hall, attribut PartySize)
	local expected = math.clamp(workspace:GetAttribute("PartySize") or CONFIG.MAX_PLAYERS, 1, CONFIG.MAX_PLAYERS)
	workspace:SetAttribute("LobbyExpected", expected)
	local deadline = os.clock() + CONFIG.WAIT_FOR_PLAYERS
	while os.clock() < deadline and #Players:GetPlayers() < expected do
		workspace:SetAttribute("LobbyCountdown", math.ceil(deadline - os.clock()))
		workspace:SetAttribute("LobbyPlayers", #Players:GetPlayers())
		task.wait(0.25)
	end
	workspace:SetAttribute("LobbyCountdown", nil)

	-- Appel
	-- Un seul message pour tout l'appel (une bulle par annonce : on en limite le nombre)
	setState("RollCall")
	local called = {}
	for i = 1, CONFIG.MAX_PLAYERS do
		local p = cellOwner[i]
		if p and p.Parent then
			table.insert(called, p:GetAttribute("Matricule"))
		end
	end
	if #called > 0 then
		announce(string.format("Appel : %s. Préparez-vous pour le test.", table.concat(called, ", ")), "pa", 5)
	end
	task.wait(3)

	-- Brèche de confinement
	setState("Breach")
	setAlarm(true)
	local siren = playAt(speakers[1], CONFIG.ALARM_SOUND_ID, 0.7, true)

	-- Cinématique : alarme, les gardes partent confiner la SALLE 001 (rend la main à la fin de la scène)
	BreachCutscene.play({
		slideDoor = slideDoor,
		securityDoor = securityDoor,
		setLights = setLights,
		announce = announce,
	})

	flicker(2.5)
	setLights(0)
	task.wait(1.4)
	setLights(0.35, Color3.fromRGB(255, 190, 170))
	screensLost()
	task.wait(1.5)

	local doors = CollectionService:GetTagged("CellDoor")
	for i = #doors, 2, -1 do
		local j = math.random(1, i)
		doors[i], doors[j] = doors[j], doors[i]
	end
	for _, door in ipairs(doors) do
		slideDoor(door, true, 1.2 + math.random() * 0.8)
		task.wait(0.08 + math.random() * 0.15)
	end
	task.spawn(announce, "Portes déverrouillées. Rejoignez le sas.", "alert", 5)
	task.wait(1.5)
	slideDoor(securityDoor("HallDoor"), true, 2.5)
	task.wait(1)
	slideDoor(securityDoor("TestDoor"), true, 2.5)
	slideDoor(securityDoor("InnerDoor"), true, 2.5)
	task.wait(3)
	setState("Open")

	-- Regroupement dans le sas, puis SALLE 001
	local t0 = os.clock()
	while os.clock() - t0 < CONFIG.REGROUP_TIMEOUT do
		local alive = alivePlayers()
		local ready = #alive > 0
		local count = 0
		for _, p in ipairs(alive) do
			if inAirlock(p) then
				count += 1
			else
				ready = false
			end
		end
		workspace:SetAttribute("LobbyRegroup", string.format("%d/%d", count, #alive))
		if ready then
			break
		end
		task.wait(0.5)
	end
	workspace:SetAttribute("LobbyRegroup", nil)
	slideDoor(securityDoor("Room001Door"), true, 3)
	setState("Started")
	if siren then
		siren.Volume = 0.3
	end
	finished:Fire(alivePlayers())
end

task.spawn(run)
