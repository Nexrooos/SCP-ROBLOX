--[[
	SCPTerminal (ModuleScript) — à placer dans ReplicatedStorage. Côté client uniquement.

	Cases de texte au style « document officiel / terminal de la Fondation », pour toutes les
	indications et notifications du jeu. Deux types :
	  - "info"   : bandeau jaune-orange (#E8A33D), texte du bandeau en noir ;
	  - "alerte" : bandeau rouge (#B3261E), texte du bandeau en blanc ("alert" est aussi accepté).

	Structure d'une case :
	  ┌──────────────────────────────────────────────┐
	  │ (logo) TERMINAL SITE-19 · TRANSIT    REF-0019 │  bandeau plein
	  │ ╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱ │  rayures de danger
	  │▌Texte principal (RobotoMono)                  │  corps : dégradé + lignes de balayage,
	  │▌NIV. ACCRÉD. 1 · CLASSE D · 14:02:31          │  barre d'accent à gauche, métadonnées + heure
	  └──────────────────────────────────────────────┘
	  + bordure 1 px couleur d'accent (transparence 0,5) et ombre portée douce.

	Ouverture : le bandeau se déplie de gauche à droite, puis le corps s'ouvre vers le bas,
	puis le texte s'écrit avec un curseur clignotant. Alerte : le bandeau clignote, la case
	tremble et l'image se coupe brièvement. Fermeture : fondu.

	Tailles : la largeur est en Scale (widthScale) bornée par un UISizeConstraint (minWidth / width).
	Les tailles de police sont réduites sur les petits écrans (hauteur d'écran < 820 px).

	Utilisation :
		local Terminal = require(ReplicatedStorage.SCPTerminal)

		local gui = Terminal.screenGui("MonHUD", 5)          -- ScreenGui qui respecte la barre du haut
		local hint = Terminal.new({
			kind = "info",
			header = "TERMINAL SITE-19 · TRANSIT",
			ref = "REF-0019",
			meta = "NIV. ACCRÉD. 1 · CLASSE D", -- facultatif (valeur par défaut selon le type)
			parent = gui,
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -12),
			widthScale = 0.5, minWidth = 260, width = 460, -- largeur : 50 % de l'écran, entre 260 et 460 px
			-- height = 80, -- hauteur fixe du corps (utile hors PlayerGui, ex. écran de téléportation)
		})
		hint:show("Présentez-vous à un sas de transit pour être affecté à une équipe.")
		hint:setText("…") -- change le texte sans rejouer l'animation (comptes à rebours)
		hint:hide()

		Terminal.notify("alerte", "Sas complet. Affectation refusée.") -- colonne de droite, fondu après 4 s
		Terminal.decorate(frame, "info") -- bordure, équerres et barre d'accent sur un panneau existant
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Terminal = {}
Terminal.__index = Terminal

-- Logo de la Fondation. L'image directe (rbxassetid://121817411121794) n'est pas encore servie par Roblox
-- (modération en cours) : on passe par sa vignette, qui est disponible.
Terminal.LOGO_IMAGE = "rbxthumb://type=Asset&id=121817411121794&w=420&h=420"

local THEMES = {
	info = {
		accent = Color3.fromHex("E8A33D"),
		band = Color3.fromHex("E8A33D"),
		bandText = Color3.fromRGB(14, 14, 14),
		cursor = Color3.fromHex("E8A33D"),
		line = Color3.fromRGB(64, 66, 70),
		header = Color3.fromRGB(138, 140, 136), -- gris secondaire (aussi utilisé par HubHUD)
		text = Color3.fromRGB(222, 223, 218),
		meta = Color3.fromRGB(108, 111, 112),
		bg = Color3.fromHex("0E1014"),
		gradTop = Color3.fromRGB(26, 29, 35),
		gradBottom = Color3.fromRGB(10, 11, 14),
	},
	alert = {
		accent = Color3.fromHex("B3261E"),
		band = Color3.fromHex("B3261E"),
		bandText = Color3.fromRGB(255, 255, 255),
		cursor = Color3.fromRGB(255, 92, 80),
		line = Color3.fromRGB(112, 34, 30),
		header = Color3.fromRGB(255, 112, 98),
		text = Color3.fromRGB(255, 228, 222),
		meta = Color3.fromRGB(150, 100, 96),
		bg = Color3.fromHex("0E1014"),
		gradTop = Color3.fromRGB(36, 16, 17),
		gradBottom = Color3.fromRGB(12, 9, 10),
	},
}
THEMES.alerte = THEMES.alert
Terminal.THEMES = THEMES

Terminal.DEFAULT_HEADER = {
	info = "TERMINAL SITE-19 · AVIS",
	alert = "ALERTE NIVEAU 3 · CONFINEMENT",
}
-- Pas de ligne de métadonnées par défaut (moins de texte à l'écran) ; passer opts.meta pour en afficher une
Terminal.DEFAULT_META = {}

-- Dimensions (px)
local BAND_H = 18
local STRIPE_H = 4
local HEAD_H = BAND_H + STRIPE_H
local ACCENT_W = 4
local SCAN_GAP = 3 -- une ligne de balayage tous les 3 px
local SCAN_MAX = 200 -- hauteur couverte par les lignes de balayage

-- Polices de base (px), réduites sur petit écran
local SIZE_HEADER, SIZE_REF, SIZE_TEXT, SIZE_META = 12, 11, 14, 9

-- Temps (s)
local TYPE_SPEED = 110 -- caractères par seconde
local FADE_IN, FADE_OUT = 0.12, 0.4
local UNFOLD_TIME = 0.22 -- dépliage du bandeau
local OPEN_TIME = 0.2 -- ouverture du corps
local NOTIFY_HOLD = 4 -- durée d'affichage d'une notification
local BODY_TRANSPARENCY = 0.06
local MAX_STACK = 2 -- notifications visibles en même temps

local function normalizeKind(kind)
	if kind == "alerte" or kind == "alert" or kind == "warn" then
		return "alert"
	end
	return "info"
end

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

-- Texte brut d'une chaîne RichText (pour l'effet machine à écrire)
local function plainText(s)
	s = s:gsub("<[^>]->", "")
	return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end
local function escape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

---------------------------------------------------------------------------
-- ScreenGui conformes : zone de sécurité de l'interface Roblox (barre du haut, boutons)
---------------------------------------------------------------------------
-- fullscreen = true pour les fonds plein écran (fondu, vignette) qui doivent couvrir la barre du haut
function Terminal.screenGui(name, displayOrder, fullscreen)
	return make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder or 0,
		IgnoreGuiInset = fullscreen == true,
		ScreenInsets = fullscreen and Enum.ScreenInsets.None or Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
end

---------------------------------------------------------------------------
-- Tailles de police selon l'écran
---------------------------------------------------------------------------
local allBoxes = setmetatable({}, { __mode = "k" })

local function textFactor()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 820
	return math.clamp(h / 820, 0.8, 1)
end
Terminal.textFactor = textFactor

local function applyTextSizes(box)
	local f = textFactor()
	box.headerLabel.TextSize = math.floor(SIZE_HEADER * f + 0.5)
	box.refLabel.TextSize = math.floor(SIZE_REF * f + 0.5)
	box.textLabel.TextSize = math.floor(box.textSize * f + 0.5)
	box.metaLabel.TextSize = math.floor(SIZE_META * f + 0.5)
end

local function watchViewport()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		for box in pairs(allBoxes) do
			applyTextSizes(box)
		end
	end)
end
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

---------------------------------------------------------------------------
-- Horloge des lignes de métadonnées (une seule boucle pour toutes les cases)
---------------------------------------------------------------------------
local active = {}
task.spawn(function()
	while true do
		local now = os.date("%H:%M:%S")
		for box in pairs(active) do
			if box.meta then
				box.metaLabel.Text = box.meta .. " · " .. now
			end
		end
		task.wait(1)
	end
end)

---------------------------------------------------------------------------
-- Logo de la Fondation (asset ou dessin de remplacement)
---------------------------------------------------------------------------
local function drawLogo(parent, color, z)
	if Terminal.LOGO_IMAGE then
		return make("ImageLabel", {
			Name = "Logo",
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Image = Terminal.LOGO_IMAGE,
			ImageColor3 = Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = z,
		}, parent)
	end
	local holder = make("Frame", { Name = "Logo", Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, ZIndex = z }, parent)
	local ring = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, holder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	make("UIStroke", { Color = color, Thickness = 1.5 }, ring)
	return holder
end

---------------------------------------------------------------------------
-- Habillage d'un panneau existant : bordure d'accent, équerres, barre d'accent
---------------------------------------------------------------------------
function Terminal.decorate(frame, kind, opts)
	opts = opts or {}
	local theme = THEMES[normalizeKind(kind)]
	local len = opts.corner or 10
	local thick = opts.thickness or 2

	local stroke = frame:FindFirstChild("TerminalStroke")
		or make("UIStroke", { Name = "TerminalStroke", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1 }, frame)
	stroke.Color = theme.accent
	stroke.Transparency = 0.5

	for _, name in ipairs({ "TerminalCorners", "TerminalAccent" }) do
		local old = frame:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	make("Frame", {
		Name = "TerminalAccent",
		Size = UDim2.new(0, ACCENT_W, 1, 0),
		BackgroundColor3 = theme.accent,
		BorderSizePixel = 0,
		ZIndex = frame.ZIndex + 1,
	}, frame)
	-- Équerres dans un cadre à part, pour ne pas être prises dans un UIListLayout du panneau
	local corners = make("Frame", { Name = "TerminalCorners", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = frame.ZIndex + 2 }, frame)
	for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local ax, ay = c[1], c[2]
		local pos = UDim2.new(ax, ax == 0 and -1 or 1, ay, ay == 0 and -1 or 1)
		for _, size in ipairs({ UDim2.fromOffset(len, thick), UDim2.fromOffset(thick, len) }) do
			make("Frame", {
				Name = "Corner",
				AnchorPoint = Vector2.new(ax, ay),
				Position = pos,
				Size = size,
				BackgroundColor3 = theme.accent,
				BorderSizePixel = 0,
				ZIndex = frame.ZIndex + 2,
			}, corners)
		end
	end
	return corners
end

---------------------------------------------------------------------------
-- Case de texte
---------------------------------------------------------------------------
function Terminal.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Terminal)
	self.kind = normalizeKind(opts.kind)
	local th = THEMES[self.kind]
	self.theme = th
	self.widthScale = opts.widthScale or 0.4
	self.maxWidth = opts.width or 480
	self.minWidth = math.min(opts.minWidth or 220, self.maxWidth)
	self.fixedHeight = opts.height
	self.textSize = opts.textSize or SIZE_TEXT
	self.meta = opts.meta or Terminal.DEFAULT_META[self.kind]
	self.visible = false
	self.alpha = 0
	self._token = 0
	self._fullText = ""
	self._stripesWidth = 0
	self._cursor = string.format("<font color='#%s'>▌</font>", th.cursor:ToHex())

	local z = opts.zIndex or 1
	local zc = z + 1

	-- Conteneur (porte l'ombre et la carte). Hauteur gérée à la main, voir _resizeRoot.
	local root = make("Frame", {
		Name = opts.name or "TerminalBox",
		AnchorPoint = opts.anchorPoint or Vector2.zero,
		Position = opts.position or UDim2.new(),
		Size = UDim2.new(self.widthScale, 0, 0, HEAD_H),
		BackgroundTransparency = 1,
		LayoutOrder = opts.layoutOrder or 0,
		Visible = false,
		ZIndex = z,
	}, opts.parent)
	self.root = root
	make("UISizeConstraint", {
		MinSize = Vector2.new(self.minWidth, 0),
		MaxSize = Vector2.new(self.maxWidth, math.huge),
	}, root)

	-- Ombre portée douce : trois couches arrondies, de plus en plus larges et transparentes
	for i, t in ipairs({ 0.8, 0.88, 0.94 }) do
		local s = make("Frame", {
			Name = "Shadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 4),
			Size = UDim2.new(1, i * 5, 1, i * 5),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = t,
			BorderSizePixel = 0,
			ZIndex = z,
		}, root)
		make("UICorner", { CornerRadius = UDim.new(0, 3 + i * 2) }, s)
	end

	-- Carte (découpe tout ce qui dépasse)
	local card = make("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = zc,
	}, root)
	self.card = card
	make("UIStroke", { Color = th.accent, Transparency = 0.5, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

	-- 1. Bandeau plein + 2. rayures de danger (se déplient ensemble de gauche à droite)
	local headClip = make("Frame", {
		Name = "HeadClip",
		Size = UDim2.new(1, 0, 0, HEAD_H),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 1,
		ZIndex = zc,
	}, card)
	self.headClip = headClip
	local band = make("Frame", {
		Name = "Band",
		Size = UDim2.fromOffset(self.maxWidth, BAND_H),
		BackgroundColor3 = th.band,
		BorderSizePixel = 0,
		ZIndex = zc,
	}, headClip)
	self.band = band
	drawLogo(band, th.bandText, zc)
	self.headerLabel = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -22 - 84, 1, 0),
		Font = Enum.Font.Code,
		TextSize = SIZE_HEADER,
		TextColor3 = th.bandText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = opts.header or Terminal.DEFAULT_HEADER[self.kind],
		ZIndex = zc,
	}, band)
	self.refLabel = make("TextLabel", {
		Name = "Ref",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 78, 1, 0),
		Font = Enum.Font.Code,
		TextSize = SIZE_REF,
		TextColor3 = th.bandText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = opts.ref or "",
		ZIndex = zc,
	}, band)
	-- Rayures : barres inclinées dans un CanvasGroup ; recalculées selon la largeur réelle (voir _onResize)
	self.stripes = make("CanvasGroup", {
		Name = "Stripes",
		Position = UDim2.fromOffset(0, BAND_H),
		Size = UDim2.fromOffset(self.maxWidth, STRIPE_H),
		BackgroundColor3 = Color3.fromRGB(236, 190, 38),
		BorderSizePixel = 0,
		ZIndex = zc,
	}, headClip)

	-- 3. Corps (s'ouvre vers le bas)
	local bodyClip = make("Frame", {
		Name = "BodyClip",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 2,
		ZIndex = zc,
	}, card)
	self.bodyClip = bodyClip
	local body = make("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = BODY_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = zc,
	}, bodyClip)
	self.body = body
	make("UIGradient", { Color = ColorSequence.new(th.gradTop, th.gradBottom), Rotation = 90 }, body)
	-- Lignes de balayage CRT
	local scan = make("Frame", { Name = "Scanlines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = zc }, body)
	for y = 0, SCAN_MAX, SCAN_GAP do
		make("Frame", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.95,
			BorderSizePixel = 0,
			ZIndex = zc,
		}, scan)
	end
	-- 4. Barre d'accent verticale
	make("Frame", { Name = "Accent", Size = UDim2.new(0, ACCENT_W, 1, 0), BackgroundColor3 = th.accent, BorderSizePixel = 0, ZIndex = zc }, body)

	-- Contenu : texte principal + 5. ligne de métadonnées
	local content = make("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = zc,
	}, body)
	self.content = content
	make("UIPadding", {
		PaddingLeft = UDim.new(0, ACCENT_W + 9),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 5),
	}, content)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, content)
	self.textLabel = make("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.RobotoMono,
		TextSize = self.textSize,
		TextColor3 = th.text,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = opts.align or Enum.TextXAlignment.Left,
		LineHeight = 1.05,
		Text = "",
		LayoutOrder = 1,
		ZIndex = zc,
	}, content)
	self.metaLabel = make("TextLabel", {
		Name = "Meta",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 10),
		Font = Enum.Font.Code,
		TextSize = SIZE_META,
		TextColor3 = th.meta,
		TextXAlignment = opts.align or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = self.meta or "",
		Visible = self.meta ~= nil,
		LayoutOrder = 2,
		ZIndex = zc,
	}, content)

	allBoxes[self] = true
	applyTextSizes(self)
	self:_onResize()

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_onResize()
	end)
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end)
	bodyClip:GetPropertyChangedSignal("Size"):Connect(function()
		self:_resizeRoot()
	end)

	-- Fondu : transparence de base de chaque élément, puis alpha 0 → 1
	self._fades = {}
	self:_track(root)

	self._alphaValue = Instance.new("NumberValue")
	self._alphaValue.Changed:Connect(function(v)
		self:_setAlpha(v)
	end)
	self:_setAlpha(0)
	return self
end

function Terminal:_track(o)
	if o:IsA("CanvasGroup") then
		table.insert(self._fades, { o, "GroupTransparency", o.GroupTransparency })
		return -- le groupe gère ses enfants
	end
	if o:IsA("GuiObject") and o.BackgroundTransparency < 1 then
		table.insert(self._fades, { o, "BackgroundTransparency", o.BackgroundTransparency })
	end
	if o:IsA("TextLabel") then
		table.insert(self._fades, { o, "TextTransparency", o.TextTransparency })
	elseif o:IsA("ImageLabel") then
		table.insert(self._fades, { o, "ImageTransparency", o.ImageTransparency })
	elseif o:IsA("UIStroke") then
		table.insert(self._fades, { o, "Transparency", o.Transparency })
	end
	for _, c in ipairs(o:GetChildren()) do
		self:_track(c)
	end
end

---------------------------------------------------------------------------
-- Mise en page
---------------------------------------------------------------------------
-- Largeur réelle (hors PlayerGui, AbsoluteSize vaut 0 : on prend la largeur maximale)
function Terminal:_width()
	local w = self.root.AbsoluteSize.X
	return w > 0 and w or self.maxWidth
end

-- Bandeau et rayures suivent la largeur réelle ; les barres restent entières à l'intérieur de la bande
function Terminal:_onResize()
	local w = math.floor(self:_width() + 0.5)
	self.band.Size = UDim2.fromOffset(w, BAND_H)
	self.stripes.Size = UDim2.fromOffset(w, STRIPE_H)
	if math.abs(w - self._stripesWidth) < 1 then
		return
	end
	self._stripesWidth = w
	self.stripes:ClearAllChildren()
	for x = 8, w - 8, 9 do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, STRIPE_H / 2),
			Size = UDim2.fromOffset(4, STRIPE_H * 3),
			Rotation = 40,
			BackgroundColor3 = Color3.fromRGB(16, 16, 16),
			BorderSizePixel = 0,
			ZIndex = self.stripes.ZIndex,
		}, self.stripes)
	end
end

function Terminal:_layout()
	local h = self.fixedHeight or self.content.AbsoluteSize.Y
	if self._typing and self._targetH then
		h = math.max(h, self._targetH) -- pas de saut de hauteur pendant la frappe
	end
	self.body.Size = UDim2.new(1, 0, 0, h)
	if not self._opening then
		self.bodyClip.Size = UDim2.new(1, 0, 0, self._bodyOpen and h or 0)
	end
end

function Terminal:_resizeRoot()
	self.root.Size = UDim2.new(self.widthScale, 0, 0, HEAD_H + self.bodyClip.Size.Y.Offset)
end

function Terminal:_measure()
	return self.fixedHeight or self.content.AbsoluteSize.Y
end

---------------------------------------------------------------------------
-- Transparence globale
---------------------------------------------------------------------------
function Terminal:_setAlpha(a)
	self.alpha = a
	for _, f in ipairs(self._fades) do
		f[1][f[2]] = 1 - (1 - f[3]) * a
	end
end

function Terminal:_fadeTo(target, duration, onDone)
	if self._tween then
		self._tween:Cancel()
	end
	self._alphaValue.Value = self.alpha
	local tween = TweenService:Create(self._alphaValue, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = target })
	self._tween = tween
	if onDone then
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				onDone()
			end
		end)
	end
	tween:Play()
end

---------------------------------------------------------------------------
-- Animations
---------------------------------------------------------------------------
-- Alerte : bandeau qui clignote 3 fois, tremblement de la case, coupure de l'image
function Terminal:_glitch(token)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.35 and token == self._token do
			self.card.Position = UDim2.fromOffset(math.random(-3, 3), math.random(-2, 2))
			task.wait(0.03)
		end
		self.card.Position = UDim2.new()
	end)
	local dark = Color3.fromRGB(40, 10, 10)
	for i = 1, 3 do
		if token ~= self._token then
			return
		end
		self.band.BackgroundColor3 = dark
		if i == 2 then
			self:_setAlpha(0) -- coupure de l'image
		end
		task.wait(0.06)
		self.band.BackgroundColor3 = self.theme.band
		if i == 2 then
			self:_setAlpha(1)
		end
		task.wait(0.09)
	end
end

-- Machine à écrire avec curseur, puis curseur qui clignote quelques fois
function Terminal:_type(token)
	-- Hauteur finale mesurée avec le texte complet (masqué), pour éviter les sauts pendant la frappe
	self.textLabel.Text = self._fullText
	self.textLabel.MaxVisibleGraphemes = 0
	task.wait()
	if token ~= self._token then
		return
	end
	self._targetH = self.content.AbsoluteSize.Y
	self._typing = true
	self.textLabel.MaxVisibleGraphemes = -1
	local t0 = os.clock()
	while token == self._token do
		local plain = plainText(self._fullText)
		local total = utf8.len(plain) or #plain
		local n = math.floor((os.clock() - t0) * TYPE_SPEED)
		if n >= total then
			break
		end
		local cut = utf8.offset(plain, n + 1) or (#plain + 1)
		self.textLabel.Text = escape(plain:sub(1, cut - 1)) .. self._cursor
		task.wait()
	end
	if token ~= self._token then
		return
	end
	self._typing = false
	self:_layout()
	for i = 1, 6 do
		if token ~= self._token then
			return
		end
		self.textLabel.Text = self._fullText .. (i % 2 == 1 and self._cursor or "")
		task.wait(0.22)
	end
	if token == self._token then
		self.textLabel.Text = self._fullText
	end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- Affiche la case. opts : header, ref, hold (s depuis l'apparition, puis fondu), destroyOnHide,
-- instant (sans animation)
function Terminal:show(text, opts)
	opts = opts or {}
	if opts.header then
		self.headerLabel.Text = opts.header
	end
	if opts.ref then
		self.refLabel.Text = opts.ref
	end
	local wasVisible = self.visible
	-- Déjà affichée ou en cours d'ouverture : on met seulement le texte à jour, sans couper l'animation
	if wasVisible and (self._opening or self._fullText == text) then
		self._fullText = text
		self:_fadeTo(1, FADE_IN)
		if opts.hold then
			local token = self._token
			task.delay(opts.hold, function()
				if token == self._token then
					self:hide(opts.destroyOnHide)
				end
			end)
		end
		return
	end
	self._token += 1
	local token = self._token
	local sameText = false
	self._fullText = text
	self.visible = true
	self.root.Visible = true
	active[self] = true
	if self.meta then
		self.metaLabel.Text = self.meta .. " · " .. os.date("%H:%M:%S")
	end

	local duration = 0
	if opts.instant then
		if self._tween then
			self._tween:Cancel()
		end
		self._opening, self._typing = false, false
		self._bodyOpen = true
		self.headClip.Size = UDim2.new(1, 0, 0, HEAD_H)
		self.textLabel.MaxVisibleGraphemes = -1
		self.textLabel.Text = text
		self:_layout()
		self:_setAlpha(1)
	elseif not wasVisible then
		-- Ouverture complète : bandeau → corps → texte
		duration = UNFOLD_TIME + OPEN_TIME + (self.kind == "alert" and 0.45 or 0)
		self._opening, self._bodyOpen, self._typing = true, false, false
		self.card.Position = UDim2.new()
		self.headClip.Size = UDim2.new(0, 0, 0, HEAD_H)
		self.bodyClip.Size = UDim2.new(1, 0, 0, 0)
		self.textLabel.Text = text
		self.textLabel.MaxVisibleGraphemes = 0
		self:_fadeTo(1, FADE_IN)
		task.spawn(function()
			TweenService:Create(self.headClip, TweenInfo.new(UNFOLD_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, HEAD_H) }):Play()
			task.wait(UNFOLD_TIME)
			if token ~= self._token then
				return
			end
			if self.kind == "alert" then
				self:_glitch(token)
				if token ~= self._token then
					return
				end
			end
			local h = self:_measure()
			TweenService:Create(self.bodyClip, TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, h) }):Play()
			task.wait(OPEN_TIME)
			if token ~= self._token then
				return
			end
			self._opening, self._bodyOpen = false, true
			self:_layout()
			self:_type(token)
		end)
	elseif not sameText then
		self:_fadeTo(1, FADE_IN)
		task.spawn(self._type, self, token)
	else
		self:_fadeTo(1, FADE_IN)
	end

	if opts.hold then
		-- Durée comptée depuis l'apparition, mais jamais avant la fin de la frappe
		local typing = sameText and 0 or (utf8.len(plainText(text)) or #text) / TYPE_SPEED
		task.delay(math.max(opts.hold, duration + typing + 0.6), function()
			if token == self._token then
				self:hide(opts.destroyOnHide)
			end
		end)
	end
end

-- Change le texte sans rejouer l'animation (compte à rebours, compteur…)
function Terminal:setText(text)
	self._fullText = text
	if not self._typing and not self._opening then
		self.textLabel.Text = text
	end
end

function Terminal:hide(destroy)
	self._token += 1
	local token = self._token
	if not self.visible then
		if destroy then
			self:destroy()
		end
		return
	end
	self.visible = false
	self._typing = false
	self:_fadeTo(0, FADE_OUT, function()
		if token ~= self._token then
			return
		end
		self.root.Visible = false
		self._opening, self._bodyOpen = false, false
		self.card.Position = UDim2.new()
		active[self] = nil
		if destroy then
			self:destroy()
		end
	end)
end

function Terminal:destroy()
	self._token += 1
	active[self] = nil
	allBoxes[self] = nil
	if self._tween then
		self._tween:Cancel()
	end
	self._alphaValue:Destroy()
	self.root:Destroy()
end

---------------------------------------------------------------------------
-- Notifications temporaires : colonne unique en haut à droite, jamais superposées
---------------------------------------------------------------------------
local stack = {}
local holder

local function getHolder()
	if holder and holder.Parent then
		return holder
	end
	local gui = Terminal.screenGui("SCPNotifications", 50)
	holder = make("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0.3, 0, 1, -24),
		BackgroundTransparency = 1,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(220, 0), MaxSize = Vector2.new(360, math.huge) }, holder)
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, holder)
	return holder
end

local counter = 0
-- kind : "info" ou "alerte". opts : header, ref, meta, hold (défaut 4 s)
function Terminal.notify(kind, text, opts)
	opts = opts or {}
	counter += 1
	local box = Terminal.new({
		kind = kind,
		header = opts.header,
		ref = opts.ref,
		meta = opts.meta,
		parent = getHolder(),
		widthScale = 1,
		minWidth = 200,
		width = 360,
		layoutOrder = counter,
	})
	table.insert(stack, box)
	while #stack > MAX_STACK do
		table.remove(stack, 1):hide(true)
	end
	box.root.Destroying:Connect(function()
		local i = table.find(stack, box)
		if i then
			table.remove(stack, i)
		end
	end)
	box:show(text, { hold = opts.hold or NOTIFY_HOLD, destroyOnHide = true })
	return box
end

return Terminal
