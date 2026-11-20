--[[
	HubServer (Script) — à placer dans ServerScriptService.

	Hall de transit du Site-19 (Workspace.Hub) : tous les joueurs du serveur s'y retrouvent et se voient.
	Pour lancer une partie, on entre dans un des sas (modèles tagués "HubSas") :
	  1. Le premier entré devient l'hôte : il choisit SOLO, 2, 3 ou 4 Classe D.
	  2. Les autres joueurs entrent dans le sas tant qu'il reste de la place (porte ouverte, voyant orange).
	  3. Compte à rebours (raccourci quand le sas est plein, ou « Lancer maintenant » par l'hôte),
	     portes fermées, décontamination, puis téléportation du groupe.

	Une partie = un serveur réservé de CETTE place (TeleportOptions.ShouldReserveServer).
	Ce script règle workspace.ServerMode : "Hub" sur un serveur public, "Match" sur un serveur réservé.
	Les scripts de partie (DClassLobby, SCP173AI, BlinkAndWatch, DClassHUD) attendent "Match".

	Studio ne peut pas téléporter : au départ d'un sas, ce serveur bascule directement en "Match"
	(tous les joueurs vont dans le bloc D). Pour tester le bloc D sans passer par le hall,
	mets l'attribut StudioStart = "Match" sur ce script.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local CONFIG = {
	MAX_SIZE = 4, -- taille max d'un groupe (= cellules du bloc D)
	SETUP_TIMEOUT = 25, -- l'hôte a ce temps pour choisir le mode, sinon il est sorti du sas (s)
	WAIT_TIME = 30, -- attente des coéquipiers une fois le mode choisi (s)
	FULL_TIME = 5, -- compte à rebours quand le sas est plein (s)
	LAUNCH_TIME = 5, -- portes fermées + décontamination avant le transfert (s)
	TELEPORT_TIMEOUT = 20, -- au-delà, le transfert est considéré comme raté (s)
	TICK = 0.2,
	DOOR_SOUND_ID = nil, -- ex. "rbxassetid://123456" : porte de sas
	DEPART_SOUND_ID = nil, -- sifflement de décontamination
}

---------------------------------------------------------------------------
-- Mode du serveur
---------------------------------------------------------------------------
local isReserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local mode = isReserved and "Match" or "Hub"
if RunService:IsStudio() and script:GetAttribute("StudioStart") == "Match" then
	mode = "Match"
end

local hub = workspace:WaitForChild("Hub")
local block = workspace:FindFirstChild("DClassBlock")

-- Taille du groupe, lue dans les données de téléportation du premier joueur arrivé
local function readPartySize(player)
	if workspace:GetAttribute("PartySize") then
		return
	end
	local ok, data = pcall(function()
		return player:GetJoinData().TeleportData
	end)
	if ok and type(data) == "table" and tonumber(data.partySize) then
		workspace:SetAttribute("PartySize", math.clamp(math.floor(tonumber(data.partySize)), 1, CONFIG.MAX_SIZE))
	end
end

-- Éclairage du hall. Les lampes du hall sont des lumières locales, que Roblox ne rend pas en qualité
-- graphique basse (et toute qualité « Automatique » démarre basse) : avec l'ambiance sombre du jeu,
-- le hall serait noir à l'apparition et sur les appareils modestes. En mode Hall, l'ambiance de base
-- est donc relevée ; elle est rétablie au passage en partie (bloc D, ambiance sombre voulue).
local Lighting = game:GetService("Lighting")
local HUB_LIGHTING = {
	Ambient = Color3.fromRGB(138, 142, 150),
	OutdoorAmbient = Color3.fromRGB(120, 124, 132),
	EnvironmentDiffuseScale = 0.4,
	ExposureCompensation = 0,
}
local savedLighting = nil
local function useHubLighting(on)
	if on and not savedLighting then
		savedLighting = {}
		for k, v in pairs(HUB_LIGHTING) do
			savedLighting[k] = Lighting[k]
			Lighting[k] = v
		end
	elseif not on and savedLighting then
		for k, v in pairs(savedLighting) do
			Lighting[k] = v
		end
		savedLighting = nil
	end
end

local function enterMatch(partySize)
	useHubLighting(false)
	if partySize then
		workspace:SetAttribute("PartySize", partySize)
	end
	if block then
		block.Parent = workspace
	end
	workspace:SetAttribute("ServerMode", "Match")
	-- Le hall ne sert plus : on le retire (après que DClassLobby a replacé les joueurs dans les cellules)
	task.delay(1, function()
		hub:Destroy()
	end)
end

if mode == "Match" then
	Players.PlayerAdded:Connect(readPartySize)
	for _, p in ipairs(Players:GetPlayers()) do
		readPartySize(p)
	end
	enterMatch(nil)
	return
end

-- Hub : le bloc D n'est pas utilisé sur ce serveur, on le range (moins de pièces et de lumières à rendre)
if block then
	block.Parent = ServerStorage
end
workspace:SetAttribute("ServerMode", "Hub")
useHubLighting(true)

---------------------------------------------------------------------------
-- Communication avec les clients
---------------------------------------------------------------------------
-- Client -> serveur : ("SetSize", n) / ("Launch") / ("Leave")
-- Serveur -> client : ("Toast", texte, couleur?)
local remote = ReplicatedStorage:FindFirstChild("HubRemote") or Instance.new("RemoteEvent")
remote.Name = "HubRemote"
remote.Parent = ReplicatedStorage

local function toast(player, text, kind)
	remote:FireClient(player, "Toast", text, kind or "info")
end

---------------------------------------------------------------------------
-- Sas
---------------------------------------------------------------------------
local COLORS = {
	Free = Color3.fromRGB(60, 230, 110),
	Setup = Color3.fromRGB(255, 190, 40),
	Waiting = Color3.fromRGB(255, 140, 30),
	Launching = Color3.fromRGB(255, 45, 35),
}

local sasList = {}
local sasOf = {} -- player -> sas

local function playAt(part, id, volume)
	if not id or not part then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.RollOffMaxDistance = 80
	s.Parent = part
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local function setDoor(sas, open)
	if sas.doorOpen == open then
		return
	end
	sas.doorOpen = open
	local door = sas.door
	local target = open and (sas.doorClosed * CFrame.new(door:GetAttribute("Slide") or 8.4, 0, 0)) or sas.doorClosed
	TweenService:Create(door, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = target }):Play()
	playAt(door, CONFIG.DOOR_SOUND_ID, 0.7)
end

local function memberNames(sas)
	local names = {}
	for i, p in ipairs(sas.members) do
		table.insert(names, (p == sas.host and "★ " or "") .. p.DisplayName)
	end
	return table.concat(names, "\n")
end

local STATUS_TEXT = {
	Free = "LIBRE",
	Setup = "CONFIGURATION",
	Waiting = "EMBARQUEMENT",
	Launching = "DÉPART",
}

local function refresh(sas)
	local m = sas.model
	local count = #sas.members
	local countdown = sas.deadline and math.max(0, math.ceil(sas.deadline - os.clock())) or nil
	m:SetAttribute("State", sas.state)
	m:SetAttribute("Size", sas.size)
	m:SetAttribute("Count", count)
	m:SetAttribute("Countdown", countdown)
	m:SetAttribute("Host", sas.host and sas.host.UserId or nil)
	m:SetAttribute("Members", memberNames(sas))

	-- Porte : ouverte tant qu'on peut entrer
	local joinable = sas.state == "Free" or (sas.state == "Waiting" and count < sas.size)
	setDoor(sas, joinable)

	-- Voyant + écran au-dessus de la porte
	local color = COLORS[sas.state]
	if sas.state == "Waiting" and count >= sas.size then
		color = COLORS.Setup
	end
	sas.lamp.Color = color
	local light = sas.lamp:FindFirstChildOfClass("Light")
	if light then
		light.Color = color
	end
	local status, info
	if sas.state == "Free" then
		status, info = "DISPONIBLE", "PRÉSENTEZ-VOUS POUR AFFECTATION"
	elseif sas.state == "Setup" then
		status, info = "CONFIGURATION", (sas.host and sas.host.DisplayName or "?") .. " DÉCLARE L'EFFECTIF"
	elseif sas.state == "Waiting" then
		local label = sas.size == 1 and "SOLO" or (sas.size .. " SUJETS")
		status = string.format("%s · %d/%d", label, count, sas.size)
		info = count >= sas.size and string.format("EFFECTIF COMPLET · TRANSFERT %ds", countdown or 0)
			or string.format("PLACES VACANTES · TRANSFERT %ds", countdown or 0)
	else
		status, info = "TRANSFERT", "DÉCONTAMINATION EN COURS"
	end
	if sas.statusLabel then
		sas.statusLabel.Text = status
		sas.statusLabel.TextColor3 = color
	end
	if sas.infoLabel then
		sas.infoLabel.Text = info
	end
end

local function reset(sas)
	sas.state = "Free"
	sas.size = nil
	sas.host = nil
	sas.deadline = nil
	sas.launchToken = nil
	table.clear(sas.members)
	if sas.mist then
		sas.mist.Enabled = false
	end
	refresh(sas)
end

local function removeMember(sas, player)
	local i = table.find(sas.members, player)
	if not i then
		return
	end
	table.remove(sas.members, i)
	sasOf[player] = nil
	if player.Parent then
		player:SetAttribute("HubSas", nil)
	end
	if #sas.members == 0 then
		reset(sas)
		return
	end
	if sas.host == player then
		sas.host = sas.members[1]
		toast(sas.host, "Responsabilité du groupe transférée. Vous êtes désigné hôte du sas.", "info")
	end
	refresh(sas)
end

local function eject(sas, player, reason)
	removeMember(sas, player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local offset = Vector3.new((math.random() - 0.5) * 4, 3, 0)
		player.Character:PivotTo(sas.exit.CFrame + offset)
	end
	if reason then
		toast(player, reason, "warn")
	end
end

local function addMember(sas, player)
	table.insert(sas.members, player)
	sasOf[player] = sas
	player:SetAttribute("HubSas", sas.model.Name)
	if not sas.host then
		sas.host = player
	end
	refresh(sas)
end

local function teleportGroup(sas, players)
	if RunService:IsStudio() then
		-- Pas de téléportation dans Studio : ce serveur devient la partie.
		for _, p in ipairs(players) do
			p:SetAttribute("HubSas", nil)
		end
		enterMatch(#players)
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({
		partySize = #players,
		sas = sas.model.Name,
	})
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if not ok then
		warn("[HubServer] Échec du transfert du " .. sas.model.Name .. " : " .. tostring(err))
		for _, p in ipairs(table.clone(sas.members)) do
			eject(sas, p, "Transfert interrompu. Nouvelle tentative possible dans quelques instants.")
		end
		reset(sas)
		return
	end
	-- Si le transfert traîne, on libère le sas
	local token = sas.launchToken
	task.delay(CONFIG.TELEPORT_TIMEOUT, function()
		if sas.launchToken == token and sas.state == "Launching" then
			for _, p in ipairs(table.clone(sas.members)) do
				eject(sas, p, "Délai de transfert dépassé. Sas réinitialisé.")
			end
			reset(sas)
		end
	end)
end

local function launch(sas)
	if sas.state == "Launching" or #sas.members == 0 then
		return
	end
	sas.state = "Launching"
	sas.deadline = os.clock() + CONFIG.LAUNCH_TIME
	local token = {}
	sas.launchToken = token
	refresh(sas)
	if sas.mist then
		sas.mist.Enabled = true
	end
	playAt(sas.lamp, CONFIG.DEPART_SOUND_ID, 0.8)
	task.delay(CONFIG.LAUNCH_TIME, function()
		if sas.launchToken ~= token then
			return
		end
		local players = {}
		for _, p in ipairs(sas.members) do
			if p.Parent then
				table.insert(players, p)
			end
		end
		if #players == 0 then
			reset(sas)
			return
		end
		teleportGroup(sas, players)
	end)
end

local function chooseSize(sas, n)
	sas.size = n
	-- Trop de monde pour le mode choisi : les derniers arrivés ressortent
	while #sas.members > n do
		local p = sas.members[#sas.members]
		eject(sas, p, string.format("Effectif du groupe fixé à %d. Vous êtes réaffecté au hall.", n))
	end
	if n == 1 then
		launch(sas)
		return
	end
	-- Premier choix : on lance l'attente des coéquipiers. Changement de mode ensuite : le compte à rebours continue.
	if sas.state ~= "Waiting" then
		sas.state = "Waiting"
		sas.deadline = os.clock() + CONFIG.WAIT_TIME
	end
	refresh(sas)
end

-- Inventaire des sas du hall
for _, model in ipairs(CollectionService:GetTagged("HubSas")) do
	if not model:IsDescendantOf(hub) then
		continue
	end
	local screen = model:FindFirstChild("Screen")
	local display = screen and screen:FindFirstChildOfClass("SurfaceGui")
	local sas = {
		model = model,
		region = model:WaitForChild("Region"),
		door = model:WaitForChild("Door"),
		exit = model:WaitForChild("Exit"),
		lamp = model:WaitForChild("Lamp"),
		mist = model:FindFirstChild("Mist") and model.Mist:FindFirstChildOfClass("ParticleEmitter"),
		statusLabel = display and display:FindFirstChild("Status", true),
		infoLabel = display and display:FindFirstChild("Info", true),
		members = {},
		state = "Free",
	}
	sas.doorClosed = sas.door.CFrame
	sas.doorOpen = false
	table.insert(sasList, sas)
	reset(sas)
end
table.sort(sasList, function(a, b)
	return a.model.Name < b.model.Name
end)

---------------------------------------------------------------------------
-- Boucle : qui est dans quel sas
---------------------------------------------------------------------------
local function insideRegion(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function aliveRoot(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return root
	end
end

local function step()
	for _, sas in ipairs(sasList) do
		-- Départs (sorti à pied, mort, déconnecté) — sauf pendant le départ : la porte est fermée
		if sas.state ~= "Launching" then
			for _, p in ipairs(table.clone(sas.members)) do
				local root = p.Parent and aliveRoot(p)
				if not root or not insideRegion(sas.region, root.Position) then
					removeMember(sas, p)
				end
			end
		end

		-- Arrivées
		for _, p in ipairs(Players:GetPlayers()) do
			local root = aliveRoot(p)
			if root and not sasOf[p] and insideRegion(sas.region, root.Position) then
				if sas.state == "Free" then
					sas.state = "Setup"
					sas.deadline = os.clock() + CONFIG.SETUP_TIMEOUT
					addMember(sas, p)
				elseif sas.state == "Setup" or (sas.state == "Waiting" and #sas.members < sas.size) then
					addMember(sas, p)
				else
					eject(sas, p, "Sas complet ou en cours de transfert. Affectation refusée.")
				end
			end
		end

		-- Minuteries
		if sas.state == "Setup" and os.clock() >= sas.deadline then
			for _, p in ipairs(table.clone(sas.members)) do
				eject(sas, p, "Effectif non déclaré dans le délai. Sas réinitialisé.")
			end
		elseif sas.state == "Waiting" then
			if #sas.members >= sas.size and sas.deadline - os.clock() > CONFIG.FULL_TIME then
				sas.deadline = os.clock() + CONFIG.FULL_TIME
			end
			if os.clock() >= sas.deadline then
				launch(sas)
			end
		end
		refresh(sas)
	end
end

task.spawn(function()
	while true do
		step()
		task.wait(CONFIG.TICK)
	end
end)

---------------------------------------------------------------------------
-- Commandes des joueurs (interface du sas)
---------------------------------------------------------------------------
local lastCommand = {}

remote.OnServerEvent:Connect(function(player, action, value)
	local now = os.clock()
	if lastCommand[player] and now - lastCommand[player] < 0.25 then
		return
	end
	lastCommand[player] = now

	local sas = sasOf[player]
	if not sas then
		return
	end
	if action == "Leave" then
		if sas.state ~= "Launching" then
			eject(sas, player, nil)
		end
	elseif action == "SetSize" then
		local n = tonumber(value)
		if sas.host ~= player or not n or n ~= math.floor(n) or n < 1 or n > CONFIG.MAX_SIZE then
			return
		end
		if sas.state == "Setup" or sas.state == "Waiting" then
			chooseSize(sas, n)
		end
	elseif action == "Launch" then
		if sas.host == player and sas.state == "Waiting" then
			launch(sas)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastCommand[player] = nil
	local sas = sasOf[player]
	if sas then
		removeMember(sas, player)
	end
end)

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	local sas = sasOf[player]
	warn("[HubServer] TeleportInitFailed", player.Name, result, message)
	if sas then
		eject(sas, player, "Transfert interrompu. Nouvelle tentative possible dans quelques instants.")
	end
end)
