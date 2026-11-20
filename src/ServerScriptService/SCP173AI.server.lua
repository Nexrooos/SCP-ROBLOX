--[[
	SCP173AI (Script) — à placer dans ServerScriptService.

	Règle de SCP-173 : il ne bouge QUE si aucun joueur vivant ne le regarde.
	Dès que personne ne le voit (ou que tout le monde cligne des yeux),
	il fonce vers le joueur le plus proche et le tue au contact.

	- Chaque client dit au serveur s'il voit 173 (script BlinkAndWatch côté client).
	- Le déplacement suit le PathfindingService (contourne les murs).
	- Pour faire apparaître 173 à un endroit précis : place une Part nommée
	  "SCP173Spawn" dans le Workspace (sinon il apparaît en 0, 0, -40).
]]

-- Ne tourne que sur un serveur de partie, pas dans le hall de transit (voir HubServer).
while workspace:GetAttribute("ServerMode") ~= "Match" do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local SCP173Model = require(ServerStorage:WaitForChild("SCP173Model"))

local CONFIG = {
	TICK = 0.1, -- intervalle de mise à jour (s)
	STEP = 3.5, -- distance parcourue par tick quand personne ne regarde (studs) => 35 studs/s
	KILL_DISTANCE = 4, -- distance de "nuque brisée"
	AGGRO_RANGE = 150, -- ne chasse que les joueurs à cette distance
	REPATH_EVERY = 0.4, -- recalcul du chemin (s)
	SCRAPE_SOUND_ID = nil, -- ex. "rbxassetid://123456" : bruit de pierre qui racle
	SNAP_SOUND_ID = nil, -- ex. "rbxassetid://123456" : craquement de nuque
}

-- RemoteEvent partagé avec le client
local remote = ReplicatedStorage:FindFirstChild("SCP173_Watching")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SCP173_Watching"
	remote.Parent = ReplicatedStorage
end

-- watching[player][model] = true si ce joueur voit ce 173 en ce moment
local watching = {}

remote.OnServerEvent:Connect(function(player, model, isWatching)
	if typeof(model) ~= "Instance" or not CollectionService:HasTag(model, "SCP173") then
		return
	end
	watching[player] = watching[player] or {}
	watching[player][model] = (isWatching == true) or nil
end)

Players.PlayerRemoving:Connect(function(player)
	watching[player] = nil
end)

local function getAliveRoot(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return hrp, hum
	end
	return nil
end

local function isObserved(model)
	for _, player in ipairs(Players:GetPlayers()) do
		if getAliveRoot(player) and watching[player] and watching[player][model] then
			return true
		end
	end
	return false
end

local function nearestTarget(position)
	local best, bestDist, bestHum
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp, hum = getAliveRoot(player)
		if hrp then
			local d = (hrp.Position - position).Magnitude
			if d <= CONFIG.AGGRO_RANGE and (not bestDist or d < bestDist) then
				best, bestDist, bestHum = hrp, d, hum
			end
		end
	end
	return best, bestDist, bestHum
end

local function playSound(model, id, volume)
	if not id then
		return
	end
	local anchor = model.PrimaryPart and model.PrimaryPart:FindFirstChild("SoundAnchor")
	if not anchor then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.RollOffMaxDistance = 80
	s.Parent = anchor
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Fait tourner un 173 en boucle
local function runAI(model)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 10,
		AgentCanJump = false,
	})
	local waypoints = {}
	local wpIndex = 1
	local lastRepath = 0
	local computing = false
	local wasMoving = false

	local function repath(fromPos, toPos)
		if computing then
			return
		end
		computing = true
		task.spawn(function()
			local ok = pcall(function()
				path:ComputeAsync(fromPos, toPos)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				waypoints = path:GetWaypoints()
				wpIndex = 2 -- le 1er waypoint = position actuelle
			else
				-- Pas de chemin : ligne droite
				waypoints = { { Position = fromPos }, { Position = toPos } }
				wpIndex = 2
			end
			computing = false
		end)
	end

	while model.Parent do
		task.wait(CONFIG.TICK)

		local pivot = model:GetPivot()
		local pos = pivot.Position
		local target, dist, hum = nearestTarget(pos)

		if not target or isObserved(model) then
			wasMoving = false
			continue
		end

		-- Contact => mort
		if dist <= CONFIG.KILL_DISTANCE then
			playSound(model, CONFIG.SNAP_SOUND_ID, 2)
			hum.Health = 0
			continue
		end

		if not wasMoving then
			playSound(model, CONFIG.SCRAPE_SOUND_ID, 1.5)
			wasMoving = true
		end

		local now = os.clock()
		if now - lastRepath > CONFIG.REPATH_EVERY then
			lastRepath = now
			local groundTarget = target.Position - Vector3.new(0, 3, 0)
			repath(pos, groundTarget)
		end

		-- Avance le long des waypoints
		local remaining = CONFIG.STEP
		while remaining > 0 and waypoints[wpIndex] do
			local wp = waypoints[wpIndex].Position
			local delta = wp - pos
			local d = delta.Magnitude
			if d <= remaining then
				pos = wp
				remaining -= d
				wpIndex += 1
			else
				pos += delta.Unit * remaining
				remaining = 0
			end
		end

		-- Toujours face au joueur (orientation horizontale)
		local lookDir = flat(target.Position - pos)
		if lookDir.Magnitude > 0.01 then
			model:PivotTo(CFrame.lookAt(pos, pos + lookDir))
		else
			model:PivotTo(CFrame.new(pos) * pivot.Rotation)
		end
	end
end

CollectionService:GetInstanceAddedSignal("SCP173"):Connect(function(model)
	task.spawn(runAI, model)
end)
for _, model in ipairs(CollectionService:GetTagged("SCP173")) do
	task.spawn(runAI, model)
end

-- Apparition de test
local spawnPart = workspace:FindFirstChild("SCP173Spawn")
local spawnCF = spawnPart and (spawnPart.CFrame * CFrame.new(0, -spawnPart.Size.Y / 2, 0)) or CFrame.new(0, 0, -40)
if spawnPart then
	spawnPart.Transparency = 1
	spawnPart.CanCollide = false
end
local scp = SCP173Model.build(spawnCF)
scp.Parent = workspace

if RunService:IsStudio() then
	print("[SCP-173] Apparu en", spawnCF.Position, "— regarde-le pour qu'il ne bouge pas !")
end
