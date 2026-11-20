--[[
	NPCFaces (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.

	Anime les visages dessinés par ServerStorage.FaceKit (SurfaceGui tagués « NPCFace ») :
	  - clignements d'yeux (intervalle selon BlinkMin / BlinkMax) ;
	  - regard qui se déplace (les iris glissent dans les yeux) ;
	  - visage « Crazy » : pupilles qui se dilatent et rétrécissent, yeux qui tressautent,
	    clignements nerveux en rafale ;
	  - quand le modèle a l'attribut Talking = true : la bouche s'ouvre et se ferme.
	Rien n'est calculé pour les visages éloignés de la caméra.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MAX_DISTANCE = 60

local faces = {}

local function setup(gui)
	local head = gui.Parent
	if not (head and head:IsA("BasePart")) then
		return
	end
	local function part(name)
		local e = gui:FindFirstChild(name)
		return e and {
			eye = e,
			iris = e:FindFirstChild("Iris"),
			pupil = e:FindFirstChild("Iris") and e.Iris:FindFirstChild("Pupil"),
			lid = e:FindFirstChild("Lid"),
			baseLid = e:GetAttribute("BaseLid") or 0.12,
		}
	end
	local mouth = gui:FindFirstChild("Mouth")
	faces[gui] = {
		head = head,
		model = head.Parent,
		eyes = { part("LeftEye"), part("RightEye") },
		mouthOpen = mouth and mouth:FindFirstChild("Open"),
		crazy = gui:GetAttribute("Crazy") == true,
		blinkMin = gui:GetAttribute("BlinkMin") or 2,
		blinkMax = gui:GetAttribute("BlinkMax") or 6,
		nextBlink = os.clock() + math.random() * 3,
		blinkUntil = 0,
		look = Vector2.zero,
		lookTarget = Vector2.zero,
		nextLook = 0,
		basePupil = nil,
	}
	local f = faces[gui]
	if f.eyes[1] and f.eyes[1].pupil then
		f.basePupil = f.eyes[1].pupil.Size.X.Scale
	end
end

for _, g in ipairs(CollectionService:GetTagged("NPCFace")) do
	setup(g)
end
CollectionService:GetInstanceAddedSignal("NPCFace"):Connect(setup)
CollectionService:GetInstanceRemovedSignal("NPCFace"):Connect(function(g)
	faces[g] = nil
end)

local camera = workspace.CurrentCamera

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for gui, f in pairs(faces) do
		if not gui.Parent then
			faces[gui] = nil
			continue
		end
		if (camera.CFrame.Position - f.head.Position).Magnitude > MAX_DISTANCE then
			continue
		end

		-- Clignements (en rafale pour le visage « fou »)
		if now >= f.nextBlink then
			f.blinkUntil = now + 0.12
			local burst = f.crazy and math.random() < 0.35
			f.nextBlink = now + (burst and 0.25 or (f.blinkMin + math.random() * (f.blinkMax - f.blinkMin)))
		end
		local blinking = now < f.blinkUntil

		-- Regard : petits déplacements des iris
		if now >= f.nextLook then
			local range = f.crazy and 0.32 or 0.18
			f.lookTarget = Vector2.new((math.random() * 2 - 1) * range, (math.random() * 2 - 1) * range * 0.5)
			f.nextLook = now + (f.crazy and (0.15 + math.random() * 0.5) or (0.8 + math.random() * 2.5))
		end
		local speed = f.crazy and 30 or 8
		f.look = f.look:Lerp(f.lookTarget, math.min(1, dt * speed))

		-- Pupilles du fou : dilatation instable
		local pupil = f.basePupil
		if f.crazy and pupil then
			pupil = pupil * (0.75 + 0.45 * (math.sin(now * 3.1) * 0.5 + 0.5)) + (math.random() < 0.02 and 0.15 or 0)
		end

		for _, e in ipairs(f.eyes) do
			if e and e.iris then
				local jitter = f.crazy and Vector2.new((math.random() - 0.5) * 0.04, (math.random() - 0.5) * 0.04) or Vector2.zero
				e.iris.Position = UDim2.fromScale(0.5 + f.look.X + jitter.X, 0.5 + f.look.Y + jitter.Y)
				if pupil and e.pupil then
					e.pupil.Size = UDim2.fromScale(pupil, pupil)
				end
				if e.lid then
					e.lid.Size = UDim2.fromScale(1.1, blinking and 1.05 or e.baseLid)
				end
			end
		end

		-- Bouche qui parle
		if f.mouthOpen then
			local talking = f.model and f.model:GetAttribute("Talking")
			local open = 0
			if talking then
				open = math.max(0, math.sin(now * 14) * 0.6 + math.sin(now * 23) * 0.4) * 3.2
			end
			f.mouthOpen.Size = UDim2.fromScale(0.8, open)
		end
	end
end)
