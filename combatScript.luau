-- LOCAL SCRIPT 

local rps = game:GetService("ReplicatedStorage")

local punchRad = rps.punchRad
local PunchTool = script.Parent
local PunchRadius
local HitPlayer = rps.HitPlayer

local Player = game.Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()
local hum = Char:WaitForChild("Humanoid")
local HumRootPart = Char:WaitForChild("HumanoidRootPart")

local punchIde = Instance.new("Animation")
punchIde.AnimationId = "rbxassetid://16681874657"
local punchIdeTrack = hum:WaitForChild("Animator"):LoadAnimation(punchIde)

local punchAnim  = Instance.new("Animation")
punchAnim.AnimationId = "rbxassetid://16683775731"
local punchAnimTrack = hum:WaitForChild("Animator"):LoadAnimation(punchAnim)

local db = false

PunchTool.Equipped:Connect(function()
	PunchRadius = punchRad:Clone()
	PunchRadius.Parent = workspace
	PunchTool.Name = "PunchRadius"
	PunchRadius:PivotTo(HumRootPart.CFrame + HumRootPart.CFrame.LookVector * 2)
	
	local WeldCon = Instance.new("WeldConstraint")

	WeldCon.Parent = PunchRadius
	WeldCon.Part0 = HumRootPart
	WeldCon.Part1 = PunchRadius
	
	punchIdeTrack:Play()
end)

PunchTool.Activated:Connect(function()
	if not db then
		db = true
		punchAnimTrack:Play()

		local collisionItems = workspace:GetPartsInPart(PunchRadius)

		for i, v in pairs(collisionItems) do
			if v.Parent:FindFirstChild("Humanoid") and v.Parent.Name ~= Player.Name then
				HitPlayer:FireServer(v.Parent)
				break
			end
		end
		wait(1)
		db = false
	end
end)

PunchTool.Unequipped:Connect(function()
	PunchRadius:Destroy()
	punchIdeTrack:Stop()
end)



-- SERVER SCRIPT

local rps = game:GetService("ReplicatedStorage")

local Player
local Char
local hitplayer = rps.HitPlayer

game.Players.PlayerAdded:Connect(function(player)
	Player = player
	Char = Player.Character or Player.CharacterAdded:Wait()
end)

hitplayer.OnServerEvent:Connect(function(player, char)
	local hum = char:FindFirstChild("Humanoid")
	hum.Health -= 5
end)

