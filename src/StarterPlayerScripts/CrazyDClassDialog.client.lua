--[[
	CrazyDClassDialog (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.
	Nécessite ReplicatedStorage.SCPTerminal (notifications).

	1. Dialogue avec D-0451 « Le Fou » (voir ServerScriptService.CrazyDClass) :
	   une seule fenêtre en bas de l'écran, une réplique à la fois, écrite lettre par lettre.
	   [E], clic ou bouton A : réplique suivante (ou fin de l'écriture). La fenêtre se ferme
	   à la dernière réplique, ou si le joueur s'éloigne. Pendant le dialogue, l'attribut local
	   InDialog du joueur vaut true (HubHUD masque alors son indication en bas de l'écran).
	2. Dossier des anomalies (ServerScriptService.SCPCodex) : à la première rencontre d'une anomalie,
	   une notification indique qu'elle est entrée au dossier et que D-0451 en sait plus.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Terminal = require(ReplicatedStorage:WaitForChild("SCPTerminal"))

---------------------------------------------------------------------------
-- 2. Notification « nouvelle entrée au dossier »
---------------------------------------------------------------------------
local codexEvent = ReplicatedStorage:WaitForChild("CodexEvent", 30)
if codexEvent then
	codexEvent.OnClientEvent:Connect(function(kind, id)
		if kind == "NewEntry" then
			Terminal.notify("info", string.format("%s ajouté à ton dossier.\nD-0451, dans le hall, en sait plus.", id), {
				header = "DOSSIER",
				hold = 6,
			})
		end
	end)
end

---------------------------------------------------------------------------
-- 1. Dialogue (hall uniquement)
---------------------------------------------------------------------------
while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local remote = ReplicatedStorage:WaitForChild("FouDialog")

local CONFIG = {
	TYPE_SPEED = 45, -- caractères par seconde
	MAX_DISTANCE = 16, -- au-delà, le dialogue se ferme (studs)
	ORANGE = Color3.fromRGB(226, 110, 20),
	BG = Color3.fromRGB(12, 13, 16),
	TEXT = Color3.fromRGB(232, 230, 222),
	DIM = Color3.fromRGB(140, 140, 136),
}

local gui = Terminal.screenGui("FouDialog", 30)
gui.Enabled = false

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -16)
panel.Size = UDim2.new(0.6, 0, 0, 118)
panel.BackgroundColor3 = CONFIG.BG
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(300, 0)
sizeLimit.MaxSize = Vector2.new(640, math.huge)
sizeLimit.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = CONFIG.ORANGE
stroke.Transparency = 0.4
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = panel
local accent = Instance.new("Frame")
accent.Size = UDim2.new(0, 4, 1, 0)
accent.BackgroundColor3 = CONFIG.ORANGE
accent.BorderSizePixel = 0
accent.Parent = panel

local nameTag = Instance.new("TextLabel")
nameTag.Position = UDim2.fromOffset(16, -12)
nameTag.Size = UDim2.fromOffset(0, 24)
nameTag.AutomaticSize = Enum.AutomaticSize.X
nameTag.BackgroundColor3 = CONFIG.ORANGE
nameTag.BorderSizePixel = 0
nameTag.Font = Enum.Font.Michroma
nameTag.TextSize = 13
nameTag.TextColor3 = Color3.fromRGB(14, 14, 14)
nameTag.Parent = panel
local namePad = Instance.new("UIPadding")
namePad.PaddingLeft = UDim.new(0, 10)
namePad.PaddingRight = UDim.new(0, 10)
namePad.Parent = nameTag

local body = Instance.new("TextLabel")
body.Position = UDim2.fromOffset(20, 22)
body.Size = UDim2.new(1, -40, 1, -46)
body.BackgroundTransparency = 1
body.Font = Enum.Font.RobotoMono
body.TextSize = 17
body.TextColor3 = CONFIG.TEXT
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Parent = panel

local hint = Instance.new("TextButton")
hint.AnchorPoint = Vector2.new(1, 1)
hint.Position = UDim2.new(1, -12, 1, -6)
hint.Size = UDim2.fromOffset(160, 18)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Code
hint.TextSize = 12
hint.TextColor3 = CONFIG.DIM
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.Text = "[E] suivant"
hint.Parent = panel

-- Toute la fenêtre est cliquable
local clickArea = Instance.new("TextButton")
clickArea.Size = UDim2.fromScale(1, 1)
clickArea.BackgroundTransparency = 1
clickArea.Text = ""
clickArea.ZIndex = 5
clickArea.Parent = panel

local lines, index = nil, 0
local typing = false
local typeToken = 0
local open = false
local npcRoot = nil

local function findNpcRoot()
	local cell = workspace:FindFirstChild("Hub")
		and workspace.Hub:FindFirstChild("Decor")
		and workspace.Hub.Decor:FindFirstChild("CelluleIsolement")
	local npc = cell and cell:FindFirstChild("D-0451")
	return npc and npc:FindFirstChild("HumanoidRootPart")
end

local function setPrompt(enabled)
	local prompt = npcRoot and npcRoot:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = enabled -- local au client
	end
end

-- Petit tremblement de la fenêtre : il n'est pas très stable
local function shake()
	task.spawn(function()
		for _ = 1, 6 do
			panel.Position = UDim2.new(0.5, math.random(-3, 3), 1, -16 + math.random(-2, 2))
			task.wait(0.03)
		end
		panel.Position = UDim2.new(0.5, 0, 1, -16)
	end)
end

local function showLine(text)
	typeToken += 1
	local token = typeToken
	typing = true
	body.Text = text
	body.MaxVisibleGraphemes = 0
	hint.Text = index < #lines and "[E] suivant" or "[E] fermer"
	-- les répliques en MAJUSCULES le font trembler
	if string.find(text, "%u%u%u%u") then
		shake()
	end
	task.spawn(function()
		local total = utf8.len(text) or #text
		local t0 = os.clock()
		while token == typeToken do
			local n = math.floor((os.clock() - t0) * CONFIG.TYPE_SPEED)
			if n >= total then
				break
			end
			body.MaxVisibleGraphemes = n
			task.wait()
		end
		if token == typeToken then
			body.MaxVisibleGraphemes = -1
			typing = false
		end
	end)
end

local close -- défini plus bas

local function advance()
	if not open then
		return
	end
	if typing then
		typeToken += 1
		body.MaxVisibleGraphemes = -1
		typing = false
		return
	end
	index += 1
	if index > #lines then
		close()
	else
		showLine(lines[index])
	end
end

local function onAction(_, state)
	if state == Enum.UserInputState.Begin then
		advance()
	end
	return Enum.ContextActionResult.Sink
end

function close()
	if not open then
		return
	end
	open = false
	typeToken += 1
	ContextActionService:UnbindAction("FouDialogNext")
	remote:FireServer("Close")
	player:SetAttribute("InDialog", nil)
	local fadeOut = TweenService:Create(panel, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
	fadeOut.Completed:Once(function()
		if not open then
			gui.Enabled = false
		end
	end)
	fadeOut:Play()
	task.delay(0.3, function()
		if not open then
			setPrompt(true)
		end
	end)
end

clickArea.Activated:Connect(advance)

remote.OnClientEvent:Connect(function(msg, speaker, newLines)
	if msg ~= "Open" or type(newLines) ~= "table" or #newLines == 0 then
		return
	end
	npcRoot = findNpcRoot()
	lines, index = newLines, 1
	nameTag.Text = speaker or "D-0451"
	open = true
	player:SetAttribute("InDialog", true)
	setPrompt(false)
	panel.BackgroundTransparency = 0.08
	gui.Enabled = true
	ContextActionService:BindActionAtPriority(
		"FouDialogNext",
		onAction,
		false,
		Enum.ContextActionPriority.High.Value + 50,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonA
	)
	showLine(lines[1])
end)

-- Fermeture si le joueur s'éloigne
RunService.Heartbeat:Connect(function()
	if not open or not npcRoot then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - npcRoot.Position).Magnitude > CONFIG.MAX_DISTANCE then
		close()
	end
end)
