--[[
	CrazyDClassAnim (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.

	Animation procédurale de D-0451 « Le Fou » (voir ServerScriptService.CrazyDClass) :
	aucune animation importée, uniquement des Motor6D.Transform calculés à chaque image.
	  - posture voûtée : genoux fléchis, dos rond, épaules en avant, tête rentrée ;
	  - balancement d'avant en arrière, en continu ;
	  - tics nerveux aléatoires : la tête part de travers, les épaules sursautent, une main tremble ;
	  - regard (attribut Focus) : la tête se tourne d'un coup vers le joueur qui approche, puis le suit ;
	  - Rush / Grab : il se jette sur les barreaux, les mains agrippées, et les secoue ;
	  - Return : il retourne au fond de la cellule à petits pas traînants.
	Le calcul est coupé quand la caméra est loin (économie).
]]

while workspace:GetAttribute("ServerMode") == nil do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end
if workspace:GetAttribute("ServerMode") ~= "Hub" then
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MAX_DISTANCE = 140 -- au-delà, pas d'animation (studs)

local rad = math.rad
local function ang(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

local function findNpc()
	local cell = workspace:WaitForChild("Hub"):WaitForChild("Decor"):WaitForChild("CelluleIsolement")
	return cell:WaitForChild("D-0451", 60)
end

local npc = findNpc()
if not npc then
	return
end
local root = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")

local JOINTS = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftWrist", "RightWrist",
	"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle",
}
local motors = {}
for _, name in ipairs(JOINTS) do
	local m = npc:FindFirstChild(name, true)
	while not (m and m:IsA("Motor6D")) do
		task.wait(0.2)
		m = npc:FindFirstChild(name, true)
	end
	motors[name] = m
end

-- Pose courante (lissée) et tics superposés
local current = {}
for name in pairs(motors) do
	current[name] = CFrame.identity
end
local tics = {} -- { joint, offset, t0, dur }

local function addTic(joint, offset, dur)
	table.insert(tics, { joint = joint, offset = offset, t0 = os.clock(), dur = dur })
end

-- Tic nerveux au hasard
local function randomTic(intense)
	local k = math.random(1, 5)
	local s = intense and 1.6 or 1
	if k == 1 then
		addTic("Neck", ang(math.random(-15, 20) * s, math.random(-45, 45) * s, math.random(-30, 30) * s), 0.35)
	elseif k == 2 then
		addTic("LeftShoulder", ang(0, 0, -14 * s) * CFrame.new(0, 0.18, 0), 0.25)
		addTic("RightShoulder", ang(0, 0, 14 * s) * CFrame.new(0, 0.18, 0), 0.25)
		addTic("Neck", ang(-10, 0, 0), 0.25)
	elseif k == 3 then
		local side = math.random() < 0.5 and "Left" or "Right"
		addTic(side .. "Elbow", ang(35 * s, 0, 0), 0.3)
		addTic(side .. "Wrist", ang(math.random(-40, 40), 0, math.random(-30, 30)), 0.3)
	elseif k == 4 then
		addTic("Root", ang(-6 * s, math.random(-8, 8), 0), 0.22)
		addTic("Neck", ang(10, math.random(-60, 60), 0), 0.4)
	else
		addTic("Waist", ang(4, math.random(-18, 18) * s, math.random(-10, 10)), 0.5)
	end
end

-- Regard : direction de la tête du joueur suivi, dans le repère du PNJ
local focusUser, focusSince = 0, 0
local function updateFocus()
	local f = npc:GetAttribute("Focus") or 0
	if f ~= focusUser then
		focusUser = f
		focusSince = os.clock()
		if f ~= 0 then
			-- il vient de le remarquer : sursaut + tête qui part d'un coup
			addTic("Root", ang(6, 0, 0), 0.25)
			addTic("LeftShoulder", ang(0, 0, -10) * CFrame.new(0, 0.15, 0), 0.3)
			addTic("RightShoulder", ang(0, 0, 10) * CFrame.new(0, 0.15, 0), 0.3)
		end
	end
end
npc:GetAttributeChangedSignal("Focus"):Connect(updateFocus)
updateFocus()

local function focusAngles()
	if focusUser == 0 then
		return nil
	end
	local p = Players:GetPlayerByUserId(focusUser)
	local h = p and p.Character and p.Character:FindFirstChild("Head")
	if not h then
		return nil
	end
	local rel = root.CFrame:PointToObjectSpace(h.Position)
	local headRel = root.CFrame:PointToObjectSpace(head.Position)
	local d = rel - headRel
	local yaw = math.deg(math.atan2(-d.X, -d.Z))
	local pitch = math.deg(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)))
	return math.clamp(yaw, -80, 80), math.clamp(pitch, -35, 35)
end

---------------------------------------------------------------------------
-- Poses cibles
---------------------------------------------------------------------------
local function hunched(t, out)
	local rock = math.sin(t * 2.3)
	out.Root = CFrame.new(0, -0.45, 0.08 * rock) * ang(-10 + rock * 7, 0, math.sin(t * 1.1) * 2)
	out.Waist = ang(-24 + rock * 4, 0, 0)
	out.Neck = ang(14 - rock * 3, 0, 0)
	out.LeftShoulder = ang(14 + rock * 3, 0, 6)
	out.RightShoulder = ang(16 + rock * 3, 0, -6)
	out.LeftElbow = ang(32, 0, 0)
	out.RightElbow = ang(28, 0, 0)
	out.LeftWrist = ang(-12, 0, 8)
	out.RightWrist = ang(-12, 0, -8)
	out.LeftHip = ang(24, 0, -3)
	out.RightHip = ang(24, 0, 3)
	out.LeftKnee = ang(-36, 0, 0)
	out.RightKnee = ang(-36, 0, 0)
	out.LeftAnkle = ang(12, 0, 0)
	out.RightAnkle = ang(12, 0, 0)
end

local function grabbing(t, out, rushing)
	-- tremblement nerveux + secousses des barreaux
	local tremble = math.sin(t * 37) * 2 + math.sin(t * 23) * 1.5
	local shake = math.max(0, math.sin(t * 5.5)) ^ 6 * (math.sin(t * 0.7) > 0.3 and 1 or 0.25)
	out.Root = CFrame.new(0, -0.2, -0.15 - shake * 0.12) * ang(-14 - shake * 4, 0, tremble * 0.3)
	out.Waist = ang(-8, 0, 0)
	out.Neck = ang(4 + tremble * 0.5, 0, 6)
	out.LeftShoulder = ang(78 + tremble - shake * 8, 0, 14)
	out.RightShoulder = ang(84 - tremble - shake * 8, 0, -14)
	out.LeftElbow = ang(38 + shake * 10, 0, 0)
	out.RightElbow = ang(34 + shake * 10, 0, 0)
	out.LeftWrist = ang(-25, 0, -10)
	out.RightWrist = ang(-25, 0, 10)
	out.LeftHip = ang(16, 0, -2)
	out.RightHip = ang(10, 0, 2)
	out.LeftKnee = ang(-22, 0, 0)
	out.RightKnee = ang(-18, 0, 0)
	out.LeftAnkle = ang(6, 0, 0)
	out.RightAnkle = ang(8, 0, 0)
	if rushing then
		out.Root = out.Root * ang(-10, 0, 0)
	end
end

local function shuffling(t, out)
	hunched(t, out)
	local step = math.sin(t * 7)
	out.LeftHip = ang(24 + step * 16, 0, -3)
	out.RightHip = ang(24 - step * 16, 0, 3)
	out.LeftKnee = ang(-36 - math.max(0, step) * 20, 0, 0)
	out.RightKnee = ang(-36 - math.max(0, -step) * 20, 0, 0)
	out.Root = out.Root * ang(0, step * 4, step * 3)
end

---------------------------------------------------------------------------
-- Boucle d'animation
---------------------------------------------------------------------------
local target = {}
local nextTic = os.clock() + 1
local camera = workspace.CurrentCamera

RunService.RenderStepped:Connect(function(dt)
	if not npc.Parent then
		return
	end
	if (camera.CFrame.Position - root.Position).Magnitude > MAX_DISTANCE then
		return
	end
	local t = os.clock()
	local state = npc:GetAttribute("State") or "Idle"

	if state == "Grab" or state == "Rush" then
		grabbing(t, target, state == "Rush")
	elseif state == "Return" then
		shuffling(t, target)
	else
		hunched(t, target)
	end

	-- Regard : la tête (et un peu le buste) se tournent vers le joueur suivi
	local yaw, pitch = focusAngles()
	if yaw then
		target.Waist = target.Waist * ang(0, yaw * 0.3, 0)
		target.Neck = target.Neck * ang(pitch * 0.8, yaw * 0.7, (state == "Grab") and 10 or 0)
	end

	-- Tics nerveux (plus fréquents quand quelqu'un le regarde de près)
	if t >= nextTic then
		randomTic(focusUser ~= 0)
		local busyState = state == "Grab"
		nextTic = t + (busyState and math.random(4, 12) / 10 or (focusUser ~= 0 and math.random(6, 18) / 10 or math.random(10, 32) / 10))
	end

	-- Lissage : très rapide juste après avoir remarqué quelqu'un (tête qui part d'un coup)
	local speed = (state == "Rush") and 18 or ((t - focusSince < 0.18 and focusUser ~= 0) and 30 or 7)
	local a = math.min(1, dt * speed)
	for name, motor in pairs(motors) do
		local cf = target[name] or CFrame.identity
		current[name] = current[name]:Lerp(cf, a)
		local final = current[name]
		for i = #tics, 1, -1 do
			local tic = tics[i]
			if tic.joint == name then
				local u = (t - tic.t0) / tic.dur
				if u >= 1 then
					table.remove(tics, i)
				else
					-- attaque immédiate, retour plus lent
					local e = u < 0.15 and (u / 0.15) or (1 - (u - 0.15) / 0.85) ^ 2
					final = final * CFrame.identity:Lerp(tic.offset, e)
				end
			end
		end
		motor.Transform = final
	end
end)
