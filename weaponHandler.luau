-- ===== SERVICES =====
-- Roblox services used throughout the script
local rps = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local uis = game:GetService("UserInputService")

-- ===== PLAYER SETUP =====
-- Core player references
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera

-- ===== OTHER REFERENCES =====
-- Frequently accessed objects
local viewModelsFolder = rps:WaitForChild("viewModels")
local shootEvent = rps.events.shootEvent

-- ===== WEAPON SYSTEM =====
-- Current weapon state and data
local currentVM = nil -- Active viewmodel in camera
local weaponModules = {} -- weapon modules to avoid repeated require() calls
local currentWeaponData = nil

-- ===== PLAYER STATES =====
-- Tracks player actions that affect weapon behavior
local playerState = {
	idle = true,
	walking = false,
	shooting = false,
	fullAutoShooting = false, -- Continuous firing for automatic weapons
	inAir = false, -- Affects weapon accuracy
	canShoot = true, -- Shooting cooldown state
	canReload = true,
	reloading = false
}

-- ===== CACHED OBJECTS =====
local cachedAnimations = {}
local raycastParams = RaycastParams.new()

-- Raycast params
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = {character} -- Prevents self-collision
raycastParams.CollisionGroup = "gunRaycast"

-- ===== INVENTORY =====
-- Player's weapon loadout
local inventory = {
	primary = "Rifle",   -- Key 1
	secondary = "Pistol", -- Key 2
	knife = "Knife"      -- Key 3
}

-- ===== VISUAL SETTINGS =====
-- Weapon feel and visual behavior settings
local settings = {
	swayAmount = 0.1,        -- Camera movement influence on weapon position
	mouseSensitivity = 0.3   -- Reduced sensitivity when weapon is equipped
}

-- ===== CAMERA MOVEMENT =====
-- Camera sway and weapon positioning variables
local swayCFrame = CFrame.new()
local lastCameraCFrame = camera.CFrame
local baseSway = CFrame.new()
local currentSpreadAngle = 0 -- Current weapon accuracy/spread

-- ===== CONNECTIONS =====
-- Event connection storage for proper cleanup
local connections = {}

-- ===== PRECOMPUTED VALUES =====
-- Pre-calculated constants for weapon 
local mathPi2 = math.pi * 2
local zAxis = Vector3.zAxis

-- ===== UTILITY FUNCTIONS =====

-- Adjusts mouse sensitivity based on weapon state
local function updateMouseSensitivity()
	uis.MouseDeltaSensitivity = currentVM and settings.mouseSensitivity or 1.0
end

-- Returns true if player cannot shoot (cooldown, reloading, no weapon)
local function isBusy()
	return not playerState.canShoot or playerState.reloading or not currentVM
end

-- Disconnects all event connections to prevent memory leaks
local function cleanupConnections()
	for name, connection in pairs(connections) do
		if connection then
			connection:Disconnect()
			connections[name] = nil
		end
	end
end

-- Stops reload animation and resets reload state
local function cancelReload()
	if cachedAnimations.reload and cachedAnimations.reload.IsPlaying then
		cachedAnimations.reload:Stop()
	end
	playerState.reloading = false
	playerState.canReload = true
	playerState.canShoot = true
end

-- Stops full-auto firing loop
local function stopFullAutoShooting()
	playerState.fullAutoShooting = false
	if connections.fullAutoLoop then
		connections.fullAutoLoop:Disconnect()
		connections.fullAutoLoop = nil
	end
end

-- ===== WEAPON MODULE CACHE =====
-- Retrieves and caches weapon module data
local function getWeaponModule(weaponName)
	if not weaponModules[weaponName] then
		local vm = viewModelsFolder:FindFirstChild(weaponName)
		if vm and vm:FindFirstChild("module") then
			weaponModules[weaponName] = require(vm.module)
		end
	end
	return weaponModules[weaponName]
end

-- ===== WEAPON MANAGEMENT =====
-- Removes current weapon and resets player state
local function unequipWeapon()
	if currentVM then
		currentVM:Destroy()
		currentVM = nil
		currentWeaponData = nil
		cachedAnimations = {}
	end

	player.CameraMode = Enum.CameraMode.Classic
	uis.MouseIcon = ""
	cancelReload()
	stopFullAutoShooting()
	updateMouseSensitivity()
end

-- Equips specified weapon with full setup
local function equipWeapon(weaponName)
	local weaponModule = getWeaponModule(weaponName)
	if not weaponModule then
		warn("Weapon '" .. weaponName .. "' not found or has no module")
		return false
	end

	local vm = viewModelsFolder:FindFirstChild(weaponName)
	if not vm then
		warn("Weapon '" .. weaponName .. "' not found in viewModels folder")
		return false
	end

	-- Configure first-person mode and crosshair
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	uis.MouseIcon = "rbxassetid://8259335784"

	-- Clone and setup viewmodel
	local newVM = vm:Clone()
	newVM.Parent = camera
	currentVM = newVM
	currentWeaponData = weaponModule

	-- Load and cache weapon animations
	local animController = newVM:FindFirstChildOfClass("AnimationController")
	if animController then
		cachedAnimations.shoot = animController:LoadAnimation(newVM.Animations.Shoot)
		cachedAnimations.reload = animController:LoadAnimation(newVM.Animations.Reload)
	else
		warn("No AnimationController found in " .. weaponName)
		return false
	end

	-- Set weapon accuracy to idle state
	currentSpreadAngle = weaponModule.idleSpread
	updateMouseSensitivity()
	stopFullAutoShooting()

	print("Equipped " .. weaponName)
	return true
end

-- Handles weapon switching with toggle functionality
local function loadSlot(weaponName)
	if not weaponName or weaponName == "" then return end

	-- Toggle off if same weapon is already equipped
	if currentVM and currentVM.Name == weaponName then
		unequipWeapon()
		return
	end

	-- Switch to new weapon
	if currentVM then
		unequipWeapon()
	end

	equipWeapon(weaponName)
end

-- ===== RELOAD SYSTEM =====
-- Handles weapon reloading with animation and ammo management
local function reload()
	if not currentVM or isBusy() then return end

	local maxAmmo = currentVM.maxAmmo.Value
	if currentVM.ammo.Value >= maxAmmo then
		print("Already at max ammo (" .. maxAmmo .. ")")
		return
	end

	print("Reloading...")
	playerState.reloading = true
	playerState.canShoot = false
	playerState.canReload = false

	cachedAnimations.reload:Play()

	-- Setup reload completion handler
	if connections.reloadConnection then
		connections.reloadConnection:Disconnect()
	end

	connections.reloadConnection = cachedAnimations.reload.Stopped:Connect(function()
		connections.reloadConnection:Disconnect()
		connections.reloadConnection = nil

		if playerState.reloading then
			-- Update ammo in viewmodel and original model
			currentVM.ammo.Value = maxAmmo
			local originalVM = viewModelsFolder:FindFirstChild(currentVM.Name)
			if originalVM then
				originalVM.ammo.Value = maxAmmo
			end
			print("Reload complete")
		end
		cancelReload()
	end)
end

-- ===== BULLET SPREAD =====
-- Calculates random bullet spread direction using spherical coordinates
local function calculateSpread(axis, angle)
	local cosAngle = math.cos(angle)
	local z = 1 - math.random() * (1 - cosAngle)
	local phi = math.random() * mathPi2
	local r = math.sqrt(1 - z * z)
	local x = r * math.cos(phi)
	local y = r * math.sin(phi)
	local vec = Vector3.new(x, y, z)

	-- Handle edge cases for axis alignment
	if axis.Z > 0.9999 then 
		return vec 
	elseif axis.Z < -0.9999 then 
		return -vec
	end

	-- Rotate vector to align with desired axis
	local orth = zAxis:Cross(axis)
	local rot = math.acos(axis:Dot(zAxis))
	return CFrame.fromAxisAngle(orth, rot) * vec
end

-- ===== SHOOTING SYSTEM =====
-- Handles single shot firing with raycast 
local function shoot()
	if isBusy() or currentVM.ammo.Value <= 0 then
		if currentVM.ammo.Value <= 0 then
			print("Out of ammo! Press R to reload")
		end
		return
	end

	-- Begin shooting sequence
	playerState.canShoot = false

	-- Consume ammunition
	local newAmmo = currentVM.ammo.Value - 1
	currentVM.ammo.Value = newAmmo

	-- Update original weapon model ammo
	local originalVM = viewModelsFolder:FindFirstChild(currentVM.Name)
	if originalVM then
		originalVM.ammo.Value = newAmmo
	end

	cachedAnimations.shoot:Play()

	-- Calculate bullet trajectory with spread
	local spreadDirection = calculateSpread(camera.CFrame.LookVector, math.rad(currentSpreadAngle))
	local direction = spreadDirection * 9999

	-- Perform raycast and send hit data to server
	local ray = workspace:Raycast(character.Head.Position, direction, raycastParams)
	if ray and ray.Instance then
		shootEvent:FireServer(
			ray.Instance, 
			currentWeaponData.damage, 
			ray.Position, 
			currentWeaponData.headshotDamage
		)
	end

	-- Apply shooting cooldown
	task.delay(currentWeaponData.cooldown, function()
		if not playerState.reloading then
			playerState.canShoot = true
		end
	end)
end

-- ===== FULL-AUTO SYSTEM =====
-- Starts continuous firing loop for automatic weapons
local function startFullAutoShooting()
	if connections.fullAutoLoop or not currentVM then return end

	playerState.fullAutoShooting = true
	connections.fullAutoLoop = runService.Heartbeat:Connect(function()
		if not playerState.fullAutoShooting then
			connections.fullAutoLoop:Disconnect()
			connections.fullAutoLoop = nil
			return
		end

		-- Fire as fast as possible while conditions are met
		if not isBusy() and currentVM and currentVM.ammo.Value > 0 then
			shoot()
		end
	end)
end

-- ===== MOVEMENT ACCURACY =====
-- Updates weapon accuracy based on player movement state
local function updateMovementState()
	if not currentVM then return end

	local moveDirection = character.Humanoid.MoveDirection
	local isMoving = moveDirection.Magnitude > 0

	if isMoving and not playerState.inAir then
		-- Moving on ground reduces accuracy
		playerState.walking = true
		playerState.idle = false
		currentSpreadAngle = currentWeaponData.runningSpread
	elseif not isMoving then
		-- Standing still improves accuracy
		playerState.walking = false
		playerState.idle = true
		currentSpreadAngle = currentWeaponData.idleSpread
	end
end

-- ===== INPUT HANDLERS =====
-- Processes mouse input for shooting
local function handleMouseInput(input, began)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not currentVM then
		return
	end

	if began then
		if not currentWeaponData.fullAuto then
			shoot() -- Single shot
		else
			startFullAutoShooting() -- Begin automatic fire
		end
	else
		stopFullAutoShooting() -- Stop automatic fire on release
	end
end

-- Processes keyboard input for weapon switching and reloading
local function handleKeyboardInput(input)
	if input.KeyCode == Enum.KeyCode.One then
		loadSlot(inventory.primary)
	elseif input.KeyCode == Enum.KeyCode.Two then
		loadSlot(inventory.secondary)
	elseif input.KeyCode == Enum.KeyCode.Three then
		loadSlot(inventory.knife)
	elseif input.KeyCode == Enum.KeyCode.R then
		reload()
	end
end

-- ===== EVENT CONNECTIONS =====
-- Handle input start events
uis.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleMouseInput(input, true)
	else
		handleKeyboardInput(input)
	end
end)

-- Handle input end events
uis.InputEnded:Connect(function(input, processed)
	if processed then return end
	handleMouseInput(input, false)
end)

-- Track player movement changes
connections.moveConnection = character.Humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(updateMovementState)

-- ===== VISUAL EFFECTS =====
-- Main rendering loop for weapon positioning and effects
connections.renderConnection = runService.RenderStepped:Connect(function()
	if not character or not currentVM then return end

	-- Detect if player is airborne
	playerState.inAir = character.Humanoid.FloorMaterial == Enum.Material.Air
	if playerState.inAir and currentWeaponData then
		currentSpreadAngle = currentWeaponData.jumpingSpread -- Worst accuracy while jumping
	end

	-- Calculate camera sway based on camera rotation
	local cameraRotation = camera.CFrame:ToObjectSpace(lastCameraCFrame)
	local x, y = cameraRotation:ToOrientation()
	lastCameraCFrame = camera.CFrame

	-- Apply sway with clamping to prevent excessive movement
	local swayX = math.clamp(math.sin(x * 2), -1, 1) * settings.swayAmount
	local swayY = math.clamp(math.sin(y * 2), -1, 1) * settings.swayAmount
	baseSway = CFrame.Angles(swayX, swayY, 0)
	swayCFrame = swayCFrame:Lerp(baseSway, 0.1)

	-- Calculate weapon bobbing effects
	local bobX, bobY = 0, 0
	local t = time()

	if playerState.walking and not playerState.inAir then
		-- Walking bob pattern
		bobX = math.sin(t * 7.5) / 20
		bobY = math.cos(t * 15) / 20
	elseif playerState.idle and not playerState.inAir then
		-- Subtle idle breathing effect
		bobX = math.sin(t * 0.75) / 120
		bobY = math.cos(t * 1.5) / 120
	end

	-- Combine all visual effects and position weapon
	local finalBob = CFrame.new(bobX, bobY, 0)
	local offset = currentWeaponData.blasterOffset or CFrame.new()
	local finalOffset = swayCFrame * finalBob * offset

	currentVM:PivotTo(camera.CFrame * finalOffset)
end)

-- ===== CLEANUP =====
-- Clean up connections when player leaves
game.Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		cleanupConnections()
	end
end)
