--[[
	SCP173Model (ModuleScript) — à placer dans ServerStorage, nommé "SCP173Model".

	v2 (recommandé) : importe assets/SCP173.obj dans Studio (onglet Accueil > « Importer 3D »),
	renomme le Model obtenu "SCP173Mesh" et range-le dans ServerStorage.
	Le script l'utilise automatiquement (couleurs + taille appliquées).

	v1 (secours) : si "SCP173Mesh" n'existe pas, construit SCP-173 en pièces Roblox.
	Design ORIGINAL : statue humanoïde en béton, armature en fer qui dépasse,
	tête disproportionnée, visage peint en rouge et traînées de peinture verte.
	(On ne copie pas la sculpture d'origine, qui n'est pas sous licence libre.)

	Utilisation :
		local SCP173Model = require(game.ServerStorage.SCP173Model)
		local scp = SCP173Model.build(CFrame.new(0, 0, -30))  -- CFrame = position des pieds au sol
		scp.Parent = workspace

	Le modèle regarde vers -Z (LookVector), comme tous les modèles Roblox.
	Hauteur totale : ~8.5 studs (≈ 2,4 m).
]]

local CollectionService = game:GetService("CollectionService")

local SCP173Model = {}

local CONCRETE = Color3.fromRGB(176, 170, 156)
local CONCRETE_DARK = Color3.fromRGB(128, 122, 110)
local RUST = Color3.fromRGB(110, 62, 38)
local PAINT_RED = Color3.fromRGB(140, 18, 18)
local PAINT_GREEN = Color3.fromRGB(52, 120, 48)
local CRACK = Color3.fromRGB(60, 56, 50)

local function makePart(model, root, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false -- évite de gêner le pathfinding ; le contact tue de toute façon
	p.CanQuery = true -- nécessaire pour que les joueurs le "voient" (raycast)
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * offset
	p.Parent = model
	return p
end

-- Couleurs / matériaux appliqués au modèle 3D importé (assets/SCP173.obj)
local MESH_LOOK = {
	Body = { color = Color3.fromRGB(196, 181, 145), material = Enum.Material.Concrete },
	PaintBlack = { color = Color3.fromRGB(13, 10, 9), material = Enum.Material.SmoothPlastic },
	PaintRed = { color = Color3.fromRGB(122, 15, 11), material = Enum.Material.SmoothPlastic },
	PaintGreen = { color = Color3.fromRGB(61, 100, 36), material = Enum.Material.SmoothPlastic },
	Rebar = { color = RUST, material = Enum.Material.CorrodedMetal },
}
local TARGET_HEIGHT = 9.9 -- studs

-- Version v2 : utilise le mesh importé (ServerStorage > SCP173Mesh) s'il existe
local function buildFromMesh(template, feetCFrame)
	local model = template:Clone()
	model.Name = "SCP-173"

	-- Mise à l'échelle automatique, au cas où l'import a changé la taille
	local _, size = model:GetBoundingBox()
	if math.abs(size.Y - TARGET_HEIGHT) > 0.3 then
		model:ScaleTo(model:GetScale() * TARGET_HEIGHT / size.Y)
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = true
			for key, look in pairs(MESH_LOOK) do
				if string.find(d.Name, key, 1, true) then
					d.Color = look.color
					d.Material = look.material
					if d:IsA("MeshPart") then
						d.TextureID = ""
					end
				end
			end
		end
	end

	-- Racine au sol, au centre, orientée comme le mesh (face vers -Z)
	local cf, box = model:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 0.2, 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - box.Y / 2, cf.Position.Z)
	root.Parent = model
	model.PrimaryPart = root

	local soundAnchor = Instance.new("Attachment")
	soundAnchor.Name = "SoundAnchor"
	soundAnchor.Position = Vector3.new(0, 1, 0)
	soundAnchor.Parent = root

	model:PivotTo(feetCFrame)
	CollectionService:AddTag(model, "SCP173")
	return model
end

function SCP173Model.build(feetCFrame)
	feetCFrame = feetCFrame or CFrame.new()

	local template = game:GetService("ServerStorage"):FindFirstChild("SCP173Mesh")
	if template then
		return buildFromMesh(template, feetCFrame)
	end
	-- Sinon : version v1 en blocs (ci-dessous)

	local model = Instance.new("Model")
	model.Name = "SCP-173"

	-- Racine invisible au niveau du sol : c'est le pivot qu'on déplace.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 0.2, 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CFrame = feetCFrame
	root.Parent = model
	model.PrimaryPart = root

	local function add(name, size, offset, color, material, shape)
		return makePart(model, root, name, size, offset, color, material, shape)
	end
	local rad = math.rad

	-- Socle de béton cassé (il a été "coulé" sur place)
	add("Base", Vector3.new(2.6, 0.4, 2), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, rad(7), 0), CONCRETE_DARK)

	-- Jambes (épaisses, légèrement écartées)
	add("LegL", Vector3.new(1, 3.4, 1), CFrame.new(-0.6, 2.1, 0) * CFrame.Angles(0, 0, rad(-3)), CONCRETE)
	add("LegR", Vector3.new(1, 3.4, 1), CFrame.new(0.6, 2.1, 0) * CFrame.Angles(0, 0, rad(3)), CONCRETE)

	-- Bassin + torse (penché en avant, menaçant)
	add("Pelvis", Vector3.new(2.3, 1, 1.3), CFrame.new(0, 4.1, 0), CONCRETE)
	add("Torso", Vector3.new(2.5, 2.8, 1.5), CFrame.new(0, 5.9, -0.15) * CFrame.Angles(rad(-8), 0, 0), CONCRETE)

	-- Bras trop longs qui pendent jusqu'aux genoux
	add("ArmL", Vector3.new(0.6, 3.8, 0.6), CFrame.new(-1.6, 5.1, -0.1) * CFrame.Angles(rad(-6), 0, rad(-6)), CONCRETE)
	add("ArmR", Vector3.new(0.6, 3.8, 0.6), CFrame.new(1.6, 5.1, -0.1) * CFrame.Angles(rad(-6), 0, rad(6)), CONCRETE)
	add("HandL", Vector3.new(0.75, 0.7, 0.75), CFrame.new(-1.8, 3, -0.3), CONCRETE_DARK)
	add("HandR", Vector3.new(0.75, 0.7, 0.75), CFrame.new(1.8, 3, -0.3), CONCRETE_DARK)

	-- Cou + grosse tête ronde
	add("Neck", Vector3.new(0.8, 0.7, 0.8), CFrame.new(0, 7.5, -0.25), CONCRETE)
	local headOffset = CFrame.new(0, 8.4, -0.35)
	add("Head", Vector3.new(2.2, 2.2, 2.2), headOffset, CONCRETE, Enum.Material.Concrete, Enum.PartType.Ball)

	-- Visage peint (rouge, irrégulier). Le visage est côté -Z.
	add("EyeL", Vector3.new(0.45, 0.28, 0.12), headOffset * CFrame.new(-0.45, 0.2, -0.97) * CFrame.Angles(0, 0, rad(12)), PAINT_RED, Enum.Material.SmoothPlastic)
	add("EyeR", Vector3.new(0.45, 0.22, 0.12), headOffset * CFrame.new(0.45, 0.15, -0.97) * CFrame.Angles(0, 0, rad(-8)), PAINT_RED, Enum.Material.SmoothPlastic)
	add("Mouth", Vector3.new(0.9, 0.18, 0.16), headOffset * CFrame.new(0.05, -0.45, -0.94) * CFrame.Angles(0, 0, rad(-4)), PAINT_RED, Enum.Material.SmoothPlastic)
	add("DripL", Vector3.new(0.08, 0.5, 0.12), headOffset * CFrame.new(-0.42, -0.1, -0.98), PAINT_RED, Enum.Material.SmoothPlastic)
	add("DripMouth", Vector3.new(0.08, 0.45, 0.14), headOffset * CFrame.new(0.25, -0.7, -0.86), PAINT_RED, Enum.Material.SmoothPlastic)

	-- Traînées de peinture verte (aérosol) sur le torse
	add("SprayA", Vector3.new(1.6, 0.18, 0.08), CFrame.new(0.1, 6.4, -0.98) * CFrame.Angles(rad(-8), 0, rad(18)), PAINT_GREEN, Enum.Material.SmoothPlastic)
	add("SprayB", Vector3.new(1.1, 0.14, 0.08), CFrame.new(-0.3, 5.7, -0.9) * CFrame.Angles(rad(-8), 0, rad(-25)), PAINT_GREEN, Enum.Material.SmoothPlastic)

	-- Fissures (lignes sombres)
	add("CrackTorso", Vector3.new(0.06, 1.4, 0.06), CFrame.new(0.7, 5.6, -0.92) * CFrame.Angles(0, 0, rad(20)), CRACK, Enum.Material.SmoothPlastic)
	add("CrackLeg", Vector3.new(0.06, 1.2, 0.06), CFrame.new(0.95, 2.4, -0.5) * CFrame.Angles(0, 0, rad(-15)), CRACK, Enum.Material.SmoothPlastic)

	-- Armature en fer rouillé qui sort du dos et de l'épaule
	add("RebarA", Vector3.new(2.2, 0.15, 0.15), CFrame.new(0.4, 6.8, 0.9) * CFrame.Angles(0, rad(70), rad(35)), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	add("RebarB", Vector3.new(1.6, 0.15, 0.15), CFrame.new(-0.6, 6.1, 0.95) * CFrame.Angles(0, rad(110), rad(-20)), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	add("RebarC", Vector3.new(1.3, 0.12, 0.12), CFrame.new(1.5, 7.2, 0) * CFrame.Angles(0, 0, rad(50)), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)

	-- Point d'attache pour les sons (raclement / craquement)
	local soundAnchor = Instance.new("Attachment")
	soundAnchor.Name = "SoundAnchor"
	soundAnchor.Position = Vector3.new(0, 1, 0)
	soundAnchor.Parent = root

	model:PivotTo(feetCFrame)
	CollectionService:AddTag(model, "SCP173")
	return model
end

return SCP173Model
