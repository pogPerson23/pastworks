-- ===== SERVICES =====
local rps = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local uis = game:GetService("UserInputService")

-- ===== PLAYER SETUP =====
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local camera = workspace.CurrentCamera

-- ===== CACHED REFERENCES =====
local viewModelsFolder = rps:WaitForChild("viewModels")
local shootEvent = rps.events.shootEvent

-- ===== WEAPON SYSTEM =====
local currentVM = nil
local weaponModules = {} -- Cache for weapon modules
local currentWeaponData = nil

-- ===== PLAYER STATES =====
local playerState = {
	idle = true,
	walking = false,
	shooting = false,
	fullAutoShooting = false,
	inAir = false,
	canShoot = true,
	canReload = true,
	reloading = false
}

-- ===== CACHED OBJECTS =====
local cachedAnimations = {}
local raycastParams = RaycastParams.new()

-- Setup raycast params once
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = {character}
raycastParams.CollisionGroup = "gunRaycast"

-- ===== INVENTORY =====
local inventory = {
	primary = "Rifle",
	secondary = "Pistol",
	knife = "Knife"
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
local currentSpreadAngle = 0

-- ===== CONNECTIONS =====
local connections = {}

-- ===== PRECOMPUTED VALUES =====
local mathPi2 = math.pi * 2
local zAxis = Vector3.zAxis

-- ===== UTILITY FUNCTIONS =====
local function updateMouseSensitivity()
	uis.MouseDeltaSensitivity = currentVM and settings.mouseSensitivity or 1.0
end

local function isBusy()
	return not playerState.canShoot or playerState.reloading or not currentVM
end

local function cleanupConnections()
	for name, connection in pairs(connections) do
		if connection then
			connection:Disconnect()
			connections[name] = nil
		end
	end
end

local function cancelReload()
	if cachedAnimations.reload and cachedAnimations.reload.IsPlaying then
		cachedAnimations.reload:Stop()
	end
	playerState.reloading = false
	playerState.canReload = true
	playerState.canShoot = true
end

local function stopFullAutoShooting()
	playerState.fullAutoShooting = false
	if connections.fullAutoLoop then
		connections.fullAutoLoop:Disconnect()
		connections.fullAutoLoop = nil
	end
end

-- ===== WEAPON MODULE CACHE =====
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

	-- Setup new weapon
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	uis.MouseIcon = "rbxassetid://8259335784"

	local newVM = vm:Clone()
	newVM.Parent = camera
	currentVM = newVM
	currentWeaponData = weaponModule

	-- Cache animations
	local animController = newVM:FindFirstChildOfClass("AnimationController")
	if animController then
		cachedAnimations.shoot = animController:LoadAnimation(newVM.Animations.Shoot)
		cachedAnimations.reload = animController:LoadAnimation(newVM.Animations.Reload)
	else
		warn("No AnimationController found in " .. weaponName)
		return false
	end

	-- Set initial accuracy
	currentSpreadAngle = weaponModule.idleSpread
	updateMouseSensitivity()
	stopFullAutoShooting()

	print("Equipped " .. weaponName)
	return true
end

local function loadSlot(weaponName)
	if not weaponName or weaponName == "" then return end

	-- Toggle off if same weapon
	if currentVM and currentVM.Name == weaponName then
		unequipWeapon()
		return
	end

	-- Unequip current weapon
	if currentVM then
		unequipWeapon()
	end

	-- Equip new weapon
	equipWeapon(weaponName)
end

-- ===== RELOAD SYSTEM =====
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

	-- Single connection for reload completion
	if connections.reloadConnection then
		connections.reloadConnection:Disconnect()
	end

	connections.reloadConnection = cachedAnimations.reload.Stopped:Connect(function()
		connections.reloadConnection:Disconnect()
		connections.reloadConnection = nil

		if playerState.reloading then
			-- Update ammo in both places efficiently
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

-- ===== OPTIMIZED BULLET SPREAD =====
local function calculateSpread(axis, angle)
	local cosAngle = math.cos(angle)
	local z = 1 - math.random() * (1 - cosAngle)
	local phi = math.random() * mathPi2
	local r = math.sqrt(1 - z * z)
	local x = r * math.cos(phi)
	local y = r * math.sin(phi)
	local vec = Vector3.new(x, y, z)

	if axis.Z > 0.9999 then 
		return vec 
	elseif axis.Z < -0.9999 then 
		return -vec
	end

	local orth = zAxis:Cross(axis)
	local rot = math.acos(axis:Dot(zAxis))
	return CFrame.fromAxisAngle(orth, rot) * vec
end

-- ===== SHOOTING SYSTEM =====
local function shoot()
	if isBusy() or currentVM.ammo.Value <= 0 then
		if currentVM.ammo.Value <= 0 then
			print("Out of ammo! Press R to reload")
		end
		return
	end

	-- Fire the weapon
	playerState.canShoot = false

	-- Update ammo efficiently
	local newAmmo = currentVM.ammo.Value - 1
	currentVM.ammo.Value = newAmmo

	local originalVM = viewModelsFolder:FindFirstChild(currentVM.Name)
	if originalVM then
		originalVM.ammo.Value = newAmmo
	end

	cachedAnimations.shoot:Play()

	-- Apply spread and shoot
	local spreadDirection = calculateSpread(camera.CFrame.LookVector, math.rad(currentSpreadAngle))
	local direction = spreadDirection * 9999

	local ray = workspace:Raycast(character.Head.Position, direction, raycastParams)
	if ray and ray.Instance then
		shootEvent:FireServer(
			ray.Instance, 
			currentWeaponData.damage, 
			ray.Position, 
			currentWeaponData.headshotDamage
		)
	end

	-- Cooldown before next shot
	task.delay(currentWeaponData.cooldown, function()
		if not playerState.reloading then
			playerState.canShoot = true
		end
	end)
end

-- ===== FULL-AUTO SYSTEM =====
local function startFullAutoShooting()
	if connections.fullAutoLoop or not currentVM then return end

	playerState.fullAutoShooting = true
	connections.fullAutoLoop = runService.Heartbeat:Connect(function()
		if not playerState.fullAutoShooting then
			connections.fullAutoLoop:Disconnect()
			connections.fullAutoLoop = nil
			return
		end

		if not isBusy() and currentVM and currentVM.ammo.Value > 0 then
			shoot()
		end
	end)
end

-- ===== MOVEMENT ACCURACY =====
local function updateMovementState()
	if not currentVM then return end

	local moveDirection = character.Humanoid.MoveDirection
	local isMoving = moveDirection.Magnitude > 0

	if isMoving and not playerState.inAir then
		playerState.walking = true
		playerState.idle = false
		currentSpreadAngle = currentWeaponData.runningSpread
	elseif not isMoving then
		playerState.walking = false
		playerState.idle = true
		currentSpreadAngle = currentWeaponData.idleSpread
	end
end

-- ===== INPUT HANDLERS =====
local function handleMouseInput(input, began)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not currentVM then
		return
	end

	if began then
		if not currentWeaponData.fullAuto then
			shoot()
		else
			startFullAutoShooting()
		end
	else
		stopFullAutoShooting()
	end
end

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
uis.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleMouseInput(input, true)
	else
		handleKeyboardInput(input)
	end
end)

uis.InputEnded:Connect(function(input, processed)
	if processed then return end
	handleMouseInput(input, false)
end)

-- Movement connection
connections.moveConnection = character.Humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(updateMovementState)

-- ===== VISUAL EFFECTS =====
connections.renderConnection = runService.RenderStepped:Connect(function()
	if not character or not currentVM then return end

	-- Air detection
	playerState.inAir = character.Humanoid.FloorMaterial == Enum.Material.Air
	if playerState.inAir and currentWeaponData then
		currentSpreadAngle = currentWeaponData.jumpingSpread
	end

	-- Camera sway calculation
	local cameraRotation = camera.CFrame:ToObjectSpace(lastCameraCFrame)
	local x, y = cameraRotation:ToOrientation()
	lastCameraCFrame = camera.CFrame

	local swayX = math.clamp(math.sin(x * 2), -1, 1) * settings.swayAmount
	local swayY = math.clamp(math.sin(y * 2), -1, 1) * settings.swayAmount
	baseSway = CFrame.Angles(swayX, swayY, 0)
	swayCFrame = swayCFrame:Lerp(baseSway, 0.1)

	-- Weapon bobbing
	local bobX, bobY = 0, 0
	local t = time()

	if playerState.walking and not playerState.inAir then
		-- Walking bob
		bobX = math.sin(t * 7.5) / 20
		bobY = math.cos(t * 15) / 20
	elseif playerState.idle and not playerState.inAir then
		-- Idle breathing
		bobX = math.sin(t * 0.75) / 120
		bobY = math.cos(t * 1.5) / 120
	end

	-- Apply all effects
	local finalBob = CFrame.new(bobX, bobY, 0)
	local offset = currentWeaponData.blasterOffset or CFrame.new()
	local finalOffset = swayCFrame * finalBob * offset

	currentVM:PivotTo(camera.CFrame * finalOffset)
end)

-- ===== CLEANUP =====
game.Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		cleanupConnections()
	end
end)
