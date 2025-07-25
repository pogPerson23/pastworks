local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

-- modules

local securityCameraModule = require(replicatedStorage.securityCameraModule)

-- variables

local camerasFolder = workspace.camerasFolder

local player = players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local playerGui = player.PlayerGui

local tablet = script.Parent

-- events

local tabletEquippedEvent = replicatedStorage.tabletEquippedEvent
local tabletUnequippedEvent = replicatedStorage.tabletUnequippedEvent

-- gui objects

local tabletGui = playerGui.tabletGui
local mainTabletFrame = tabletGui.mainTabletFrame

--app buttons
local securityCamerasButton = mainTabletFrame.securityCamerasButton

-- security app
local securityTabletFrame = tabletGui.securityTabletFrame
local moveForwardsButton = securityTabletFrame.moveForwardsButton
local moveBackwardsButton = securityTabletFrame.moveBackButton
local securityFrameCloseButton = securityTabletFrame.closeButton
local currentCameraLabel = securityTabletFrame.currentCameraLabel
local currentCameraIndex = 1

local appsMeta = {} -- apps metatable
appsMeta.__index = appsMeta

local apps = {}

function appsMeta:Open() -- app open function
	self.frame.Visible = true
end

function appsMeta:Close() -- app close function
	self.frame.Visible = false
end

function createApp(appName: string, appFrame: Frame) -- create new app
	local app = {
		name = appName, frame = appFrame
	}
	setmetatable(app, appsMeta)
	apps[appName] = app -- add app metatable to apps table
end

function openApp(appName) -- open an app
	for _, app in apps do -- close all other apps
		app:Close()
	end

	local appToOpen = apps[appName]
	if appToOpen then -- ensure the app thats trying to be accessed exists
		mainTabletFrame.Visible = false
		appToOpen:Open() -- open the app
	else
		warn("App '" .. appName .. "' not found!")
	end
end

function closeApp()
	for _, app in apps do 
		app:Close()
	end
	mainTabletFrame.Visible = true
end

function tabletEquipped() 
	tabletEquippedEvent:FireServer(character)
	animateCameraOnEquip()
	if character:FindFirstChild("tablet") then
		mainTabletFrame.Visible = true
		loadTabletScreen()
	end
end

function loadTabletScreen()
	local loadingFrame = tabletGui:FindFirstChild("loadingFrame")
	
	local tween = tweenService:Create(loadingFrame, 
		TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	)
	task.wait(0.2)
	tween:Play()
	tween.Completed:Wait()
	loadingFrame:Destroy()
end

function animateCameraOnEquip()
	-- camera variables
	local camera = workspace.CurrentCamera
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then 
		warn("HumanoidRootPart not found for " .. player.Name)
		return
	end

	local lookVector = humanoidRootPart.CFrame.LookVector
	local cameraStartPosition = humanoidRootPart.Position - lookVector * 1.3 + Vector3.new(0, 4, 0)
	local cameraEndPosition = humanoidRootPart.Position + lookVector * 1.5 + Vector3.new(0, 0.5, 0) 

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(cameraStartPosition, humanoidRootPart.Position)
	
	local tiltAngle = math.rad(-30)

	local tween = tweenService:Create(camera, 
		TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = CFrame.lookAt(cameraEndPosition, cameraEndPosition + lookVector) * CFrame.Angles(tiltAngle, 0, 0)}
	)
	
	-- screen fade variables
	local loadingFrame = Instance.new("Frame")
	loadingFrame.Parent = tabletGui
	loadingFrame.ZIndex = 10
	loadingFrame.Name = "loadingFrame"
	loadingFrame.Size = UDim2.new(1, 0, 1, 0)
	loadingFrame.BackgroundColor = BrickColor.new("Really black")
	loadingFrame.BackgroundTransparency = 1
	
	local loadingTween = tweenService:Create(loadingFrame, 
		TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0}
	)
	
	tween:Play()
	loadingTween:Play()
	character.ChildRemoved:Connect(function(child)
		if child.Name == "tablet" then
			tween:Cancel()
		end
	end)
	tween.Completed:Wait()
end

function tabletUnequipped()
	mainTabletFrame.Visible = false	
	
	for _, app in apps do -- close all other apps
		app:Close()
	end
	
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	print("Switched back to custom!")
	
	if tabletGui:FindFirstChild("loadingFrame") then
		tabletGui:FindFirstChild("loadingFrame"):Destroy()
	end
	
	tabletUnequippedEvent:FireServer(character)
end

createApp("securityCameras", securityTabletFrame) -- create security app

-- security app functions

function navigateCameras(direction)
	local newCameraIndex = securityCameraModule.changeCamera(direction, camerasFolder:GetChildren(), currentCameraIndex)
	currentCameraIndex = newCameraIndex
	securityCameraModule.viewCamera(camerasFolder["cam"..currentCameraIndex], currentCameraLabel, currentCameraIndex)
end

-- security app events

moveForwardsButton.MouseButton1Click:Connect(function()
	navigateCameras(1)
end)

moveBackwardsButton.MouseButton1Click:Connect(function()
	navigateCameras(-1)
end)

securityFrameCloseButton.MouseButton1Click:Connect(function()
	closeApp()
end)

-- connect tablet events

tablet.Equipped:Connect(tabletEquipped)
tablet.Unequipped:Connect(tabletUnequipped)

-- app events

securityCamerasButton.MouseButton1Click:Connect(function()
	openApp("securityCameras")
	securityCameraModule.viewCamera(camerasFolder["cam"..currentCameraIndex], currentCameraLabel, currentCameraIndex)
end)
