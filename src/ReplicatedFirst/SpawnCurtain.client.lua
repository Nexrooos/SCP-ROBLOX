--[[
	SpawnCurtain (LocalScript) — à placer dans ReplicatedFirst.

	Le jeu utilise le StreamingEnabled : sans précaution, le joueur voit ses premières images
	alors que le hall (et ses lampes) n'est pas encore arrivé, donc un décor noir ou à moitié éclairé.
	Ce script garde un écran noir jusqu'à ce que :
	  - le jeu soit chargé ;
	  - le décor du serveur soit là (Workspace.Hub en mode « Persistent », ou Workspace.DClassBlock) ;
	  - le personnage soit apparu et que ses alentours soient arrivés ;
	puis fait un fondu. La première image visible est donc déjà éclairée.
	Sécurité : le rideau s'ouvre de toute façon au bout de MAX_WAIT secondes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MAX_WAIT = 12 -- s
local SETTLE_TIME = 0.6 -- laisse le moteur calculer l'éclairage avant d'ouvrir (s)
local FADE_TIME = 0.8

local player = Players.LocalPlayer
local t0 = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "SpawnCurtain"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
local curtain = Instance.new("Frame")
curtain.Size = UDim2.fromScale(1, 1)
curtain.BackgroundColor3 = Color3.new(0, 0, 0)
curtain.BorderSizePixel = 0
curtain.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local function timeLeft()
	return math.max(0, MAX_WAIT - (os.clock() - t0))
end

local function waitFor(cond)
	while not cond() and timeLeft() > 0 do
		task.wait(0.05)
	end
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Décor du serveur : le hall de transit ou le bloc D
waitFor(function()
	return workspace:FindFirstChild("Hub") ~= nil or workspace:FindFirstChild("DClassBlock") ~= nil
end)

-- Personnage, puis quelques images pour que le streaming autour de lui et l'éclairage soient en place
waitFor(function()
	local char = player.Character
	return char ~= nil and char:FindFirstChild("HumanoidRootPart") ~= nil
end)
local settle = os.clock()
while os.clock() - settle < SETTLE_TIME and timeLeft() > 0 do
	RunService.RenderStepped:Wait()
end

local tween = TweenService:Create(curtain, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	BackgroundTransparency = 1,
})
tween.Completed:Once(function()
	gui:Destroy()
end)
tween:Play()
