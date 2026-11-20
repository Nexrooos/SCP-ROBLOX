--[[
	HubHUD (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.
	Nécessite le ModuleScript ReplicatedStorage.SCPTerminal (style des cases de texte).

	Interface du hall de transit (voir HubServer) :
	  - case Site-19 (personnel présent) : plus affichée, pour alléger l'écran ;
	  - indication en bas de l'écran hors des sas ;
	  - panneau du sas : effectif (SOLO / 2 / 3 / 4) pour l'hôte, sujets affectés, compte à rebours,
	    « Lancer le transfert » et « Quitter le sas » ;
	  - fondu au noir pendant la décontamination + écran de transfert pendant la téléportation ;
	  - avis du serveur (sas complet, échec du transfert…) via Terminal.notify.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

-- Uniquement dans le hall (serveur public)
while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local Terminal = require(ReplicatedStorage:WaitForChild("SCPTerminal"))
local remote = ReplicatedStorage:WaitForChild("HubRemote")

local THEME = Terminal.THEMES.info
local C = {
	bg = THEME.bg,
	line = THEME.line,
	text = THEME.text,
	dim = THEME.header,
	amber = THEME.accent,
	green = Color3.fromRGB(80, 220, 120),
	red = Terminal.THEMES.alert.accent,
}
local HEAD = Enum.Font.Code
local MONO = Enum.Font.RobotoMono

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function label(props, parent)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = MONO,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end

local gui = Terminal.screenGui("HubHUD", 5) -- respecte la barre du haut et les boutons Roblox
local overlay = Terminal.screenGui("HubOverlay", 20, true) -- fondu plein écran

workspace:GetAttributeChangedSignal("ServerMode"):Connect(function()
	if workspace:GetAttribute("ServerMode") ~= "Hub" then
		gui:Destroy()
		overlay:Destroy()
	end
end)

-- Colonne de gauche, fixe : case du lieu, puis panneau du sas quand on est dans un sas
local leftColumn = make("Frame", {
	Name = "LeftColumn",
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.new(0.3, 0, 1, -24),
	BackgroundTransparency = 1,
}, gui)
make("UISizeConstraint", { MinSize = Vector2.new(200, 0), MaxSize = Vector2.new(340, math.huge) }, leftColumn)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, leftColumn)

---------------------------------------------------------------------------
-- Case Site-19 (haut gauche)
---------------------------------------------------------------------------
local siteBox = Terminal.new({
	kind = "info",
	header = "FONDATION SCP · SITE-19",
	ref = "SECT. T-01",
	parent = leftColumn,
	widthScale = 1,
	minWidth = 200,
	width = 300,
	layoutOrder = 1,
})

local function siteText()
	local n = #Players:GetPlayers()
	return string.format(
		"<font face='Michroma' size='16'>HALL DE TRANSIT</font>\n<font color='#50DC78'>●</font> Personnel présent : %d",
		n
	)
end
local function refreshOnline()
	siteBox:setText(siteText())
end
Players.PlayerAdded:Connect(refreshOnline)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshOnline)
end)

---------------------------------------------------------------------------
-- Indication (bas de l'écran)
---------------------------------------------------------------------------
local hint = Terminal.new({
	kind = "info",
	header = "HALL DE TRANSIT",
	parent = gui,
	anchorPoint = Vector2.new(0.5, 1),
	position = UDim2.new(0.5, 0, 1, -12),
	widthScale = 0.5,
	minWidth = 260,
	width = 460,
})
local HINT_TEXT = "Entrez dans un sas au voyant <font color='#50DC78'>vert</font> pour lancer une partie."

---------------------------------------------------------------------------
-- Panneau du sas
---------------------------------------------------------------------------
local PANEL_W, PANEL_H = 340, 372
local panel = make("Frame", {
	Name = "SasPanel",
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	LayoutOrder = 2,
	Visible = false,
}, leftColumn)
Terminal.decorate(panel, "info")
-- Petits écrans : le panneau est réduit pour tenir dans la colonne (largeur et hauteur)
local panelScale = make("UIScale", {}, panel)
local function fitPanel()
	local col = leftColumn.AbsoluteSize
	if col.X > 0 and col.Y > 0 then
		panelScale.Scale = math.clamp(math.min(col.X / PANEL_W, col.Y / PANEL_H), 0.5, 1)
	end
end
leftColumn:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
fitPanel()

local titleLabel = label({ Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, -124, 0, 14), Font = HEAD, TextSize = 12, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd }, panel)
local stateChip = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 9),
	Size = UDim2.fromOffset(100, 14),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = HEAD,
	TextSize = 11,
}, panel)
make("Frame", { Position = UDim2.fromOffset(14, 29), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = C.line, BorderSizePixel = 0 }, panel)
local statusLabel = label({ Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 22), TextSize = 15, TextWrapped = true, RichText = true }, panel)

local function sectionTitle(text, y)
	return label({ Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 12), Font = HEAD, TextSize = 11, TextColor3 = C.dim, Text = text }, panel)
end

sectionTitle("EFFECTIF DU GROUPE", 72)
local modeRow = make("Frame", { Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1 }, panel)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, modeRow)
local modeHint = label({ Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 34), TextColor3 = C.dim, TextWrapped = true }, panel)

local modeButtons = {}
for n = 1, 4 do
	local b = make("TextButton", {
		Size = UDim2.new(0.25, -5, 1, 0),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = HEAD,
		TextSize = 14,
		TextColor3 = C.text,
		Text = n == 1 and "SOLO" or tostring(n),
	}, modeRow)
	modeButtons[n] = { button = b, stroke = make("UIStroke", { Color = C.line, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b) }
	b.Activated:Connect(function()
		remote:FireServer("SetSize", n)
	end)
end

sectionTitle("SUJETS AFFECTÉS", 138)
local slots = {}
for i = 1, 4 do
	local row = make("Frame", {
		Position = UDim2.fromOffset(14, 156 + (i - 1) * 30),
		Size = UDim2.new(1, -28, 0, 26),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, panel)
	make("UIStroke", { Color = C.line, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
	local num = label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 34, 1, 0), Font = HEAD, TextSize = 12, TextColor3 = C.dim, Text = string.format("%02d", i) }, row)
	local name = label({ Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -50, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, row)
	slots[i] = { row = row, num = num, name = name }
end

local function actionButton(text, y, accent)
	local b = make("TextButton", {
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, 32),
		BackgroundColor3 = accent and C.amber or C.bg,
		BackgroundTransparency = accent and 0.82 or 0.2,
		BorderSizePixel = 0,
		Font = HEAD,
		TextSize = 13,
		TextColor3 = accent and C.amber or C.text,
		Text = text,
	}, panel)
	make("UIStroke", { Color = accent and C.amber or C.line, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end
local launchButton = actionButton("▶ LANCER LE TRANSFERT", 288, true)
local leaveButton = actionButton("QUITTER LE SAS", 326, false)
launchButton.Activated:Connect(function()
	remote:FireServer("Launch")
end)
leaveButton.Activated:Connect(function()
	remote:FireServer("Leave")
end)

---------------------------------------------------------------------------
-- Fondu de départ + écran de transfert
---------------------------------------------------------------------------
local fade = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20 }, overlay)
local deconBox = Terminal.new({
	kind = "info",
	header = "DÉCONTAMINATION",
	parent = overlay,
	anchorPoint = Vector2.new(0.5, 0.5),
	position = UDim2.fromScale(0.5, 0.5),
	widthScale = 0.5,
	minWidth = 280,
	width = 460,
	zIndex = 22,
})

local function buildTeleportGui()
	local tg = Instance.new("ScreenGui")
	tg.Name = "TransferScreen"
	tg.IgnoreGuiInset = true
	make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, tg)
	local box = Terminal.new({
		kind = "info",
		header = "TRANSFERT",
		parent = tg,
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		widthScale = 0.5,
		minWidth = 280,
		width = 460,
		height = 86, -- hors PlayerGui, la hauteur du texte ne peut pas être mesurée
		zIndex = 2,
	})
	box:show("Transfert vers la Zone de Confinement Légère.", { instant = true })
	box:_setAlpha(1)
	return tg
end
pcall(function()
	TeleportService:SetTeleportGui(buildTeleportGui())
end)

local fading = false
local function setFade(on, duration)
	if on == fading then
		return
	end
	fading = on
	-- On laisse voir la brume de décontamination, puis fondu au noir sur les 2 dernières secondes
	local delay = on and math.max(0, (duration or 4) - 2) or 0
	local info = TweenInfo.new(on and 2 or 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, delay)
	TweenService:Create(fade, info, { BackgroundTransparency = on and 0 or 1 }):Play()
	if on then
		task.delay(delay, function()
			if fading then
				deconBox:show("Transfert en cours…")
			end
		end)
	else
		deconBox:hide()
	end
end

---------------------------------------------------------------------------
-- Avis du serveur
---------------------------------------------------------------------------
remote.OnClientEvent:Connect(function(kind, text, style)
	if kind ~= "Toast" then
		return
	end
	if style == "warn" then
		Terminal.notify("alerte", text, { header = "AVIS" })
	else
		Terminal.notify("info", text, { header = "TRANSIT" })
	end
end)

---------------------------------------------------------------------------
-- Mise à jour du panneau
---------------------------------------------------------------------------
local currentSas, sasConn

local function findSas(name)
	for _, m in ipairs(CollectionService:GetTagged("HubSas")) do
		if m.Name == name then
			return m
		end
	end
end

local CHIP = {
	Setup = { "■ CONFIGURATION", C.amber },
	Waiting = { "■ EMBARQUEMENT", C.amber },
	Launching = { "■ TRANSFERT", C.red },
}

local function render()
	local m = currentSas
	panel.Visible = m ~= nil
	if m then
		hint:hide()
		siteBox:hide()
	else
		hint:show(HINT_TEXT)
		setFade(false)
		return
	end
	local state = m:GetAttribute("State") or "Free"
	local size = m:GetAttribute("Size")
	local count = m:GetAttribute("Count") or 0
	local countdown = m:GetAttribute("Countdown") or 0
	local isHost = m:GetAttribute("Host") == player.UserId

	titleLabel.Text = (string.gsub(m.Name, "_", " ")):upper()
	local chip = CHIP[state] or { "■ DISPONIBLE", C.green }
	stateChip.Text = chip[1]
	stateChip.TextColor3 = chip[2]

	if state == "Setup" then
		statusLabel.Text = isHost and string.format("Déclarez l'effectif du groupe · %d s", countdown)
			or "En attente de la déclaration de l'hôte."
	elseif state == "Waiting" then
		local full = size and count >= size
		statusLabel.Text = string.format("%s · %d/%d · transfert dans %d s", full and "Effectif complet" or "Embarquement", count, size or 4, countdown)
	elseif state == "Launching" then
		statusLabel.Text = "<font color='#FF3E32'>Portes verrouillées.</font> Décontamination."
	else
		statusLabel.Text = ""
	end

	-- Choix de l'effectif : réservé à l'hôte, avant le transfert
	local canChoose = isHost and (state == "Setup" or state == "Waiting")
	modeRow.Visible = canChoose
	modeHint.Visible = not canChoose
	modeHint.Text = size and (size == 1 and "SOLO · 1 sujet" or string.format("Groupe de %d sujets", size)) or "Non déclaré"
	for n, mb in pairs(modeButtons) do
		local selected = size == n
		mb.button.BackgroundColor3 = selected and C.amber or C.bg
		mb.button.BackgroundTransparency = selected and 0 or 0.2
		mb.button.TextColor3 = selected and C.bg or C.text
		mb.stroke.Color = selected and C.amber or C.line
	end

	-- Sujets affectés
	local names = string.split(m:GetAttribute("Members") or "", "\n")
	local slotCount = size or 4
	for i, s in ipairs(slots) do
		s.row.Visible = i <= slotCount
		local n = names[i]
		if n and n ~= "" then
			s.name.Text = n
			s.name.TextColor3 = C.text
			s.num.TextColor3 = C.amber
		else
			s.name.Text = "libre"
			s.name.TextColor3 = C.dim
			s.num.TextColor3 = C.dim
		end
	end

	launchButton.Visible = isHost and state == "Waiting"
	leaveButton.Visible = state ~= "Launching"

	setFade(state == "Launching", 4.5)
end

local function bindSas()
	if sasConn then
		sasConn:Disconnect()
		sasConn = nil
	end
	local name = player:GetAttribute("HubSas")
	currentSas = name and findSas(name) or nil
	if currentSas then
		sasConn = currentSas.AttributeChanged:Connect(render)
	end
	render()
end

player:GetAttributeChangedSignal("HubSas"):Connect(bindSas)
bindSas()
