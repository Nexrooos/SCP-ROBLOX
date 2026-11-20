--[[
	SecurityMonitors (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.

	Écrans de surveillance du hall de transit : de vraies images, pas du texte.
	  - Caméras : parts taguées « SecurityCam » (attribut CamName), dans le décor du hall.
	  - Écrans  : parts taguées « SecurityScreen » (attributs Face = face visible, Feeds = noms des caméras
	    séparés par des virgules ; l'écran passe de l'une à l'autre toutes les CYCLE secondes).
	Chaque écran contient un ViewportFrame : une copie fixe du hall (construite une fois), plus des copies
	des personnages (joueurs, gardes, D-0451) recalées FPS fois par seconde. Les caméras du plafond balaient
	lentement. Incrustation : nom de la caméra, « REC », date et heure, lignes de balayage, parasites
	au changement de caméra.
	Les écrans ne sont construits que si le joueur est à moins de BUILD_DISTANCE (et détruits au-delà).
	Les écrans de console (attribut ConsoleScreen) affichent des lignes de données qui défilent.
]]

while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CONFIG = {
	BUILD_DISTANCE = 70, -- construit les écrans à moins de cette distance (studs)
	FPS = 15, -- images par seconde des personnages sur les écrans
	CYCLE = 9, -- changement de caméra (s)
	MIN_PART_SIZE = 1.1, -- les plus petites pièces du décor ne sont pas copiées (économie)
	FOV = 72,
	PAN_ANGLE = 14, -- balayage des caméras du plafond (degrés de part et d'autre)
	PAN_PERIOD = 16, -- s
	TINT = Color3.fromRGB(205, 228, 210),
}

local player = Players.LocalPlayer
local hub = workspace:WaitForChild("Hub")
local camera = workspace.CurrentCamera

---------------------------------------------------------------------------
-- Caméras
---------------------------------------------------------------------------
local cams = {} -- nom -> { cf, pan }
local function addCam(part)
	local name = part:GetAttribute("CamName")
	if name then
		-- les caméras du plafond (hautes) balaient ; celle de la cellule est fixe
		-- point de vue juste devant l'objectif (sinon on filme l'intérieur du boîtier)
		cams[name] = { cf = part.CFrame * CFrame.new(0, 0, -1.6), pan = part.Position.Y > 15 }
	end
end
for _, p in ipairs(CollectionService:GetTagged("SecurityCam")) do
	addCam(p)
end
CollectionService:GetInstanceAddedSignal("SecurityCam"):Connect(addCam)

---------------------------------------------------------------------------
-- Copies pour les ViewportFrame
---------------------------------------------------------------------------
local KEEP = { "DataModelMesh", "Decal", "Texture", "SurfaceAppearance" }
local function visualClone(part)
	local ok, c = pcall(function()
		return part:Clone()
	end)
	if not ok or not c then
		c = Instance.new("Part")
		c.Size = part.Size
		c.Color = part.Color
		c.Material = part.Material
		c.Transparency = part.Transparency
	end
	for _, child in ipairs(c:GetChildren()) do
		local keep = false
		for _, cls in ipairs(KEEP) do
			if child:IsA(cls) then
				keep = true
				break
			end
		end
		if not keep then
			child:Destroy()
		end
	end
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	return c
end

local function isScreen(part)
	return CollectionService:HasTag(part, "SecurityScreen")
end

-- Décor fixe du hall, copié par petits paquets
local function buildStatic(parent)
	local n = 0
	for _, d in ipairs(hub:GetDescendants()) do
		if
			d:IsA("BasePart")
			and d.Transparency < 0.98
			and d.Size.Magnitude >= CONFIG.MIN_PART_SIZE
			and not isScreen(d)
			and not d:GetAttribute("EditorOnly")
			and not (d.Parent and d.Parent.Name == "D-0451")
		then
			local c = visualClone(d)
			c.CFrame = d.CFrame
			c.Parent = parent
			n += 1
			if n % 150 == 0 then
				task.wait()
				if not parent.Parent then
					return
				end
			end
		end
	end
end

-- Modèles qui bougent : personnages des joueurs, gardes, D-0451
local function movingModels()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local guards = workspace:FindFirstChild("HubGuards")
	if guards then
		for _, g in ipairs(guards:GetChildren()) do
			table.insert(list, g)
		end
	end
	local cell = hub:FindFirstChild("Decor") and hub.Decor:FindFirstChild("CelluleIsolement")
	local fou = cell and cell:FindFirstChild("D-0451")
	if fou then
		table.insert(list, fou)
	end
	return list
end

---------------------------------------------------------------------------
-- Un écran
---------------------------------------------------------------------------
local screens = {} -- part -> état

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function buildScreen(part)
	local feeds = {}
	for name in string.gmatch(part:GetAttribute("Feeds") or "", "[^,]+") do
		table.insert(feeds, (name:gsub("^%s+", ""):gsub("%s+$", "")))
	end
	if #feeds == 0 then
		return
	end
	local gui = make("SurfaceGui", {
		Name = "SecurityFeed",
		Face = Enum.NormalId[part:GetAttribute("Face") or "Front"],
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 110,
		LightInfluence = 0,
		Brightness = 1.6,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	gui.Adornee = part
	local vp = make("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		Ambient = Color3.fromRGB(150, 158, 152),
		LightColor = Color3.fromRGB(215, 225, 215),
		LightDirection = Vector3.new(-0.3, -1, -0.25),
		ImageColor3 = CONFIG.TINT,
	}, gui)
	local vcam = make("Camera", { FieldOfView = CONFIG.FOV }, vp)
	vp.CurrentCamera = vcam
	local world = make("Folder", { Name = "Static" }, vp)
	local dynamic = make("Folder", { Name = "Moving" }, vp)
	task.spawn(buildStatic, world)

	-- Incrustation
	local overlay = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, gui)
	local vignette = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 2 }, overlay)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.18, 1),
			NumberSequenceKeypoint.new(0.82, 1),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
	}, vignette)
	for y = 0, 1, 0.025 do
		make("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, y),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, overlay)
	end
	local function text(props)
		props.BackgroundTransparency = 1
		props.Font = Enum.Font.Code
		props.TextScaled = true
		props.TextStrokeTransparency = 0.4
		props.ZIndex = 4
		return make("TextLabel", props, overlay)
	end
	local camLabel = text({
		Size = UDim2.fromScale(0.62, 0.1),
		Position = UDim2.fromScale(0.03, 0.04),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(235, 240, 235),
	})
	local rec = text({
		Size = UDim2.fromScale(0.22, 0.1),
		Position = UDim2.fromScale(0.75, 0.04),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 60, 50),
		Text = "● REC",
	})
	local clock = text({
		Size = UDim2.fromScale(0.6, 0.08),
		Position = UDim2.fromScale(0.03, 0.88),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 225, 220),
	})
	local noise = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 74, 72), Visible = false, ZIndex = 5, BorderSizePixel = 0, ClipsDescendants = true }, gui)
	for _ = 1, 40 do
		make("Frame", {
			Size = UDim2.fromScale(math.random() * 0.5, 0.01 + math.random() * 0.03),
			Position = UDim2.fromScale(math.random(), math.random()),
			BackgroundColor3 = Color3.fromRGB(200, 205, 200),
			BackgroundTransparency = math.random() * 0.6,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, noise)
	end

	local state = {
		part = part,
		gui = gui,
		vp = vp,
		vcam = vcam,
		dynamic = dynamic,
		mirrors = {}, -- source BasePart -> copie
		feeds = feeds,
		feedIndex = 1,
		nextSwitch = os.clock() + CONFIG.CYCLE + math.random() * 3,
		camLabel = camLabel,
		rec = rec,
		clock = clock,
		noise = noise,
		phase = math.random() * 10,
	}
	camLabel.Text = feeds[1]
	screens[part] = state
end

local function destroyScreen(part)
	local s = screens[part]
	if s then
		s.gui:Destroy()
		screens[part] = nil
	end
end

-- Synchronise les copies des personnages avec les originaux
local function syncMoving(s)
	local alive = {}
	for _, model in ipairs(movingModels()) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "HumanoidRootPart" then
				alive[d] = true
				local m = s.mirrors[d]
				if not m then
					m = visualClone(d)
					m.Parent = s.dynamic
					s.mirrors[d] = m
				end
				m.CFrame = d.CFrame
			end
		end
	end
	for src, m in pairs(s.mirrors) do
		if not alive[src] then
			m:Destroy()
			s.mirrors[src] = nil
		end
	end
end

local function switchFeed(s)
	s.feedIndex = s.feedIndex % #s.feeds + 1
	s.camLabel.Text = s.feeds[s.feedIndex]
	s.noise.Visible = true
	task.delay(0.12 + math.random() * 0.1, function()
		s.noise.Visible = false
	end)
end

---------------------------------------------------------------------------
-- Boucles
---------------------------------------------------------------------------
-- Construction / destruction selon la distance
task.spawn(function()
	while true do
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		for _, part in ipairs(CollectionService:GetTagged("SecurityScreen")) do
			if part:IsDescendantOf(workspace) then
				local d = r and (r.Position - part.Position).Magnitude or math.huge
				if d < CONFIG.BUILD_DISTANCE and not screens[part] then
					buildScreen(part)
				elseif d > CONFIG.BUILD_DISTANCE * 1.4 and screens[part] then
					destroyScreen(part)
				end
			end
		end
		task.wait(1)
	end
end)

-- Images des écrans
local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc < 1 / CONFIG.FPS then
		return
	end
	acc = 0
	local now = os.clock()
	local stamp = os.date("%d/%m/%Y  %H:%M:%S")
	for part, s in pairs(screens) do
		-- seulement les écrans visibles à l'écran du joueur
		local _, onScreen = camera:WorldToViewportPoint(part.Position)
		if onScreen then
			if now >= s.nextSwitch then
				s.nextSwitch = now + CONFIG.CYCLE
				switchFeed(s)
			end
			local cam = cams[s.feeds[s.feedIndex]]
			if cam then
				local cf = cam.cf
				if cam.pan then
					local a = math.sin((now + s.phase) * math.pi * 2 / CONFIG.PAN_PERIOD) * CONFIG.PAN_ANGLE
					cf = CFrame.new(cf.Position) * CFrame.Angles(0, math.rad(a), 0) * cf.Rotation
				end
				s.vcam.CFrame = cf
			end
			syncMoving(s)
			s.clock.Text = stamp
			s.rec.TextTransparency = (math.floor(now * 1.2) % 2 == 0) and 0 or 1
		end
	end
end)

---------------------------------------------------------------------------
-- Écrans de console : lignes de données qui défilent
---------------------------------------------------------------------------
local consoleLines = {}
for _, d in ipairs(hub:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("ConsoleScreen") then
		local gui = d:FindFirstChildOfClass("SurfaceGui")
		local frame = gui and gui:FindFirstChildOfClass("Frame")
		if frame then
			for _, l in ipairs(frame:GetChildren()) do
				if l:IsA("Frame") then
					table.insert(consoleLines, l)
				end
			end
		end
	end
end
task.spawn(function()
	while #consoleLines > 0 do
		for _, l in ipairs(consoleLines) do
			l.Size = UDim2.new(0.15 + math.random() * 0.75, 0, 0, 3)
			l.BackgroundTransparency = 0.15 + math.random() * 0.55
		end
		task.wait(0.6 + math.random() * 0.8)
	end
end)
