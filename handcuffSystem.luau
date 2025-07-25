-- local script 

local rps = game:GetService("ReplicatedStorage")
local rs = game:GetService("RunService")

local handcuffs = script.Parent

local Player = game.Players.LocalPlayer
local Char = Player.Character or Player.CharacterAdded:Wait()
local hum = Char:WaitForChild("Humanoid")
local hrp = Char:WaitForChild("HumanoidRootPart")
local Mouse = Player:GetMouse()
Mouse.TargetFilter = handcuffs

local PlayerGui = Player.PlayerGui
local CuffGui = PlayerGui.CuffGui
local CuffFrame = CuffGui.CuffFrame
local ReleaseButton = CuffFrame.ReleaseButton
local DetainButton = CuffFrame.DetainButton
local PinButton = CuffFrame.PinButton
local SearchButton = CuffFrame.SearchButton

local CuffDistance = 10

local detained = false
local detainedUser = nil
local arrested = false

local weld

local arrestreqre = rps.ArrestRequestRE
local TurnOffBackpackRE = rps.TurnOffBackpackRE
local TurnOnBackpackRE = rps.TurnOnBackpackRE
local CuffsUnequipRE = rps.CuffsUnequipRE
local TurnOnCuffGuiRE = rps.TurnOnCuffGui
local DetainRE = rps.DetainRE


handcuffs.Activated:Connect(function()
	local target = Mouse.Target
	
	if target.Parent:FindFirstChild("Humanoid") and target.Parent:FindFirstChild("HumanoidRootPart") then
		if target.Parent:FindFirstChild("Humanoid"):FindFirstChild("Animator") then
			if (Char:FindFirstChild("HumanoidRootPart").Position - target.Position).Magnitude <= CuffDistance then
				arrestreqre:FireServer(target.Parent, hrp)
			end
		end
	end
end)

handcuffs.Unequipped:Connect(function()
	if CuffFrame.Visible == true then
		CuffFrame.Visible = false
		CuffsUnequipRE:FireServer()
	else
		CuffsUnequipRE:FireServer()
	end
end)

ReleaseButton.MouseButton1Click:Connect(function()
	if CuffFrame.Visible == true then
		CuffFrame.Visible = false
		CuffsUnequipRE:FireServer()
	else
		CuffsUnequipRE:FireServer()
	end
end)

TurnOffBackpackRE.OnClientEvent:Connect(function(player)
	Player.Character:FindFirstChild("Humanoid"):UnequipTools()
	game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

TurnOnBackpackRE.OnClientEvent:Connect(function()
	game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
end)

TurnOnCuffGuiRE.OnClientEvent:Connect(function()
	CuffFrame.Visible = true
end)

DetainButton.MouseButton1Click:Connect(function()
	DetainRE:FireServer()
end)


-- server script

local rps = game:GetService("ReplicatedStorage")

local ArrestAnim = Instance.new("Animation")
ArrestAnim.AnimationId = "rbxassetid://16700779741"
local ArrestAnimTrack = {}

local arrestreqre = rps.ArrestRequestRE
local TurnOffBackpackRE = rps.TurnOffBackpackRE
local TurnOnBackpackRE = rps.TurnOnBackpackRE
local CuffsUnequipRE = rps.CuffsUnequipRE
local TurnOnCuffGuiRE = rps.TurnOnCuffGui
local DetainRE = rps.DetainRE

local arresting = {}
local detained = {}
local weld = {}
local arrestedHum = {}

function checkTableKey(Key, dict)
	for key, val in pairs(dict) do
		if Key == key then
			return true
		end
		return false
	end
end

arrestreqre.OnServerEvent:Connect(function(player, arrestee, MyHrp)
	if not checkTableKey(player.Name, arresting) then
		
		local function SetProperties()
			print(2)
			arrestedHum[arrestee.Name] = arrestee:FindFirstChild("Humanoid")
			arrestedHum[arrestee.Name].WalkSpeed = 0
			arrestedHum[arrestee.Name].JumpPower = 0
			for i, v in arrestee:GetChildren() do
				if v:IsA("Part") then
					v.Massless = true
				end
			end

			arrestee:FindFirstChild("HumanoidRootPart"):PivotTo(MyHrp.CFrame)

			weld[player.Name] = Instance.new("Weld")
			weld[player.Name].Parent = MyHrp
			weld[player.Name].Part1 = MyHrp
			weld[player.Name].Part0 = arrestee:FindFirstChild("HumanoidRootPart")
			weld[player.Name].C0 = CFrame.new(-1.5, 0, 3)
			arrestedHum[arrestee.Name].PlatformStand = true

			TurnOnCuffGuiRE:FireClient(player)
			TurnOffBackpackRE:FireClient(game.Players:GetPlayerFromCharacter(arrestee))
		end

		if not detained[arrestee.Name] then
			print(1)
			arresting[player.Name] = true
			ArrestAnimTrack[player.Name] = arrestee:FindFirstChild("Humanoid"):FindFirstChild("Animator"):LoadAnimation(ArrestAnim) 
			ArrestAnimTrack[player.Name]:Play()
			SetProperties()
		else
			arresting[player.Name] = true
			SetProperties()
		end

		CuffsUnequipRE.OnServerEvent:Connect(function(player)
			if checkTableKey(player.Name, arresting) then
				ArrestAnimTrack[player.Name]:Stop()
				ArrestAnimTrack[player.Name] = nil
				arrestedHum[arrestee.Name].PlatformStand = false
				arrestedHum[arrestee.Name].WalkSpeed = 16
				arrestedHum[arrestee.Name].JumpPower = 50
				for i, v in arrestee:GetChildren() do
					if v:IsA("Part") then
						v.Massless = false
					end
				end
				arrestedHum[arrestee.Name] = nil
				weld[player.Name]:Destroy()
				weld[player.Name] = nil
				arresting[player.Name] = nil
				TurnOnBackpackRE:FireClient(game.Players:GetPlayerFromCharacter(arrestee))
			end
		end)
		
		DetainRE.OnServerEvent:Connect(function(player)
			weld[player.Name]:Destroy()
			arresting[player.Name] = nil
			local weldedPlayerHRP = weld[player.Name].Part0 
			weld[player.Name] = nil
			weldedPlayerHRP.Parent:FindFirstChild("Humanoid").WalkSpeed = 5
			weldedPlayerHRP.Parent:FindFirstChild("Humanoid").PlatformStand = false
			weldedPlayerHRP.Parent:FindFirstChild("Humanoid").JumpPower = 50
			detained[weldedPlayerHRP.Parent] = true
		end)
	end
end)

