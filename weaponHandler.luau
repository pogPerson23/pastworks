-- ===== SERVICES =====
local rps = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local uis = game:GetService("UserInputService")

-- ===== PLAYER SETUP =====
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera

-- ===== WEAPON SYSTEM =====
local viewModelsFolder = rps:WaitForChild("viewModels")
local currentVM = nil

-- ===== PLAYER STATES =====
local idle = true
local walking = false
local shooting = false
local fullAutoShooting = false
local inAir = false
local canShoot = true
local canReload = true
local reloading = false

-- ===== ANIMATIONS =====
local loadedAnims = {
	shoot = nil,
	reload = nil
}

-- ===== INVENTORY =====
local inventory = {
	primary = "Rifle",
	secondary = "Pistol",
	knife = "Knife",
	module = nil
}

-- ===== VISUAL SETTINGS =====
local settings = {
	swayAmount = 0.1,
	mouseSensitivity = 0.3
}

-- ===== CAMERA MOVEMENT =====
local swayCFrame = CFrame.new()
local lastCameraCFrame = camera.CFrame
local baseSway = CFrame.new()
local currentSpreadAngle

-- ===== CONNECTIONS =====
local connections = {}

-- ===== UTILITY FUNCTIONS =====
local function updateMouseSensitivity()
	if currentVM then
		uis.MouseDeltaSensitivity = settings.mouseSensitivity
	else
		uis.MouseDeltaSensitivity = 1.0
	end
end

local function isBusy()
	return not canShoot or reloading or not currentVM
end

local function cancelReload()
	if loadedAnims.reload and loadedAnims.reload.IsPlaying then
		loadedAnims.reload:Stop()
	end
	reloading = false
	canReload = true
	canShoot = true
end

local function stopFullAutoShooting()
	fullAutoShooting = false
	if connections.fullAutoLoop then
		connections.fullAutoLoop:Disconnect()
		connections.fullAutoLoop = nil
	end
end

-- ===== WEAPON MANAGEMENT =====
local function loadSlot(weapon)
	if weapon and weapon ~= "" then
		-- Unequip current weapon
		if camera:FindFirstChildWhichIsA("Model") then
			local name = currentVM.Name
			currentVM:Destroy()
			currentVM = nil
			-- Toggle off if same weapon
			if name == weapon then
				player.CameraMode = Enum.CameraMode.Classic
				uis.MouseIcon = ""
				cancelReload()
				stopFullAutoShooting()
				return
			end
		end

		-- Find weapon viewmodel
		local vm = viewModelsFolder:FindFirstChild(weapon)
		if not vm then 
			warn("Weapon '" .. weapon .. "' not found in viewModels folder")
			return 
		end

		-- Switch to first person
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		uis.MouseIcon = "rbxassetid://8259335784"

		-- Setup new weapon
		local newVM = vm:Clone()
		newVM.Parent = camera
		currentVM = newVM

		-- Load weapon data
		inventory.module = require(currentVM.module)

		-- Load animations
		local animController = newVM:FindFirstChildOfClass("AnimationController")
		if not animController then
			warn("No AnimationController found in " .. weapon)
			return
		end

		loadedAnims.shoot = animController:LoadAnimation(newVM.Animations.Shoot)
		loadedAnims.reload = animController:LoadAnimation(newVM.Animations.Reload)

		-- Set initial accuracy
		currentSpreadAngle = inventory.module.idleSpread

		updateMouseSensitivity()
		stopFullAutoShooting()

		print("Equipped " .. weapon)
	end
end

-- ===== RELOAD SYSTEM =====
local function reload()
	if not currentVM or isBusy() then return end

	if currentVM.ammo.Value >= currentVM.maxAmmo.Value then
		print("Already at max ammo (" .. currentVM.maxAmmo.Value .. ")")
		return
	end

	print("Reloading...")
	reloading = true
	canShoot = false
	canReload = false

	loadedAnims.reload:Play()

	-- Wait for reload to finish
	local connection
	connection = loadedAnims.reload.Stopped:Connect(function()
		connection:Disconnect()
		if reloading then
			currentVM.ammo.Value = currentVM.maxAmmo.Value
			viewModelsFolder:FindFirstChild(currentVM.Name).ammo.Value = currentVM.maxAmmo.Value
			print("Reload complete")
		end
		cancelReload()
	end)
end

-- ===== BULLET SPREAD SYSTEM =====
local function spread(axis, angle)
	local cosAngle = math.cos(angle)
	local z = 1 - math.random() * (1 - cosAngle)
	local phi = math.random() * math.pi * 2
	local r = math.sqrt(1-z*z)
	local x = r * math.cos(phi)
	local y = r * math.sin(phi)
	local vec = Vector3.new(x, y, z)

	if axis.Z > 0.9999 then 
		return vec 
	elseif axis.Z < -0.9999 then 
		return -vec
	end

	local orth = Vector3.zAxis:Cross(axis)
	local rot = math.acos(axis:Dot(Vector3.zAxis))

	return CFrame.fromAxisAngle(orth, rot) * vec
end

-- ===== SHOOTING SYSTEM =====
local function shoot()
	if isBusy() then
		return
	end

	if currentVM.ammo.Value <= 0 then
		print("Out of ammo! Press R to reload")
		return
	end

	-- Fire the weapon
	canShoot = false
	currentVM.ammo.Value -= 1
	viewModelsFolder:FindFirstChild(currentVM.Name).ammo.Value -= 1

	loadedAnims.shoot:Play()

	-- Setup raycast
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character}
	rayParams.CollisionGroup = "gunRaycast"

	-- Apply spread and shoot
	local finalSpread = spread(camera.CFrame.LookVector, math.rad(currentSpreadAngle))
	local direction = finalSpread * 9999

	local ray = workspace:Raycast(character.Head.Position, direction, rayParams)
	if ray and ray.Instance then
		local pos = ray.Position
		rps.events.shootEvent:FireServer(ray.Instance, inventory.module.damage, pos, inventory.module.headshotDamage)
	end

	-- Cooldown before next shot
	task.delay(inventory.module.cooldown, function()
		if not reloading then
			canShoot = true
		end
	end)
end

-- ===== FULL-AUTO SYSTEM =====
local function startFullAutoShooting()
	if connections.fullAutoLoop then return end

	fullAutoShooting = true
	connections.fullAutoLoop = runService.Heartbeat:Connect(function()
		if not fullAutoShooting then
			connections.fullAutoLoop:Disconnect()
			connections.fullAutoLoop = nil
			return
		end

		if not isBusy() and currentVM and currentVM.ammo.Value > 0 then
			shoot()
		end
	end)
end

-- ===== MOUSE INPUT =====
uis.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not currentVM then return end

		if not inventory.module.fullAuto then
			shoot()
		else
			startFullAutoShooting()
		end
	end
end)

uis.InputEnded:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		stopFullAutoShooting()
	end
end)

-- ===== MOVEMENT ACCURACY =====
local moveConnection = character.Humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
	if currentVM and character.Humanoid.MoveDirection.Magnitude > 0 and not inAir then
		walking = true
		idle = false
		currentSpreadAngle = inventory.module.runningSpread
	elseif currentVM and character.Humanoid.MoveDirection.Magnitude == 0 then
		walking = false
		idle = true
		currentSpreadAngle = inventory.module.idleSpread
	end
end)

connections.moveConnection = moveConnection

-- ===== KEYBOARD INPUT =====
uis.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.KeyCode == Enum.KeyCode.One then
		loadSlot(inventory.primary)
	elseif input.KeyCode == Enum.KeyCode.Two then
		loadSlot(inventory.secondary)
	elseif input.KeyCode == Enum.KeyCode.Three then
		loadSlot(inventory.knife)
	elseif input.KeyCode == Enum.KeyCode.R then
		reload()
	end
end)

-- ===== VISUAL EFFECTS =====
local renderConnection = runService.RenderStepped:Connect(function()
	if character and currentVM then
		-- Camera sway
		local cameraRotation = camera.CFrame:ToObjectSpace(lastCameraCFrame)
		local x, y, z = cameraRotation:ToOrientation()
		lastCameraCFrame = camera.CFrame

		local swayX = math.clamp(math.sin(x * 2), -1, 1) * settings.swayAmount
		local swayY = math.clamp(math.sin(y * 2), -1, 1) * settings.swayAmount
		baseSway = CFrame.Angles(swayX, swayY, 0)
		swayCFrame = swayCFrame:Lerp(baseSway, 0.1)

		-- Weapon bobbing
		local bobX, bobY = 0, 0
		local t = time()

		if walking and not inAir then
			-- Walking bob
			bobX = math.sin(t * 7.5) / 20
			bobY = math.cos(t * 15) / 20
		elseif idle and not inAir then
			-- Idle breathing
			bobX = math.sin(t * 0.75) / 120
			bobY = math.cos(t * 1.5) / 120
		end

		-- Apply all effects
		local finalBob = CFrame.new(bobX, bobY, 0)
		local offset = inventory.module.blasterOffset or CFrame.new()

		local finalOffset = swayCFrame * finalBob * offset
		currentVM:PivotTo(camera.CFrame * finalOffset)
	end

	-- Air detection
	if character.Humanoid.FloorMaterial == Enum.Material.Air then
		inAir = true
		if currentVM then
			currentSpreadAngle = inventory.module.jumpingSpread
		end
	else
		inAir = false
	end
end)

connections.renderConnection = renderConnection

-- ===== CLEANUP =====
game.Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		for _, connection in pairs(connections) do
			if connection then
				connection:Disconnect()
			end
		end
	end
end)
