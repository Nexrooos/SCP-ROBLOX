--[[
	FaceKit (ModuleScript) — à placer dans ServerStorage. Côté serveur.

	Dessine un vrai visage sur la tête d'un PNJ (SurfaceGui sur la face avant), sans aucun asset :
	yeux (blanc, iris, pupille, paupière), sourcils, nez, bouche, et détails selon le personnage
	(cernes, yeux injectés de sang, barbe de trois jours, moustache, cicatrice, rides, sueur).
	Le visage par défaut de Roblox (décalque « face ») est retiré.

	Les éléments sont nommés pour être animés côté client (voir NPCFaces) :
	  Face.LeftEye / RightEye  -> Iris -> Pupil ; Lid (paupière, hauteur = fermeture)
	  Face.LeftBrow / RightBrow, Face.Mouth (Open = bouche ouverte quand il parle)
	Attributs posés sur le SurfaceGui « Face » : Crazy (regard instable), BlinkMin / BlinkMax (s).

	Utilisation :
		FaceKit.apply(model.Head, {
			skin = Color3.fromRGB(198, 140, 104),
			iris = Color3.fromRGB(70, 50, 30),
			eyeSize = 1,         -- 1 = normal, 1.3 = yeux exorbités
			pupil = 0.45,        -- taille de la pupille dans l'iris
			brows = { -8, 10 },  -- inclinaison des sourcils gauche / droit (degrés)
			browColor = Color3.fromRGB(40, 30, 25),
			mouth = "flat",      -- "flat", "frown", "smirk", "grin", "tense"
			lids = 0.15,         -- paupières mi-closes (0 = grands ouverts)
			bags = 0.5, bloodshot = false, stubble = 0.6, mustache = false, scar = false,
			wrinkles = false, sweat = false, crazy = false,
		})
]]

local FaceKit = {}

local function frame(parent, name, props)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function round(f, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r or 1, 0)
	c.Parent = f
end

local function darker(c, k)
	return c:Lerp(Color3.new(0, 0, 0), k)
end

local function eye(gui, name, cx, spec)
	local s = spec.eyeSize or 1
	local w, h = 0.16 * s, 0.1 * s
	local white = frame(gui, name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx, 0.4),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = spec.bloodshot and Color3.fromRGB(240, 214, 205) or Color3.fromRGB(245, 242, 236),
		ClipsDescendants = true,
		ZIndex = 2,
	})
	round(white)
	if spec.bloodshot then
		for k = 1, 4 do
			frame(white, "Vein", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(k % 2 == 0 and 0 or 0.7, 0.3 + k * 0.1),
				Size = UDim2.fromScale(0.3, 0.06),
				Rotation = (k % 2 == 0) and 15 or -20,
				BackgroundColor3 = Color3.fromRGB(200, 40, 40),
				BackgroundTransparency = 0.25,
				ZIndex = 3,
			})
		end
	end
	-- iris rond (taille relative à la hauteur de l'œil) ; un œil exorbité montre plus de blanc autour
	local iris = frame(white, "Iris", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(0.82 / math.max(1, s * 0.85), 0.82 / math.max(1, s * 0.85)),
		BackgroundColor3 = spec.iris or Color3.fromRGB(70, 50, 30),
		ZIndex = 4,
	})
	round(iris)
	local p = spec.pupil or 0.45
	local pupil = frame(iris, "Pupil", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(p, p),
		BackgroundColor3 = Color3.fromRGB(12, 10, 10),
		ZIndex = 5,
	})
	round(pupil)
	frame(iris, "Glint", {
		Position = UDim2.fromScale(0.58, 0.18),
		Size = UDim2.fromScale(0.22, 0.22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.2,
		ZIndex = 6,
	})
	-- paupière : descend depuis le haut (Size.Y = fermeture)
	local lid = frame(white, "Lid", {
		Size = UDim2.fromScale(1.1, spec.lids or 0.12),
		Position = UDim2.fromScale(-0.05, 0),
		BackgroundColor3 = darker(spec.skin, 0.08),
		ZIndex = 7,
	})
	frame(lid, "Lash", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.fromRGB(30, 22, 20),
		ZIndex = 8,
	})
	white:SetAttribute("BaseLid", spec.lids or 0.12)
	return white
end

function FaceKit.apply(head, spec)
	spec.skin = spec.skin or head.Color
	head.Color = spec.skin
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Decal") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	-- les têtes « dynamiques » ont le visage par défaut imprimé dans leur texture : on l'efface
	if head:IsA("MeshPart") then
		pcall(function()
			head.TextureID = ""
		end)
	end
	local old = head:FindFirstChild("Face")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 220
	gui.LightInfluence = 1
	gui.ClipsDescendants = true
	gui:SetAttribute("Crazy", spec.crazy == true)
	gui:SetAttribute("BlinkMin", spec.crazy and 0.6 or 2)
	gui:SetAttribute("BlinkMax", spec.crazy and 3 or 6)

	local skin = spec.skin
	local brow = spec.browColor or Color3.fromRGB(45, 32, 26)

	-- cernes
	if (spec.bags or 0) > 0 then
		for _, x in ipairs({ 0.3, 0.7 }) do
			local b = frame(gui, "Bag", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.465),
				Size = UDim2.fromScale(0.17, 0.045),
				BackgroundColor3 = darker(spec.skin, 0.45):Lerp(Color3.fromRGB(70, 40, 60), 0.3),
				BackgroundTransparency = 1 - 0.45 * spec.bags,
				ZIndex = 1,
			})
			round(b)
		end
	end
	eye(gui, "LeftEye", 0.3, spec)
	eye(gui, "RightEye", 0.7, spec)

	-- sourcils
	local angles = spec.brows or { 0, 0 }
	for i, x in ipairs({ 0.3, 0.7 }) do
		frame(gui, i == 1 and "LeftBrow" or "RightBrow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.27 - (spec.eyeSize or 1) * 0.02),
			Size = UDim2.fromScale(0.21, spec.browThick or 0.04),
			Rotation = (i == 1 and 1 or -1) * angles[i],
			BackgroundColor3 = brow,
			ZIndex = 3,
		})
	end

	-- nez : ombre et narines
	frame(gui, "NoseShade", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.09, 0.16),
		BackgroundColor3 = darker(skin, 0.18),
		BackgroundTransparency = 0.45,
		ZIndex = 1,
	})
	for _, x in ipairs({ 0.46, 0.54 }) do
		local n = frame(gui, "Nostril", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.62),
			Size = UDim2.fromScale(0.035, 0.025),
			BackgroundColor3 = darker(skin, 0.45),
			BackgroundTransparency = 0.2,
			ZIndex = 2,
		})
		round(n)
	end

	-- bouche
	local kind = spec.mouth or "flat"
	local mouth = frame(gui, "Mouth", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.76),
		Size = UDim2.fromScale(kind == "grin" and 0.42 or 0.28, 0.035),
		BackgroundColor3 = Color3.fromRGB(110, 50, 48),
		Rotation = kind == "smirk" and -7 or 0,
		ZIndex = 3,
	})
	round(mouth, 0.5)
	local open = frame(mouth, "Open", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0),
		BackgroundColor3 = Color3.fromRGB(40, 14, 16),
		ZIndex = 4,
	})
	round(open, 0.4)
	if kind == "frown" or kind == "tense" then
		for _, s in ipairs({ -1, 1 }) do
			frame(mouth, "Corner", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5 + s * 0.5, 0, 0.5, 0),
				Size = UDim2.fromScale(0.14, 1),
				Rotation = s * 35,
				BackgroundColor3 = mouth.BackgroundColor3,
				ZIndex = 3,
			})
		end
	end
	if kind == "grin" then
		-- sourire trop large, dents serrées, coins qui remontent de travers
		local teeth = frame(mouth, "Teeth", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 2.2),
			BackgroundColor3 = Color3.fromRGB(226, 214, 180),
			ZIndex = 5,
		})
		round(teeth, 0.3)
		for k = 1, 7 do
			frame(teeth, "Gap", {
				Position = UDim2.fromScale(k / 8, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = Color3.fromRGB(150, 130, 100),
				ZIndex = 6,
			})
		end
		for _, s in ipairs({ -1, 1 }) do
			frame(mouth, "Corner", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5 + s * 0.5, 0, 0.5, 0),
				Size = UDim2.fromScale(0.08, s < 0 and 3.2 or 2.2),
				Rotation = s * -30,
				BackgroundColor3 = mouth.BackgroundColor3,
				ZIndex = 4,
			})
		end
	end

	-- barbe de quelques jours
	if (spec.stubble or 0) > 0 then
		local rng = Random.new(#head:GetFullName())
		for _ = 1, math.floor(140 * spec.stubble) do
			local x, y = rng:NextNumber(0.12, 0.88), rng:NextNumber(0.63, 0.98)
			local fromCenter = math.abs(x - 0.5)
			if not (y < 0.7 and fromCenter < 0.2) then
				frame(gui, "Stubble", {
					Position = UDim2.fromScale(x, y),
					Size = UDim2.fromOffset(2, 2),
					BackgroundColor3 = spec.stubbleColor or Color3.fromRGB(50, 40, 34),
					BackgroundTransparency = rng:NextNumber(0.25, 0.6),
					ZIndex = 1,
				})
			end
		end
	end
	if spec.mustache then
		local m = frame(gui, "Mustache", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.69),
			Size = UDim2.fromScale(0.34, 0.06),
			BackgroundColor3 = spec.stubbleColor or brow,
			ZIndex = 3,
		})
		round(m, 0.5)
	end
	if spec.scar then
		frame(gui, "Scar", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.76, 0.42),
			Size = UDim2.fromScale(0.03, 0.34),
			Rotation = 18,
			BackgroundColor3 = Color3.fromRGB(196, 120, 120),
			BackgroundTransparency = 0.15,
			ZIndex = 8,
		})
	end
	if spec.wrinkles then
		for k = 1, 3 do
			frame(gui, "Wrinkle", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.08 + k * 0.045),
				Size = UDim2.fromScale(0.36 - k * 0.04, 0.012),
				BackgroundColor3 = darker(skin, 0.3),
				BackgroundTransparency = 0.35,
				ZIndex = 1,
			})
		end
	end
	if spec.sweat then
		for _, p in ipairs({ { 0.16, 0.2 }, { 0.83, 0.3 }, { 0.2, 0.58 } }) do
			local d = frame(gui, "Sweat", {
				Position = UDim2.fromScale(p[1], p[2]),
				Size = UDim2.fromScale(0.03, 0.05),
				BackgroundColor3 = Color3.fromRGB(220, 235, 245),
				BackgroundTransparency = 0.35,
				ZIndex = 8,
			})
			round(d)
		end
	end
	gui.Parent = head
	game:GetService("CollectionService"):AddTag(gui, "NPCFace")
	return gui
end

return FaceKit
