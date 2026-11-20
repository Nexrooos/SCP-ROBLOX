--[[
	DClassHUD (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.
	Nécessite le ModuleScript ReplicatedStorage.SCPTerminal (style des cases de texte).

	Interface du bloc cellulaire D :
	  - case d'identité en haut à gauche : matricule + cellule, 8 s à l'arrivée ;
	  - case d'état en haut au centre : attente des sujets, regroupement dans le sas, brèche ;
	  - annonces du haut-parleur en bas (RemoteEvent ReplicatedStorage.LobbyPA) :
	    case info « HAUT-PARLEUR · BLOC D », case alerte pendant la brèche ;
	  - pendant la cinématique de brèche (attribut local InCutscene, voir BreachCutsceneClient),
	    seules les annonces du haut-parleur restent affichées ;
	  - pendant l'alarme : vignette rouge pulsée et rotation des gyrophares.
]]

-- Ne tourne que sur un serveur de partie, pas dans le hall de transit (voir HubServer).
while workspace:GetAttribute("ServerMode") ~= "Match" do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Terminal = require(ReplicatedStorage:WaitForChild("SCPTerminal"))
local player = Players.LocalPlayer

local gui = Terminal.screenGui("DClassHUD", 4) -- respecte la barre du haut et les boutons Roblox
local overlay = Terminal.screenGui("DClassOverlay", 3, true) -- vignette plein écran

-- Vignette rouge (alarme)
local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
vignette.BackgroundTransparency = 1
vignette.BorderSizePixel = 0
vignette.Parent = overlay
local grad = Instance.new("UIGradient")
grad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 1),
	NumberSequenceKeypoint.new(0.75, 1),
	NumberSequenceKeypoint.new(1, 0),
})
grad.Parent = vignette

---------------------------------------------------------------------------
-- Identité (haut gauche)
---------------------------------------------------------------------------
local idBox = Terminal.new({
	kind = "info",
	header = "SITE-19 · BLOC D",
	parent = gui,
	position = UDim2.fromOffset(12, 12),
	widthScale = 0.25,
	minWidth = 200,
	width = 280,
	zIndex = 2,
})

-- Affichée quelques secondes à l'arrivée seulement (le matricule reste imprimé sur la combinaison)
local IDENTITY_HOLD = 8
local identityShown = false
local function refreshIdentity()
	local m = player:GetAttribute("Matricule")
	if not m or player:GetAttribute("InCutscene") then
		idBox:hide()
		return
	end
	if identityShown then
		return
	end
	identityShown = true
	idBox:show(string.format(
		"<font face='Michroma' size='18' color='#FF9A3C'>%s</font>\nCellule %s",
		m,
		player:GetAttribute("CellName") or "?"
	), { hold = IDENTITY_HOLD })
end
player:GetAttributeChangedSignal("Matricule"):Connect(refreshIdentity)
player:GetAttributeChangedSignal("CellName"):Connect(refreshIdentity)
refreshIdentity()

---------------------------------------------------------------------------
-- État du bloc (haut centre)
---------------------------------------------------------------------------
local statusInfo = Terminal.new({
	kind = "info",
	header = "BLOC D",
	parent = gui,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 12),
	widthScale = 0.4,
	minWidth = 220,
	width = 380,
	align = Enum.TextXAlignment.Center,
	zIndex = 2,
})
local statusAlert = Terminal.new({
	kind = "alerte",
	header = "ALERTE",
	parent = gui,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 12),
	widthScale = 0.4,
	minWidth = 220,
	width = 380,
	align = Enum.TextXAlignment.Center,
	zIndex = 2,
})

local function setStatus(box, text)
	local other = box == statusInfo and statusAlert or statusInfo
	other:hide()
	if box.visible then
		box:setText(text) -- compte à rebours : pas de nouvelle machine à écrire
	else
		box:show(text)
	end
end

-- Pendant une annonce du haut-parleur, la case d'état se retire (un seul message à la fois)
local paUntil = 0

local function refreshStatus()
	if os.clock() < paUntil or player:GetAttribute("InCutscene") then
		statusInfo:hide()
		statusAlert:hide()
		return
	end
	local state = workspace:GetAttribute("LobbyState")
	local countdown = workspace:GetAttribute("LobbyCountdown")
	local regroup = workspace:GetAttribute("LobbyRegroup")
	if countdown then
		setStatus(statusInfo, string.format(
			"Attente des joueurs · %d/%d · %d s",
			workspace:GetAttribute("LobbyPlayers") or 1,
			workspace:GetAttribute("LobbyExpected") or 4,
			countdown
		))
	elseif regroup then
		setStatus(statusAlert, "Rejoignez le sas · " .. regroup)
	elseif state == "Breach" then
		setStatus(statusAlert, "Brèche en cours. Attendez l'ouverture des portes.")
	else
		statusInfo:hide()
		statusAlert:hide()
	end
end
for _, a in ipairs({ "LobbyState", "LobbyCountdown", "LobbyRegroup", "LobbyPlayers" }) do
	workspace:GetAttributeChangedSignal(a):Connect(refreshStatus)
end
refreshStatus()
player:GetAttributeChangedSignal("InCutscene"):Connect(function()
	refreshIdentity()
	refreshStatus()
end)

---------------------------------------------------------------------------
-- Haut-parleur (bas centre)
---------------------------------------------------------------------------
local paBox = Terminal.new({
	kind = "info",
	header = "HAUT-PARLEUR",
	parent = gui,
	anchorPoint = Vector2.new(0.5, 1),
	position = UDim2.new(0.5, 0, 1, -12),
	widthScale = 0.6,
	minWidth = 280,
	width = 560,
	textSize = 16,
	zIndex = 2,
})
local alertBox = Terminal.new({
	kind = "alerte",
	header = "ALERTE",
	parent = gui,
	anchorPoint = Vector2.new(0.5, 1),
	position = UDim2.new(0.5, 0, 1, -12),
	widthScale = 0.6,
	minWidth = 280,
	width = 560,
	textSize = 16,
	zIndex = 2,
})

ReplicatedStorage:WaitForChild("LobbyPA").OnClientEvent:Connect(function(text, kind, hold)
	local box = kind == "alert" and alertBox or paBox
	local other = box == paBox and alertBox or paBox
	other:hide()
	local duration = math.max(1, (hold or 4) - 0.6)
	paUntil = os.clock() + duration + 0.5
	refreshStatus()
	box:show(text, { hold = duration })
	task.delay(duration + 0.6, refreshStatus)
end)

---------------------------------------------------------------------------
-- Gyrophares qui tournent + vignette pulsée pendant l'alarme
---------------------------------------------------------------------------
local domes = {}
local function addDome(d)
	domes[d] = d.CFrame
end
for _, d in ipairs(CollectionService:GetTagged("AlarmLight")) do
	addDome(d)
end
CollectionService:GetInstanceAddedSignal("AlarmLight"):Connect(addDome)

local angle = 0
RunService.RenderStepped:Connect(function(dt)
	local state = workspace:GetAttribute("LobbyState")
	local alarm = state == "Breach" or state == "Open" or state == "Started"
	if alarm then
		angle += dt * math.rad(240)
		for dome, base in pairs(domes) do
			if dome.Parent then
				dome.CFrame = CFrame.new(base.Position) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(-25), 0, 0)
			end
		end
		local pulse = (math.sin(os.clock() * 4) + 1) / 2
		vignette.BackgroundTransparency = 0.72 + 0.2 * pulse
	else
		vignette.BackgroundTransparency = 1
	end
end)
