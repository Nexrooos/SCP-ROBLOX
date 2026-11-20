--[[
	HubLife (Script) — à placer dans ServerScriptService.
	Nécessite ServerStorage.FoundationGuard (+ FaceKit), ReplicatedStorage.FouDialog (créé par CrazyDClass),
	et dans Workspace.Hub :
	  - Patrols.GuardPost_Cell : poste du garde devant la cellule (face avant = direction du regard) ;
	  - Patrols.PatrolA, Patrols.PatrolB : points de ronde (P01, P02… parcourus dans l'ordre, en boucle) ;
	  - Decor.Ventilation (parts avec l'attribut VentHum) et Props.Speaker (haut-parleurs).

	Vie du hall de transit, sur le serveur public uniquement :
	  - trois gardes, chacun avec son visage, son allure et son caractère (GUARDS) :
	      Delmas, posté devant la cellule de D-0451, vieux briscard blasé, béret et tasse de café ;
	      Ferrand, en ronde, sévère et procédurier ;
	      Okoye, en ronde, jeune recrue nerveuse qui en dit trop ;
	  - les rondes suivent un chemin calculé (PathfindingService) : les gardes contournent bancs,
	    jardinières et piliers au lieu de foncer dedans ;
	  - on peut leur parler (touche E) : le garde s'arrête, se tourne vers le joueur et répond
	    (même fenêtre que D-0451, aucune anomalie citée) ;
	  - bourdonnement de ventilation, annonces aux haut-parleurs, voyants qui clignotent.
	Les repères (attribut EditorOnly) sont visibles dans Studio pour être déplacés, invisibles en jeu.

	Sons : ID de la bibliothèque Roblox (ProSoundEffects pour la ventilation et les voix), à changer dans CONFIG.
]]

while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")

local FoundationGuard = require(ServerStorage:WaitForChild("FoundationGuard"))

local CONFIG = {
	PATROL_SPEED = 6, -- marche lente (studs/s)
	PAUSE_MIN = 2,
	PAUSE_MAX = 5,
	TALK_DISTANCE = 8,
	TALK_TIMEOUT = 40,
	VENT_SOUND_ID = "rbxassetid://9125446564", -- Command Room Tone, Deep Air Conditioning Hum (ProSoundEffects)
	VENT_VOLUME = 0.35,
	PA_CHIME_ID = "rbxassetid://88920716117135", -- carillon deux tons
	PA_VOICE_IDS = { -- voix radio, filtrées pour sonner comme un haut-parleur lointain (ProSoundEffects)
		"rbxassetid://9117780718",
		"rbxassetid://9117778763",
	},
	PA_VOLUME = 0.55,
	PA_EVERY_MIN = 70, -- intervalle entre deux annonces (s)
	PA_EVERY_MAX = 160,
}

-- Les trois gardes du hall. Répliques : jargon de la Fondation, aucune anomalie nommée.
local GUARDS = {
	Delmas = {
		speaker = "AGENT DELMAS · SÉCURITÉ",
		nameTag = "DELMAS",
		skinColor = Color3.fromRGB(160, 108, 78),
		scale = 1.03,
		helmet = "none",
		hairColor = Color3.fromRGB(120, 118, 114),
		mug = true,
		face = {
			iris = Color3.fromRGB(60, 44, 30),
			lids = 0.42, -- paupières lourdes : blasé
			brows = { 4, 2 },
			browColor = Color3.fromRGB(110, 108, 104),
			mouth = "flat",
			bags = 0.8,
			stubble = 0.7,
			stubbleColor = Color3.fromRGB(120, 118, 114),
			mustache = true,
			wrinkles = true,
		},
		talks = {
			{
				"Hm. Encore un qui vient voir le phénomène de foire.",
				"Trois ans que je le garde. Il compte les néons. Moi je compte les jours avant la retraite.",
			},
			{
				"Ne lui donnez rien. Pas de nourriture, pas de crayon. Et surtout pas de réponse.",
				"La dernière fois qu'un Classe D lui a répondu, il a hurlé un chiffre toute la nuit. Toujours le même.",
			},
			{
				"Le café, c'est la seule chose ici qui n'a pas de protocole.",
				"...Enfin si. Protocole C-4. Ne demandez pas.",
			},
			{
				"Les sas, c'est par là. Allez-y, on n'attend que vous.",
				"Et si vous revenez, ne lui racontez rien. Il le sait déjà. Il le sait toujours avant.",
			},
		},
	},
	Ferrand = {
		speaker = "AGENT FERRAND · SÉCURITÉ",
		nameTag = "FERRAND",
		skinColor = Color3.fromRGB(200, 146, 108),
		scale = 1.07,
		helmet = "visorUp",
		face = {
			iris = Color3.fromRGB(70, 96, 120),
			lids = 0.2,
			brows = { -16, -16 }, -- sourcils froncés
			browThick = 0.05,
			mouth = "frown",
			bags = 0.2,
			stubble = 0.25,
			scar = true,
		},
		talks = {
			{
				"Classe D. Vous n'êtes pas autorisé à engager la conversation avec le personnel de sécurité.",
				"...Puisque vous êtes là : restez dans la zone de transit. Les sas sont la seule sortie autorisée.",
			},
			{
				"Accréditation niveau zéro. La mienne suffit largement pour vous neutraliser.",
				"Avancez.",
			},
			{
				"Toute tentative d'évasion entraînera une neutralisation immédiate. Ce n'est pas une menace.",
				"C'est la procédure. J'aime la procédure. La procédure garde les gens en vie. Certains gens.",
			},
			{
				"Ne touchez pas aux écrans du poste de contrôle. Ne les regardez pas trop longtemps non plus.",
				"Certaines images ne viennent pas des caméras du hall.",
			},
		},
	},
	Okoye = {
		speaker = "AGENT OKOYE · SÉCURITÉ",
		nameTag = "OKOYE",
		skinColor = Color3.fromRGB(104, 70, 50),
		scale = 0.97,
		helmet = "visorUp",
		face = {
			iris = Color3.fromRGB(50, 34, 24),
			eyeSize = 1.15,
			pupil = 0.5,
			lids = 0.05,
			brows = { 14, 12 }, -- sourcils relevés : inquiet
			mouth = "tense",
			bags = 0.3,
			sweat = true,
		},
		talks = {
			{
				"Oh. Euh. Bonjour. On n'est pas censés vous parler, je crois.",
				"Vous allez passer les sas ? On m'a dit de jamais y aller. Jamais. Bonne chance, hein.",
			},
			{
				"C'est ma deuxième semaine. Le sergent dit qu'on s'habitue.",
				"Il dit ça avec les yeux grands ouverts. Il cligne jamais, le sergent. Jamais.",
			},
			{
				"Vous avez entendu l'annonce, tout à l'heure ? Moi j'ai rien compris.",
				"Personne comprend jamais. Mais tout le monde arrête de parler pendant.",
			},
			{
				"Si je vous dis un truc, vous le répétez pas ?",
				"Les Classe D qui partent par les sas... je les vois jamais revenir. Pas par ce couloir-là, en tout cas.",
			},
		},
	},
}

local hub = workspace:WaitForChild("Hub")
local patrols = hub:WaitForChild("Patrols")
local dialog = ReplicatedStorage:WaitForChild("FouDialog")

-- Repères invisibles en jeu
for _, d in ipairs(hub:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("EditorOnly") then
		d.Transparency = 1
	end
end

---------------------------------------------------------------------------
-- Gardes
---------------------------------------------------------------------------
local guardsFolder = Instance.new("Folder")
guardsFolder.Name = "HubGuards"
guardsFolder.Parent = workspace
-- Dans Studio, le serveur passe du hall à la partie sans redémarrer : les gardes partent avec le hall
workspace:GetAttributeChangedSignal("ServerMode"):Connect(function()
	if workspace:GetAttribute("ServerMode") ~= "Hub" then
		guardsFolder:Destroy()
	end
end)

local function standOn(marker)
	local p = marker.Position
	return CFrame.lookAt(Vector3.new(p.X, p.Y + 3, p.Z), Vector3.new(p.X, p.Y + 3, p.Z) + marker.CFrame.LookVector)
end

local function turnTo(guard, dir)
	local pos = guard.root.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	guard.humanoid.AutoRotate = false
	guard.root.CFrame = CFrame.lookAt(pos, pos + dir.Unit)
end

local function spawnGuard(key, cframe, extra)
	local p = GUARDS[key]
	local opts = {
		name = "Agent_" .. key,
		cframe = cframe,
		parent = guardsFolder,
		skinColor = p.skinColor,
		scale = p.scale,
		helmet = p.helmet,
		hairColor = p.hairColor,
		mug = p.mug,
		face = p.face,
		nameTag = p.nameTag,
	}
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	local guard = FoundationGuard.new(opts)
	guard.persona = p
	guard.talkIndex = {} -- player -> index de la prochaine réplique
	return guard
end

---------------------------------------------------------------------------
-- Conversation avec un garde
---------------------------------------------------------------------------
local talkingGuard = {} -- player -> garde en conversation

local function endGuardTalk(player)
	local guard = talkingGuard[player]
	if not guard then
		return
	end
	talkingGuard[player] = nil
	guard.talkingWith = nil
	guard.model:SetAttribute("Talking", false)
end

local function makeTalkable(guard)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Parler"
	prompt.ObjectText = guard.persona.speaker:match("^[^·]+"):gsub("%s+$", "")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = CONFIG.TALK_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = guard.root
	prompt.Triggered:Connect(function(player)
		if guard.talkingWith or talkingGuard[player] then
			return
		end
		guard.talkingWith = player
		talkingGuard[player] = guard
		-- il s'arrête et se tourne vers le joueur
		guard.humanoid:MoveTo(guard.root.Position)
		local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if r then
			turnTo(guard, r.Position - guard.root.Position)
		end
		local talks = guard.persona.talks
		local i = guard.talkIndex[player] or math.random(1, #talks)
		guard.talkIndex[player] = i % #talks + 1
		guard.model:SetAttribute("Talking", true)
		dialog:FireClient(player, "Open", guard.persona.speaker, table.clone(talks[i]), guard.root)
		task.delay(CONFIG.TALK_TIMEOUT, function()
			if talkingGuard[player] == guard then
				endGuardTalk(player)
			end
		end)
	end)
end

dialog.OnServerEvent:Connect(function(player, msg)
	if msg == "Close" then
		endGuardTalk(player)
	end
end)
Players.PlayerRemoving:Connect(endGuardTalk)

-- Attend la fin d'une conversation (le garde reste immobile, tourné vers le joueur)
local function waitWhileTalking(guard)
	while guard.talkingWith and guard.model.Parent do
		task.wait(0.25)
	end
end

---------------------------------------------------------------------------
-- Garde posté devant la cellule : Delmas
---------------------------------------------------------------------------
local post = patrols:FindFirstChild("GuardPost_Cell")
if post then
	local guard = spawnGuard("Delmas", standOn(post))
	makeTalkable(guard)
	local cell = hub:FindFirstChild("Decor") and hub.Decor:FindFirstChild("CelluleIsolement")
	local forward = post.CFrame.LookVector
	task.spawn(function()
		while guard.model.Parent do
			task.wait(4 + math.random() * 6)
			waitWhileTalking(guard)
			local r = math.random()
			if r < 0.4 and cell then
				-- coup d'œil au détenu
				local fou = cell:FindFirstChild("D-0451")
				local spot = cell:FindFirstChild("FouSpot")
				local c = fou and fou:GetPivot().Position or (spot and spot.Position) or guard.root.Position
				turnTo(guard, c - guard.root.Position)
				task.wait(2 + math.random() * 2)
			elseif r < 0.7 then
				local a = math.rad(math.random(-50, 50))
				turnTo(guard, CFrame.Angles(0, a, 0):VectorToWorldSpace(forward))
				task.wait(1.5 + math.random() * 2)
			end
			waitWhileTalking(guard)
			turnTo(guard, forward)
		end
	end)
end

---------------------------------------------------------------------------
-- Rondes : Ferrand et Okoye, chemin calculé autour des obstacles
---------------------------------------------------------------------------
local function moveStep(guard, target)
	-- avance jusqu'à un point du chemin ; reprend après une conversation
	local t0 = os.clock()
	while guard.model.Parent and os.clock() - t0 < 10 do
		waitWhileTalking(guard)
		guard.humanoid.AutoRotate = true
		guard.humanoid:MoveTo(target)
		local done, reached = false, false
		local conn = guard.humanoid.MoveToFinished:Connect(function(ok)
			done, reached = true, ok
		end)
		local s = os.clock()
		while not done and os.clock() - s < 6 do
			task.wait(0.1)
			if guard.talkingWith then
				break
			end
		end
		conn:Disconnect()
		if guard.talkingWith then
			continue -- interrompu : on attend la fin de la conversation et on reprend ce point
		end
		local flat = Vector3.new(target.X - guard.root.Position.X, 0, target.Z - guard.root.Position.Z)
		if reached or flat.Magnitude < 2 then
			return true
		end
	end
	return false
end

local function walkTo(guard, target)
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5.5,
		AgentCanJump = false,
		WaypointSpacing = 5,
	})
	local ok = pcall(function()
		path:ComputeAsync(guard.root.Position, target)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		local wps = path:GetWaypoints()
		for i = 2, #wps do
			if not moveStep(guard, wps[i].Position) then
				return
			end
		end
	else
		moveStep(guard, target) -- pas de chemin : ligne droite
	end
end

local function runPatrol(folder, key)
	local points = folder:GetChildren()
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	if #points < 2 then
		return
	end
	local guard = spawnGuard(key, standOn(points[1]), { walkSpeed = CONFIG.PATROL_SPEED })
	makeTalkable(guard)
	task.spawn(function()
		local i = 1
		while guard.model.Parent do
			i = i % #points + 1
			walkTo(guard, points[i].Position)
			-- pause : il regarde autour de lui
			waitWhileTalking(guard)
			local forward = guard.root.CFrame.LookVector
			task.wait(CONFIG.PAUSE_MIN * 0.5)
			turnTo(guard, CFrame.Angles(0, math.rad(math.random(40, 80)), 0):VectorToWorldSpace(forward))
			task.wait(1 + math.random())
			waitWhileTalking(guard)
			turnTo(guard, CFrame.Angles(0, math.rad(-math.random(40, 80)), 0):VectorToWorldSpace(forward))
			task.wait(CONFIG.PAUSE_MIN * 0.5 + math.random() * (CONFIG.PAUSE_MAX - CONFIG.PAUSE_MIN))
		end
	end)
end

local patrolKeys = { PatrolA = "Ferrand", PatrolB = "Okoye" }
for _, name in ipairs({ "PatrolA", "PatrolB" }) do
	local f = patrols:FindFirstChild(name)
	if f then
		runPatrol(f, patrolKeys[name])
	end
end

---------------------------------------------------------------------------
-- Ventilation
---------------------------------------------------------------------------
for _, d in ipairs(hub:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("VentHum") then
		local s = Instance.new("Sound")
		s.Name = "VentHum"
		s.SoundId = CONFIG.VENT_SOUND_ID
		s.Looped = true
		s.Volume = CONFIG.VENT_VOLUME
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 70
		s.PlaybackSpeed = 0.9 + math.random() * 0.2 -- chaque bouche un peu différente
		s.TimePosition = math.random() * 20
		s.Parent = d
		s:Play()
	end
end

---------------------------------------------------------------------------
-- Annonces aux haut-parleurs
---------------------------------------------------------------------------
local speakers = {}
for _, d in ipairs(hub:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Speaker" then
		table.insert(speakers, d)
	end
end

local function speakerSound(parent, id, volume, filtered)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 160
	if filtered then
		-- son de haut-parleur : pas de graves, aigus écrasés, un peu de saturation et d'écho
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = -30
		eq.MidGain = 4
		eq.HighGain = -12
		eq.Parent = s
		local dist = Instance.new("DistortionSoundEffect")
		dist.Level = 0.25
		dist.Parent = s
		local rev = Instance.new("ReverbSoundEffect")
		rev.DecayTime = 1.6
		rev.WetLevel = -6
		rev.Parent = s
	end
	s.Parent = parent
	s.Ended:Once(function()
		s:Destroy()
	end)
	return s
end

if #speakers > 0 then
	task.spawn(function()
		task.wait(20 + math.random() * 30)
		while true do
			local voice = CONFIG.PA_VOICE_IDS[math.random(1, #CONFIG.PA_VOICE_IDS)]
			for _, sp in ipairs(speakers) do
				speakerSound(sp, CONFIG.PA_CHIME_ID, CONFIG.PA_VOLUME, false):Play()
			end
			task.wait(2.2)
			for _, sp in ipairs(speakers) do
				speakerSound(sp, voice, CONFIG.PA_VOLUME, true):Play()
			end
			task.wait(CONFIG.PA_EVERY_MIN + math.random() * (CONFIG.PA_EVERY_MAX - CONFIG.PA_EVERY_MIN))
		end
	end)
end

---------------------------------------------------------------------------
-- Voyants qui clignotent
---------------------------------------------------------------------------
local leds = {}
for _, d in ipairs(hub:GetDescendants()) do
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
