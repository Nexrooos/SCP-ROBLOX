--[[
	SCPCodex (ModuleScript) — à placer dans ServerScriptService.

	Dossier des anomalies rencontrées par chaque joueur, sauvegardé en DataStore : le hall de transit
	et les parties tournent sur des serveurs différents, le dossier doit suivre le joueur.

	Données par joueur (clé "u_<UserId>" du DataStore SCPCodex_v1) :
		{ v = 1, seen = { ["SCP-173"] = { deaths = 2, first = <os.time()> } }, heard = { ["SCP-173"] = 3 } }
	  - seen  : anomalies vues (deaths = nombre de morts contre elle) ;
	  - heard : nombre de conseils déjà donnés par D-0451 pour chaque anomalie.

	Côté client : attribut SCPSeen du joueur ("SCP-096,SCP-173"), et RemoteEvent ReplicatedStorage.CodexEvent
	("NewEntry", id) à la première rencontre (notification « nouvelle entrée »).

	Sans accès aux DataStores (Studio sans « Enable Studio Access to API Services »), le dossier
	reste en mémoire le temps de la session.

	API :
		Codex.markSeen(player, "SCP-173", { died = true })
		Codex.get(player)                    -- attend le chargement (10 s max), renvoie la table du joueur
		Codex.takeTip(player, id, tipCount)  -- index du prochain conseil (1..tipCount), et si c'est une redite
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORE_NAME = "SCPCodex_v1"
local SAVE_DELAY = 6 -- regroupe les sauvegardes rapprochées (s)

local store
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local event = ReplicatedStorage:FindFirstChild("CodexEvent") or Instance.new("RemoteEvent")
event.Name = "CodexEvent"
event.Parent = ReplicatedStorage

local Codex = {}
local cache = {} -- player -> données
local loading = {} -- player -> true pendant le chargement
local pendingSave = {} -- player -> true si une sauvegarde est programmée

local function blank()
	return { v = 1, seen = {}, heard = {} }
end

local function keyOf(player)
	return "u_" .. player.UserId
end

local function canStore(player)
	return store ~= nil and player.UserId > 0
end

local function publish(player)
	local data = cache[player]
	if not data then
		return
	end
	local ids = {}
	for id in pairs(data.seen) do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("SCPSeen", table.concat(ids, ","))
end

local function load(player)
	loading[player] = true
	local data
	if canStore(player) then
		for attempt = 1, 3 do
			local ok, res = pcall(function()
				return store:GetAsync(keyOf(player))
			end)
			if ok then
				data = type(res) == "table" and res or nil
				break
			end
			local err = tostring(res)
			if string.find(err, "StudioAccessToApisNotAllowed") or string.find(err, "Studio access to APIs") then
				store = nil -- Studio sans accès aux API : dossier en mémoire, inutile de réessayer
				break
			end
			task.wait(attempt)
		end
	end
	data = data or blank()
	data.seen = type(data.seen) == "table" and data.seen or {}
	data.heard = type(data.heard) == "table" and data.heard or {}
	if player.Parent then
		cache[player] = data
		publish(player)
	end
	loading[player] = nil
end

local function save(player)
	local data = cache[player]
	if not (data and canStore(player)) then
		return
	end
	pcall(function()
		store:SetAsync(keyOf(player), data, { player.UserId })
	end)
end

local function scheduleSave(player)
	if pendingSave[player] then
		return
	end
	pendingSave[player] = true
	task.delay(SAVE_DELAY, function()
		pendingSave[player] = nil
		if player.Parent then
			save(player)
		end
	end)
end

function Codex.get(player)
	local t0 = os.clock()
	while not cache[player] and player.Parent and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	return cache[player] or blank()
end

function Codex.markSeen(player, id, opts)
	opts = opts or {}
	local data = Codex.get(player)
	if not cache[player] then
		return
	end
	local entry = data.seen[id]
	local isNew = entry == nil
	if isNew then
		entry = { deaths = 0, first = os.time() }
		data.seen[id] = entry
	elseif not opts.died then
		return -- déjà vu, rien de nouveau
	end
	if opts.died then
		entry.deaths = (entry.deaths or 0) + 1
	end
	if isNew then
		publish(player)
		event:FireClient(player, "NewEntry", id)
	end
	scheduleSave(player)
end

-- Renvoie l'index du conseil à donner (1..tipCount) et true si tous ont déjà été donnés (redite)
function Codex.takeTip(player, id, tipCount)
	local data = Codex.get(player)
	local heard = data.heard[id] or 0
	data.heard[id] = heard + 1
	if cache[player] then
		scheduleSave(player)
	end
	return heard % tipCount + 1, heard >= tipCount
end

Players.PlayerAdded:Connect(load)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(load, p)
end

Players.PlayerRemoving:Connect(function(player)
	while loading[player] do
		task.wait(0.1)
	end
	save(player)
	cache[player] = nil
	pendingSave[player] = nil
end)

game:BindToClose(function()
	for player in pairs(cache) do
		task.spawn(save, player)
	end
	task.wait(2) -- laisse partir les sauvegardes avant l'arrêt du serveur
end)

return Codex
