--[[
	FoundationGuard (ModuleScript) — à placer dans ServerStorage. Côté serveur uniquement.

	Fabrique un PNJ garde de la Fondation : avatar R15 de base (Players:CreateHumanoidModelFromDescription),
	tenue sombre, casque à visière, gilet « SÉCURITÉ » dans le dos, fusil porté en travers de la poitrine.
	L'équipement est fait de parts simples soudées au corps (aucun asset externe).

	Option walkSpeed : vitesse de marche (rondes du hall). Sous 10 studs/s, l'animation de marche est jouée.
	Options de personnage (gardes du hall, voir HubLife) : skinColor, scale, face (spec ServerStorage.FaceKit),
	helmet = "visorUp" | "none" (béret), hairColor, nameTag (bande sur la poitrine), mug (tasse à la main).

	Animations : celles de marche, de course et d'attente par défaut de Roblox. Les ID sont lus dans le script
	« Animate » que Roblox génère avec l'avatar. Comme ce script est un LocalScript (inactif pour un PNJ),
	on joue les pistes depuis le serveur sur l'Animator, et elles se répliquent aux clients.

	Utilisation :
		local FoundationGuard = require(ServerStorage.FoundationGuard)
		local guard = FoundationGuard.new({ name = "Garde_1", cframe = spawnPart.CFrame, parent = folder })
		guard.humanoid:MoveTo(position)
		guard:destroy()
]]

local Players = game:GetService("Players")

local FoundationGuard = {}
FoundationGuard.__index = FoundationGuard

local applyPersona -- défini plus bas

local UNIFORM = Color3.fromRGB(30, 33, 38)
local GEAR = Color3.fromRGB(40, 43, 40)
local METAL = Color3.fromRGB(24, 24, 26)
local SKINS = {
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 105, 75),
	Color3.fromRGB(105, 70, 50),
}

-- Modèle de base construit une seule fois, puis cloné (CreateHumanoidModelFromDescription peut prendre du temps).
local template = nil
local animIds = nil

local function buildTemplate()
	local desc = Instance.new("HumanoidDescription")
	desc.TorsoColor = UNIFORM
	desc.LeftArmColor = UNIFORM
	desc.RightArmColor = UNIFORM
	desc.LeftLegColor = UNIFORM
	desc.RightLegColor = UNIFORM
	desc.HeadColor = SKINS[1]

	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)

	-- Animations de course et d'attente par défaut, prises dans le script Animate généré
	local animate = rig:FindFirstChild("Animate")
	local function idOf(folderName)
		local f = animate and animate:FindFirstChild(folderName)
		local a = f and f:FindFirstChildWhichIsA("Animation")
		return a and a.AnimationId or nil
	end
	animIds = { run = idOf("run"), walk = idOf("walk"), idle = idOf("idle") }
	if animate then
		animate:Destroy()
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 18
	humanoid.BreakJointsOnDeath = false

	local head = rig:FindFirstChild("Head")
	local torso = rig:FindFirstChild("UpperTorso")

	local function gear(name, base, size, offset, color, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = true
		for k, v in pairs(props or {}) do
			p[k] = v
		end
		p.CFrame = base.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = base
		w.Part1 = p
		w.Parent = p
		p.Parent = rig
		return p
	end

	-- Casque (calotte arrondie) + visière fumée
	local helmet = gear("Helmet", head, Vector3.new(1.45, 1.0, 1.55), CFrame.new(0, 0.32, 0.04), GEAR)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = helmet
	gear("Visor", head, Vector3.new(1.2, 0.3, 0.1), CFrame.new(0, 0.18, -0.62), Color3.fromRGB(12, 14, 18), {
		Material = Enum.Material.Glass,
		Reflectance = 0.25,
		Transparency = 0.15,
	})

	-- Gilet pare-balles + inscription dans le dos (visible dans le plan de dos)
	local vest = gear("Vest", torso, torso.Size + Vector3.new(0.18, -0.1, 0.25), CFrame.new(0, 0.02, 0), Color3.fromRGB(22, 24, 28))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	gui.Parent = vest
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 235, 225)
	label.Text = "SÉCURITÉ"
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.3, 0)
	pad.PaddingLeft = UDim.new(0.1, 0)
	pad.PaddingRight = UDim.new(0.1, 0)
	pad.Parent = label
	gear("Pouches", torso, Vector3.new(1.5, 0.45, 0.25), CFrame.new(0, -0.45, -0.66), GEAR)

	-- Fusil tenu en travers de la poitrine (longueur selon l'axe X du repère « arme »)
	local gunCF = CFrame.new(0.1, 0.05, -0.85) * CFrame.Angles(0, 0, math.rad(32))
	local metal = { Material = Enum.Material.Metal }
	gear("RifleBody", torso, Vector3.new(2.0, 0.32, 0.22), gunCF, METAL, metal)
	gear("RifleStock", torso, Vector3.new(0.75, 0.42, 0.18), gunCF * CFrame.new(-1.3, -0.08, 0), METAL, metal)
	gear("RifleMag", torso, Vector3.new(0.22, 0.6, 0.16), gunCF * CFrame.new(0.3, -0.42, 0) * CFrame.Angles(0, 0, math.rad(-8)), METAL, metal)
	gear("RifleSight", torso, Vector3.new(0.45, 0.14, 0.14), gunCF * CFrame.new(0.05, 0.24, 0), METAL, metal)
	gear("RifleBarrel", torso, Vector3.new(0.9, 0.12, 0.12), gunCF * CFrame.new(1.4, 0.04, 0), METAL, {
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
	})
	gear("RifleSling", torso, Vector3.new(0.12, 2.2, 0.06), CFrame.new(0.55, 0.05, -0.56) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(45, 42, 35))

	rig.Name = "FoundationGuard"
	template = rig
end

-- Pièce soudée à une partie du corps (après clonage du modèle de base)
local function attach(model, base, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

-- Personnalité visuelle d'un garde du hall : visage, casque, bande nominative, accessoires
function applyPersona(model, opts, skin)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local helmet = model:FindFirstChild("Helmet")
	local visor = model:FindFirstChild("Visor")

	local function moveWelded(part, cf, size)
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld.Enabled = false
		end
		if size then
			part.Size = size
		end
		part.CFrame = cf
		if weld then
			weld.Enabled = true
		end
	end
	if opts.helmet == "visorUp" and visor then
		-- casque remonté sur le crâne et visière relevée : les yeux restent visibles
		if helmet then
			moveWelded(helmet, head.CFrame * CFrame.new(0, 0.58, 0.1), Vector3.new(1.42, 0.74, 1.5))
		end
		moveWelded(visor, head.CFrame * CFrame.new(0, 0.95, -0.5) * CFrame.Angles(math.rad(-70), 0, 0))
	elseif opts.helmet == "none" then
		if helmet then
			helmet:Destroy()
		end
		if visor then
			visor:Destroy()
		end
		local hair = opts.hairColor or Color3.fromRGB(70, 66, 62)
		attach(model, head, "Hair", Vector3.new(1.16, 0.2, 1.2), CFrame.new(0, 0.56, 0.06), hair, Enum.Material.Fabric)
		attach(model, head, "HairBack", Vector3.new(1.16, 0.5, 0.18), CFrame.new(0, 0.28, 0.56), hair, Enum.Material.Fabric)
		-- béret sombre, penché sur le côté
		local beret = attach(
			model,
			head,
			"Beret",
			Vector3.new(0.35, 1.45, 1.4),
			CFrame.new(0.12, 0.72, 0.05) * CFrame.Angles(0, 0, math.rad(90 - 12)),
			Color3.fromRGB(32, 36, 48),
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
		beret.Size = Vector3.new(0.3, 1.45, 1.4)
	end

	if opts.face and head then
		local FaceKit = require(script.Parent:WaitForChild("FaceKit"))
		local spec = table.clone(opts.face)
		spec.skin = skin
		FaceKit.apply(head, spec)
	end

	-- bande nominative sur la poitrine
	if opts.nameTag and torso then
		local tape = attach(
			model,
			torso,
			"NameTape",
			Vector3.new(0.8, 0.22, 0.05),
			CFrame.new(-0.38, 0.42, -torso.Size.Z / 2 - 0.16),
			Color3.fromRGB(205, 200, 180),
			Enum.Material.Fabric
		)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 120
		gui.Parent = tape
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(25, 25, 25)
		label.Text = opts.nameTag
		label.Parent = gui
	end

	-- tasse de café à la main gauche
	if opts.mug then
		local hand = model:FindFirstChild("LeftHand")
		if hand then
			local mug = attach(
				model,
				hand,
				"Mug",
				Vector3.new(0.45, 0.36, 0.36),
				CFrame.new(0, -0.25, -0.2) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(235, 232, 225),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			)
			mug.Name = "Mug"
		end
	end
end

function FoundationGuard.new(opts)
	if not template then
		buildTemplate()
	end
	local model = template:Clone()
	model.Name = opts.name or "Garde"

	local self = setmetatable({}, FoundationGuard)
	self.model = model
	self.humanoid = model:FindFirstChildOfClass("Humanoid")
	self.root = model:FindFirstChild("HumanoidRootPart")

	-- Teint différent pour chaque garde
	local skin = opts.skinColor or SKINS[opts.skin or math.random(1, #SKINS)]
	model.Head.Color = skin
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.HeadColor3 = skin
	end
	applyPersona(model, opts, skin)
	if opts.scale then
		model:ScaleTo(opts.scale)
	end

	model:PivotTo(opts.cframe or CFrame.new())
	model.Parent = opts.parent or workspace
	self.root:SetNetworkOwner(nil) -- le serveur pilote le PNJ, pas un joueur proche

	-- Course / attente : pistes par défaut de Roblox
	local animator = self.humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.humanoid)
	local function load(id, priority)
		if not id then
			return nil
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		track.Priority = priority
		track.Looped = true
		return track
	end
	local runTrack = load(animIds.run, Enum.AnimationPriority.Movement)
	local walkTrack = load(animIds.walk, Enum.AnimationPriority.Movement)
	local idleTrack = load(animIds.idle, Enum.AnimationPriority.Idle)
	if idleTrack then
		idleTrack:Play()
	end
	if opts.walkSpeed then
		self.humanoid.WalkSpeed = opts.walkSpeed
	end
	-- Marche sous 10 studs/s (rondes), course au-delà (cinématique)
	self._running = self.humanoid.Running:Connect(function(speed)
		local moving = speed > 1
		local walking = moving and speed < 10 and walkTrack ~= nil
		local track = walking and walkTrack or runTrack
		local other = walking and runTrack or walkTrack
		if other and other.IsPlaying then
			other:Stop(0.2)
		end
		if not track then
			return
		end
		if moving then
			if not track.IsPlaying then
				track:Play(0.2)
			end
			track:AdjustSpeed(walking and speed / 8 or speed / 16)
		elseif track.IsPlaying then
			track:Stop(0.25)
		end
	end)
	return self
end

function FoundationGuard:destroy()
	if self._running then
		self._running:Disconnect()
	end
	self.model:Destroy()
end

return FoundationGuard
