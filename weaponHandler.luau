-- ===== SERVICES =====
-- Get references to Roblox services we'll need
local rps = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local uis = game:GetService("UserInputService")

-- ===== PLAYER AND CAMERA SETUP =====
-- Get the local player and their character
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- ===== WEAPON SYSTEM VARIABLES =====
-- Folder containing all weapon viewmodels in ReplicatedStorage
local viewModelsFolder = rps:WaitForChild("viewModels")
-- Currently equipped weapon's viewmodel (nil if no weapon equipped)
local currentVM = nil

-- ===== PLAYER STATE TRACKING =====
-- Track what the player is currently doing
local idle = true              -- Standing still
local walking = false          -- Moving on ground
local shooting = false         -- Currently firing (not used much)
local fullAutoShooting = false -- Holding down mouse for full-auto weapons
local inAir = false           -- Player is jumping/falling
local canShoot = true         -- Can fire weapon (not reloading/cooling down)
local canReload = true        -- Can start reload (not already reloading)
local reloading = false       -- Currently reloading

-- ===== ANIMATION STORAGE =====
-- Store loaded animations for the current weapon
local loadedAnims = {
	shoot = nil,   -- Shooting animation
	reload = nil   -- Reload animation
}

-- ===== INVENTORY SYSTEM =====
-- Player's weapon loadout
local inventory = {
	primary = "Rifle",   -- Primary weapon name
	secondary = "Pistol", -- Secondary weapon name
	knife = "Knife", -- Knife name
	module = nil         -- Currently equipped weapon's module script
}

-- ===== VISUAL SETTINGS =====
-- Camera sway/movement settings
local settings = {
	swayAmount = 0.1,      -- How much the viewmodel sways when looking around
	mouseSensitivity = 0.3 -- Mouse sensitivity multiplier (0.1 = very slow, 1.0 = normal, 2.0 = very fast)
}

-- ===== CAMERA MOVEMENT VARIABLES =====
-- Variables for smooth camera sway and weapon bobbing
local swayCFrame = CFrame.new()           -- Current sway offset
local lastCameraCFrame = camera.CFrame    -- Previous frame's camera position
local baseSway = CFrame.new()            -- Target sway position
local currentSpreadAngle                  -- Current weapon spread (accuracy)

-- ===== CAMERA SENSITIVITY SYSTEM =====
-- Apply custom mouse sensitivity when weapon is equipped
local function updateMouseSensitivity()
	if currentVM then
		-- Set mouse sensitivity when weapon is equipped
		uis.MouseDeltaSensitivity = settings.mouseSensitivity
	else
		-- Reset to default when no weapon
		uis.MouseDeltaSensitivity = 1.0
	end
end

-- ===== UTILITY FUNCTIONS =====

-- Check if player can't shoot (busy with other actions)
local function isBusy()
	return not canShoot or reloading or not currentVM
end

-- Stop reload animation and reset reload state
local function cancelReload()
	-- Stop the reload animation if it's playing
	if loadedAnims.reload and loadedAnims.reload.IsPlaying then
		loadedAnims.reload:Stop()
	end
	-- Reset all reload-related flags
	reloading = false
	canReload = true
	canShoot = true
end

-- ===== WEAPON MANAGEMENT =====

-- Equip a weapon by name (or unequip if same weapon)
local function loadSlot(weapon)
	-- Only proceed if weapon name is valid
	if weapon and weapon ~= "" then
		-- If we already have a weapon equipped
		if camera:FindFirstChildWhichIsA("Model") then
			local name = currentVM.Name
			-- Destroy the current viewmodel
			currentVM:Destroy()
			currentVM = nil
			-- If trying to equip the same weapon, just unequip and return to 3rd person
			if name == weapon then
				player.CameraMode = Enum.CameraMode.Classic
				mouse.Icon = ""
				cancelReload()
				return
			end
		end

		-- Try to find the weapon in the viewmodels folder
		local vm = viewModelsFolder:FindFirstChild(weapon)
		if not vm then warn("Could not find weapon in weapons folder") return end

		-- Switch to first person mode
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		mouse.Icon = "rbxassetid://8259335784"

		-- Clone the weapon viewmodel and parent it to camera
		local newVM = vm:Clone()
		newVM.Parent = camera
		currentVM = newVM

		-- Load the weapon's data module (contains damage, spread, etc.)
		inventory.module = require(currentVM.module)

		-- Load weapon animations
		local animController = newVM:FindFirstChildOfClass("AnimationController")
		loadedAnims.shoot = animController:LoadAnimation(newVM.Animations.Shoot)
		loadedAnims.reload = animController:LoadAnimation(newVM.Animations.Reload)

		-- Set initial spread to idle (most accurate)
		currentSpreadAngle = inventory.module.idleSpread

		-- Apply mouse sensitivity for this weapon
		updateMouseSensitivity()
	end
end

-- ===== RELOAD SYSTEM =====

-- Handle weapon reloading
local function reload()
	-- Can't reload if no weapon, busy, or already have full ammo
	if not currentVM or isBusy() then return end

	if currentVM.ammo.Value >= currentVM.maxAmmo.Value then
		print("Already full ammo")
		return
	end

	-- Start reload process - disable shooting and set flags
	reloading = true
	canShoot = false
	canReload = false

	-- Play reload animation
	loadedAnims.reload:Play()

	-- When reload animation finishes, refill ammo
	local connection
	connection = loadedAnims.reload.Stopped:Connect(function()
		connection:Disconnect() -- Clean up the connection
		if reloading then -- Only refill if reload wasn't cancelled
			-- Set ammo to max for both local viewmodel and server copy
			currentVM.ammo.Value = currentVM.maxAmmo.Value
			viewModelsFolder:FindFirstChild(currentVM.Name).ammo.Value = currentVM.maxAmmo.Value
		end
		cancelReload() -- Reset reload state
	end)
end

-- ===== BULLET SPREAD SYSTEM =====

-- Generate random spread direction based on cone angle
-- This makes bullets less accurate when moving/jumping
local function spread(axis, angle)
	-- Mathematical magic to create random direction within a cone
	local cosAngle = math.cos(angle)
	local z = 1 - math.random() * (1 - cosAngle)
	local phi = math.random() * math.pi * 2
	local r = math.sqrt(1-z*z)
	local x = r * math.cos(phi)
	local y = r * math.sin(phi)
	local vec = Vector3.new(x, y, z)

	-- Handle edge cases for straight up/down
	if axis.Z > 0.9999 then 
		return vec 
	elseif axis.z < -0.9999 then 
		return -vec
	end

	-- Rotate the spread vector to match camera direction
	local orth = Vector3.zAxis:Cross(axis)
	local rot = math.acos(axis:Dot(Vector3.zAxis))

	return CFrame.fromAxisAngle(orth, rot) * vec
end

-- ===== SHOOTING SYSTEM =====

-- Fire the current weapon
local function shoot()
	print(currentSpreadAngle) -- Debug: show current accuracy

	-- Can't shoot if busy, no weapon, or no ammo
	if isBusy() then
		print("Busy: Can't shoot")
		return
	end

	if currentVM.ammo.Value <= 0 then
		print("No ammo")
		return
	end

	-- Disable shooting temporarily (fire rate control)
	canShoot = false
	-- Consume one bullet
	currentVM.ammo.Value -= 1
	viewModelsFolder:FindFirstChild(currentVM.Name).ammo.Value -= 1

	-- Play shooting animation
	loadedAnims.shoot:Play()

	-- ===== RAYCAST BULLET SYSTEM =====
	-- Set up raycast parameters
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character} -- Don't hit ourselves
	rayParams.CollisionGroup = "gunRaycast"

	-- Apply spread to make bullet less accurate based on movement
	local finalSpread = spread(camera.CFrame.LookVector, math.rad(currentSpreadAngle))
	local direction = finalSpread * 9999 -- Long distance

	-- Cast the ray from head position
	local ray = workspace:Raycast(character.Head.Position, direction, rayParams)
	if ray and ray.Instance then
		local pos = ray.Position
		-- Tell server we hit something (damage calculation happens server-side)
		rps.events.shootEvent:FireServer(ray.Instance, inventory.module.damage, pos, inventory.module.headshotDamage)
	end

	-- Re-enable shooting after weapon's cooldown period
	task.delay(inventory.module.cooldown, function()
		if not reloading then -- Don't allow shooting while reloading
			canShoot = true
		end
	end)
end

-- ===== INPUT HANDLING =====

-- Handle mouse click (shooting)
mouse.Button1Down:Connect(function()
	if not currentVM then return end -- No weapon equipped

	if not inventory.module.fullAuto then
		-- Semi-auto: shoot once per click
		shoot()
	else
		-- Full-auto: start continuous shooting
		fullAutoShooting = true
	end
end)

-- Stop full-auto shooting when mouse released
mouse.Button1Up:Connect(function()
	fullAutoShooting = false
end)

-- ===== MOVEMENT-BASED ACCURACY =====

-- Adjust weapon accuracy based on player movement
character.Humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
	-- Player is moving on ground
	if currentVM and character.Humanoid.MoveDirection.Magnitude > 0 and not inAir then
		walking = true
		idle = false
		-- Less accurate when moving
		currentSpreadAngle = inventory.module.runningSpread
		print("current spread angle is " .. currentSpreadAngle)
		-- Player stopped moving
	elseif currentVM and character.Humanoid.MoveDirection.Magnitude == 0 then
		walking = false
		idle = true
		-- Most accurate when standing still
		currentSpreadAngle = inventory.module.idleSpread
	end
end)

-- ===== KEYBOARD INPUT =====

-- Handle key presses
uis.InputBegan:Connect(function(input, processed)
	if processed then return end -- Ignore if typing in chat/etc

	if input.KeyCode == Enum.KeyCode.One then
		loadSlot(inventory.primary)   -- Equip primary weapon
	elseif input.KeyCode == Enum.KeyCode.Two then
		loadSlot(inventory.secondary) -- Equip secondary weapon
	elseif input.KeyCode == Enum.KeyCode.Three then
		loadSlot(inventory.knife)
	elseif input.KeyCode == Enum.KeyCode.R then
		reload()                      -- Reload current weapon
	end
end)

-- ===== VISUAL EFFECTS LOOP =====

-- Main rendering loop - runs every frame
runService.RenderStepped:Connect(function()
	-- Only update visuals if player has weapon equipped
	if character and currentVM then
		-- ===== CAMERA SWAY SYSTEM =====
		-- Calculate how much camera rotated since last frame
		local cameraRotation = camera.CFrame:ToObjectSpace(lastCameraCFrame)
		local x, y, z = cameraRotation:ToOrientation()
		lastCameraCFrame = camera.CFrame

		-- Convert camera movement to weapon sway
		local swayX = math.clamp(math.sin(x * 2), -1, 1) * settings.swayAmount
		local swayY = math.clamp(math.sin(y * 2), -1, 1) * settings.swayAmount
		baseSway = CFrame.Angles(swayX, swayY, 0)
		-- Smoothly interpolate to new sway position
		swayCFrame = swayCFrame:Lerp(baseSway, 0.1)

		-- ===== WEAPON BOBBING SYSTEM =====
		local bobX, bobY = 0, 0
		local t = time() -- Current time for sine wave calculations

		-- Different bobbing patterns based on movement
		if walking and not inAir then
			-- Walking bob - more intense, faster rhythm
			bobX = math.sin(t * 7.5) / 20    -- Side-to-side
			bobY = math.cos(t * 15) / 20     -- Up-and-down (2x frequency)
		elseif idle and not inAir then
			-- Idle bob - subtle breathing effect
			bobX = math.sin(t * 0.75) / 120  -- Very slow side movement
			bobY = math.cos(t * 1.5) / 120   -- Slow breathing movement
		end

		-- ===== COMBINE ALL VISUAL EFFECTS =====
		local finalBob = CFrame.new(bobX, bobY, 0)
		-- Get weapon's base position offset
		local offset = inventory.module.blasterOffset or CFrame.new()

		-- Combine sway + bobbing + weapon offset
		local finalOffset = swayCFrame * finalBob * offset
		-- Apply final position to viewmodel
		currentVM:PivotTo(camera.CFrame * finalOffset)
	end

	-- ===== AIR DETECTION AND ACCURACY =====
	-- Check if player is in air (affects weapon accuracy)
	if character.Humanoid.FloorMaterial == Enum.Material.Air then
		inAir = true
		if currentVM then
			-- Least accurate when jumping/falling
			currentSpreadAngle = inventory.module.jumpingSpread
		end
	else
		inAir = false
		-- Note: Don't reset spread here, let movement detection handle it
		-- This prevents overriding the walking/idle spread values
	end
end)

-- ===== FULL-AUTO SHOOTING LOOP =====

-- Continuous loop for full-auto weapons
while task.wait() do
	-- Keep shooting while mouse held down, weapon available, and has ammo
	if fullAutoShooting and not isBusy() and currentVM and currentVM.ammo.Value > 0 then
		shoot()
	end
end
