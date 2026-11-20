--[[
	BlinkAndWatch (LocalScript) — à placer dans StarterPlayer > StarterPlayerScripts.

	1. Jauge de clignement : tes yeux se ferment tout seuls quand elle est vide.
	   Touche [B] = cligner volontairement (pour choisir le bon moment en coop).
	2. Détection : dit au serveur si tu vois SCP-173 (à l'écran ET pas caché derrière un mur).
]]

-- Ne tourne que sur un serveur de partie, pas dans le hall de transit (voir HubServer).
while workspace:GetAttribute("ServerMode") ~= "Match" do
	workspace:GetAttributeChangedSignal("ServerMode"):Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remote = ReplicatedStorage:WaitForChild("SCP173_Watching")

local BLINK_INTERVAL = 9 -- secondes avant un clignement forcé
local BLINK_DURATION = 0.3 -- yeux fermés (s)
local MAX_SIGHT = 120 -- distance de vue max (studs)
local CHECK_EVERY = 0.1 -- fréquence de détection (s)
local BLINK_KEY = Enum.KeyCode.B

---------------------------------------------------------------- Interface
local gui = Instance.new("ScreenGui")
gui.Name = "BlinkGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local eyelids = Instance.new("Frame")
eyelids.Size = UDim2.fromScale(1, 1)
eyelids.BackgroundColor3 = Color3.new(0, 0, 0)
eyelids.BackgroundTransparency = 1
eyelids.BorderSizePixel = 0
eyelids.ZIndex = 10
eyelids.Parent = gui

local barBg = Instance.new("Frame")
barBg.AnchorPoint = Vector2.new(0.5, 1)
barBg.Position = UDim2.new(0.5, 0, 1, -24)
barBg.Size = UDim2.fromOffset(220, 10)
barBg.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
barBg.BackgroundTransparency = 0.3
barBg.BorderSizePixel = 0
barBg.Parent = gui

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 0, -2)
label.Size = UDim2.fromOffset(220, 16)
label.BackgroundTransparency = 1
label.Font = Enum.Font.Code
label.TextSize = 13
label.TextColor3 = Color3.fromRGB(200, 200, 200)
label.Text = "CLIGNEMENT  [B]"
label.Parent = barBg

---------------------------------------------------------------- Clignement
local meter = BLINK_INTERVAL
local blinking = false

local function blink()
	if blinking then
		return
	end
	blinking = true
	TweenService:Create(eyelids, TweenInfo.new(0.06), { BackgroundTransparency = 0 }):Play()
	task.wait(BLINK_DURATION)
	TweenService:Create(eyelids, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
	meter = BLINK_INTERVAL
	blinking = false
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == BLINK_KEY then
		task.spawn(blink)
	end
end)

---------------------------------------------------------------- Détection
local CHECK_POINTS = {
	Vector3.new(0, 1.5, 0), -- jambes
	Vector3.new(0, 5.5, 0), -- torse
	Vector3.new(0, 8.4, 0), -- tête
}

local function canSee(model)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if blinking or not hum or hum.Health <= 0 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local origin = camera.CFrame.Position
	local pivot = model:GetPivot()
	for _, offset in ipairs(CHECK_POINTS) do
		local point = pivot:PointToWorldSpace(offset)
		local _, onScreen = camera:WorldToViewportPoint(point)
		local dir = point - origin
		if onScreen and dir.Magnitude <= MAX_SIGHT then
			local hit = workspace:Raycast(origin, dir, params)
			if not hit or hit.Instance:IsDescendantOf(model) then
				return true
			end
		end
	end
	return false
end

local lastSent = {} -- [model] = bool
local lastFullSync = 0
local acc = 0

RunService.Heartbeat:Connect(function(dt)
	-- jauge
	if not blinking then
		meter -= dt
		if meter <= 0 then
			task.spawn(blink)
		end
	end
	barFill.Size = UDim2.fromScale(math.clamp(meter / BLINK_INTERVAL, 0, 1), 1)
	barFill.BackgroundColor3 = meter < 2 and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(230, 230, 230)

	-- détection
	acc += dt
	if acc < CHECK_EVERY then
		return
	end
	acc = 0

	local now = os.clock()
	local forceSync = now - lastFullSync > 1
	if forceSync then
		lastFullSync = now
	end

	for _, model in ipairs(CollectionService:GetTagged("SCP173")) do
		local seen = canSee(model)
		if forceSync or lastSent[model] ~= seen then
			lastSent[model] = seen
			remote:FireServer(model, seen)
		end
	end
end)
