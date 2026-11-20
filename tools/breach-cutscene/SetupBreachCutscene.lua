--[[
	SetupBreachCutscene — à coller une seule fois dans la barre de commande de Studio (Affichage > Barre de commande).

	Crée Workspace.DClassBlock.BreachCutscene, le décor de la cinématique de brèche :
	  - Spawns    : Guard1 à Guard4, position de départ des gardes dans l'armurerie (face avant = regard).
	  - Waypoints : WP01, WP02… points de passage, suivis dans l'ordre alphabétique.
	      Attributs :
	        Spread (nombre)   écart latéral de la formation à ce point (0 = file indienne)
	        Shot (texte)      plan de caméra déclenché quand le premier garde atteint ce point
	        Hold (booléen)    les gardes s'arrêtent ici et attendent l'ouverture de la porte
	        SingleFile (bool) les gardes passent un par un (après la porte de confinement)
	  - Shots     : repères de caméra. travellings <Nom>_Start → <Nom>_End (attribut Time sur _Start = durée en s) :
	      Armory (ouverture, dans l'armurerie), Wide (plongée devant l'armurerie, déclenché par WP03),
	      Door (gros plan sur la porte de la SALLE 001). Un Shot de point de passage sans repères = plan de dos.
	      La face avant (Front) de chaque part indique la direction de la caméra.

	Tout est déplaçable à la main dans Studio. Les parts sont semi-transparentes en édition ;
	le script BreachCutscene les rend invisibles en jeu.

	Relancer ce script remplace le dossier existant (les positions modifiées à la main sont perdues).
]]

local block = workspace:WaitForChild("DClassBlock")
local old = block:FindFirstChild("BreachCutscene")
if old then
	old:Destroy()
end

local root = Instance.new("Folder")
root.Name = "BreachCutscene"

local function marker(name, parent, cf, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.5
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function folder(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = root
	return f
end

-- Départ : alignés dans l'armurerie, face à la porte (vers -X)
local spawns = folder("Spawns")
for i, x in ipairs({ 56.5, 58.6, 60.7, 62.8 }) do
	local pos = Vector3.new(x, 3.5, 47.2)
	marker("Guard" .. i, spawns, CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0)), Vector3.new(1.5, 1, 1.5), Color3.fromRGB(60, 140, 255))
end

-- Trajet : armurerie → couloir du bloc D → briefing → sas → porte de la SALLE 001
local waypoints = folder("Waypoints")
local route = {
	{ 55.0, 47.6, Spread = 0 },
	{ 53.6, 50.4, Spread = 0 }, -- porte de l'armurerie
	{ 48.4, 50.4, Spread = 0, Shot = "Wide" }, -- sortie de l'armurerie : plan plongeant
	{ 48.6, 55.6, Spread = 0.9 },
	{ 57.5, 56.2, Spread = 1.2, Shot = "Follow" }, -- plan qui suit les gardes de dos
	{ 62.0, 59.0, Spread = 1.2 },
	{ 70.0, 59.0, Spread = 1.2 }, -- après la porte du couloir (HallDoor)
	{ 88.5, 59.0, Spread = 1.2 },
	{ 97.0, 59.0, Spread = 1.2 }, -- sas, après TestDoor
	{ 110.0, 59.0, Spread = 1.3, Hold = true, Shot = "Door" }, -- devant la porte de la SALLE 001
	{ 117.8, 60.4, Spread = 0, SingleFile = true }, -- seuil de la porte
	{ 122.0, 60.4, Spread = 0, SingleFile = true }, -- derrière la porte
}
for i, wp in ipairs(route) do
	local p = marker(string.format("WP%02d", i), waypoints, CFrame.new(wp[1], 1, wp[2]), Vector3.new(1, 0.4, 1), Color3.fromRGB(80, 255, 120))
	p:SetAttribute("Spread", wp.Spread)
	if wp.Shot then
		p:SetAttribute("Shot", wp.Shot)
	end
	if wp.Hold then
		p:SetAttribute("Hold", true)
	end
	if wp.SingleFile then
		p:SetAttribute("SingleFile", true)
	end
end

-- Caméra
local shots = folder("Shots")
local camColor = Color3.fromRGB(255, 200, 40)
local camSize = Vector3.new(0.8, 0.8, 1.6)
-- Plan d'ouverture, dans l'armurerie : les gardes de dos, la porte au fond
marker("Armory_Start", shots, CFrame.lookAt(Vector3.new(62.5, 8, 41.5), Vector3.new(52, 3, 50)), camSize, camColor):SetAttribute("Time", 4)
marker("Armory_End", shots, CFrame.lookAt(Vector3.new(61.5, 7, 43), Vector3.new(51.5, 3.5, 50.5)), camSize, camColor)
-- Plan plongeant (caméra de surveillance) dans la cage haute du couloir, devant l'armurerie
marker("Wide_Start", shots, CFrame.lookAt(Vector3.new(46, 20, 65), Vector3.new(48.5, 3, 52)), camSize, camColor):SetAttribute("Time", 3.5)
marker("Wide_End", shots, CFrame.lookAt(Vector3.new(46.5, 16, 63), Vector3.new(54, 3, 57)), camSize, camColor)
marker("Door_Start", shots, CFrame.lookAt(Vector3.new(113.2, 7.2, 62.3), Vector3.new(117, 4.2, 58.6)), camSize, camColor)
marker("Door_End", shots, CFrame.lookAt(Vector3.new(112.4, 5.6, 62.2), Vector3.new(117, 4.4, 59.2)), camSize, camColor)

root.Parent = block
print("BreachCutscene : décor créé dans", root:GetFullName())
