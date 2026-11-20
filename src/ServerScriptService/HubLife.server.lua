--[[
	HubLife (Script) — à placer dans ServerScriptService.
	Nécessite ServerStorage.FoundationGuard, et dans Workspace.Hub :
	  - Patrols.GuardPost_Cell : poste du garde devant la cellule (face avant = direction du regard) ;
	  - Patrols.PatrolA, Patrols.PatrolB : points de ronde (P01, P02… parcourus dans l'ordre, en boucle) ;
	  - Decor.Ventilation (parts avec l'attribut VentHum) et Props.Speaker (haut-parleurs).

	Vie du hall de transit, sur le serveur public uniquement :
	  - un garde posté devant la cellule de D-0451, qui jette des coups d'œil au détenu et au hall ;
	  - deux gardes qui font des rondes lentes, avec une pause et un regard circulaire à chaque point ;
	  - bourdonnement de ventilation en continu (sons 3D sur les bouches) ;
	  - annonces occasionnelles aux haut-parleurs (carillon puis voix radio filtrée) ;
	  - voyants qui clignotent (parts avec l'attribut Blink).
	Les repères (attribut EditorOnly) sont visibles dans Studio pour être déplacés, invisibles en jeu.

	Sons : ID de la bibliothèque Roblox (ProSoundEffects pour la ventilation et les voix), à changer dans CONFIG.
]]

while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local ServerStorage = game:GetService("ServerStorage")

local FoundationGuard = require(ServerStorage:WaitForChild("FoundationGuard"))

local CONFIG = {
	PATROL_SPEED = 6, -- marche lente (studs/s)
	PAUSE_MIN = 2,
	PAUSE_MAX = 5,
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

local hub = workspace:WaitForChild("Hub")
local patrols = hub:WaitForChild("Patrols")

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

-- Garde posté devant la cellule
local post = patrols:FindFirstChild("GuardPost_Cell")
if post then
	local guard = FoundationGuard.new({ name = "Garde_Cellule", cframe = standOn(post), parent = guardsFolder, skin = 2 })
	local cell = hub:FindFirstChild("Decor") and hub.Decor:FindFirstChild("CelluleIsolement")
	local forward = post.CFrame.LookVector
	task.spawn(function()
		while guard.model.Parent do
			task.wait(4 + math.random() * 6)
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
			turnTo(guard, forward)
		end
	end)
end

-- Rondes
local function runPatrol(folder, index)
	local points = folder:GetChildren()
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)
	if #points < 2 then
		return
	end
	local guard = FoundationGuard.new({
		name = "Garde_Ronde_" .. index,
		cframe = standOn(points[1]),
		parent = guardsFolder,
		skin = index == 1 and 1 or 3,
		walkSpeed = CONFIG.PATROL_SPEED,
	})
	task.spawn(function()
		local i = 1
		while guard.model.Parent do
			i = i % #points + 1
			local target = points[i].Position
			guard.humanoid.AutoRotate = true
			guard.humanoid:MoveTo(target)
			local done = false
			local conn = guard.humanoid.MoveToFinished:Connect(function()
				done = true
			end)
			local t0, issued = os.clock(), os.clock()
			while not done and os.clock() - t0 < 25 do
				task.wait(0.2)
				if os.clock() - issued > 7 then
					guard.humanoid:MoveTo(target) -- MoveTo expire au bout de 8 s
					issued = os.clock()
				end
			end
			conn:Disconnect()
			-- pause : il regarde autour de lui
			local forward = guard.root.CFrame.LookVector
			task.wait(CONFIG.PAUSE_MIN * 0.5)
			turnTo(guard, CFrame.Angles(0, math.rad(math.random(40, 80)), 0):VectorToWorldSpace(forward))
			task.wait(1 + math.random())
			turnTo(guard, CFrame.Angles(0, math.rad(-math.random(40, 80)), 0):VectorToWorldSpace(forward))
			task.wait(CONFIG.PAUSE_MIN * 0.5 + math.random() * (CONFIG.PAUSE_MAX - CONFIG.PAUSE_MIN))
		end
	end)
end

for i, name in ipairs({ "PatrolA", "PatrolB" }) do
	local f = patrols:FindFirstChild(name)
	if f then
		runPatrol(f, i)
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
