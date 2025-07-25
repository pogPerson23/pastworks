--[[
	Pet Care System
	
	Features:
	✅ Hunger/Thirst/Happiness depletion
	✅ Happiness affects depletion rate
	✅ Pet death system
	✅ UI updates with smooth animations
	✅ Remote event integration
	✅ Money drops every 10 seconds
	
	TODO:
	- Passive income items in shop
	- add different faces
--]]

-- Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")

-- UI References
local frame = script.Parent
local sliders = {
	hunger = frame.sliderFolder.HungerSlider,
	thirst = frame.sliderFolder.ThirstSlider,
	happiness = frame.sliderFolder.HappinessSlider,
}
local labels = {
	hunger = frame.statLabels.HungerLabel,
	thirst = frame.statLabels.ThirstLabel,
	happiness = frame.statLabels.HappinessLabel,
}

-- Configuration
local ORIGINAL_DEPLETION_TIMES = {
	hunger = 60,
	thirst = 10,
	happiness = 90,
}

local CONFIG = {
	hungerFullDepletionSeconds = 60,
	thirstFullDepletionSeconds = 10,
	happinessFullDepletionSeconds = 90,
	happinessDepletionMultiplier = 1.35,
	moneyDropTime = 10,
	maxMoneyValue = 5,
}

-- Game State
local stats = {
	hunger = 100,
	thirst = 100,
	happiness = 100,
}

local player = game.Players:GetPlayers()[1] or game.Players.PlayerAdded:Wait()

-- Core Functions
local function calculateHappinessMultiplier(originalTime)
	local invertedMultiplier = math.floor(stats.happiness / 20)
	local regularMultiplier = 5 - invertedMultiplier
	local adjustedMultiplier = regularMultiplier - 1

	if adjustedMultiplier > 0 then
		return originalTime / (CONFIG.happinessDepletionMultiplier * adjustedMultiplier)
	end

	return nil
end

local function updateStatUI(statValue, slider, label, statName)
	-- Update slider with smooth animation
	local goalSize = UDim2.fromScale(statValue / 100, slider.Size.Y.Scale)
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(slider, tweenInfo, { Size = goalSize })
	tween:Play()

	-- Update label text
	label.Text = string.gsub(label.Text, "-?%d+%.?%d*", tostring(statValue))

	-- Notify client
	replicatedStorage.remoteEvents.updatePetManagerRemoteEvent:FireClient(player, statName, statValue)
end

local function killPet(statName)
	print(statName .. " depleted! Pet is dead 💀")

	if not workspace.pet:FindFirstChild("Dead") then
		local deadValue = Instance.new("BoolValue")
		deadValue.Name = "Dead"
		deadValue.Value = true
		deadValue.Parent = workspace.pet
		local particleEmitter = Instance.new("ParticleEmitter", workspace.pet.PrimaryPart)
		particleEmitter.Texture = "rbxassetid://410256160"

		workspace.pet.primaryPart.BrickColor = BrickColor.new("Really black")
	end
end

local function depleteStat(statName, slider, label)
	while task.wait(1) do
		-- Check if pet is dead
		if workspace.pet:FindFirstChild("Dead") then
			break
		end

		-- Get current depletion rate
		local depletionSeconds = CONFIG[statName .. "FullDepletionSeconds"]
		local drainPerSecond = 100 / depletionSeconds

		-- Update stat value
		stats[statName] = math.round((stats[statName] - drainPerSecond) * 10) / 10

		-- Handle happiness special case (doesn't kill pet)
		if statName == "happiness" and stats[statName] <= 0 then
			stats[statName] = 0
			updateStatUI(stats[statName], slider, label, statName)
			continue
		end

		-- Handle death condition for hunger/thirst
		if stats[statName] <= 0 then
			stats[statName] = 0
			updateStatUI(stats[statName], slider, label, statName)
			killPet(statName)
			break
		end

		updateStatUI(stats[statName], slider, label, statName)
	end
end

local function updateDepletionRates()
	-- Update hunger depletion rate based on happiness
	local newHungerTime = calculateHappinessMultiplier(ORIGINAL_DEPLETION_TIMES.hunger)
	CONFIG.hungerFullDepletionSeconds = newHungerTime or ORIGINAL_DEPLETION_TIMES.hunger

	-- Update thirst depletion rate based on happiness
	local newThirstTime = calculateHappinessMultiplier(ORIGINAL_DEPLETION_TIMES.thirst)
	CONFIG.thirstFullDepletionSeconds = newThirstTime or ORIGINAL_DEPLETION_TIMES.thirst
end

local function restoreStatAmount(amount, statName)
	stats[statName] = math.min(stats[statName] + amount, 100)
	updateStatUI(stats[statName], sliders[statName], labels[statName], statName)
end

local function dropMoney()
	local money = replicatedStorage.otherParts.money:Clone()
	local value = Instance.new("IntValue")
	value.Value = math.random(1, CONFIG.maxMoneyValue)
	value.Name = "Value"
	value.Parent = money

	local pet = workspace.pet
	local dropPosition = pet.PrimaryPart.Position - pet.PrimaryPart.CFrame.LookVector * 2
	dropPosition = Vector3.new(dropPosition.X, 0.5, dropPosition.Z) -- Adjust height to rest on baseplate

	money.Position = dropPosition
	money.CFrame = money.CFrame * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
	money.Anchored = true
	money.CanCollide = false
	money.Parent = workspace.moneyFolder
end

local function moneyTouched(hit, moneyValue, money)
	if not hit.Parent:FindFirstChild("Humanoid") then return false end

	local plr = game.Players:GetPlayerFromCharacter(hit.Parent)
	if not plr then print("no player"); return false end

	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyStat = leaderstats and leaderstats:FindFirstChild("Money")
	if not moneyStat then return false end

	moneyStat.Value += moneyValue.Value
	replicatedStorage.remoteEvents.newMoneyRemoteEvent:FireClient(plr, moneyValue.Value)
	money:Destroy()
	return true
end

local function connectMoneyEvent()
	workspace.moneyFolder.ChildAdded:Connect(function(money)
		local moneyValue = money:FindFirstChildWhichIsA("IntValue")
		if not moneyValue then return end
		local alreadyTouched = false
		money.Touched:Connect(function(hit)
			if not alreadyTouched then
				alreadyTouched = moneyTouched(hit, moneyValue, money)
			end
		end)
	end)
end

-- Main System
local function initializePetSystem()
	-- Start stat depletion coroutines
	task.spawn(function()
		depleteStat("hunger", sliders.hunger, labels.hunger)
	end)

	task.spawn(function()
		depleteStat("thirst", sliders.thirst, labels.thirst)
	end)

	task.spawn(function()
		depleteStat("happiness", sliders.happiness, labels.happiness)
	end)

	-- Update depletion rates based on happiness
	runService.Heartbeat:Connect(updateDepletionRates)
	task.spawn(function()
		while wait(CONFIG.moneyDropTime) and not workspace.pet:FindFirstChild("Dead") do
			dropMoney()
		end
	end)
	
	connectMoneyEvent()
end

-- Remote Events
replicatedStorage.remoteEvents.statRestoredRemoteEvent.OnServerEvent:Connect(function(clientPlayer, amount, statName)
	if clientPlayer == player then
		restoreStatAmount(amount, statName)
	end
end)

-- Initialize the system
initializePetSystem()
