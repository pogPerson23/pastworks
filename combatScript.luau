-- LOCAL SCRIPT

local rps = game:GetService("ReplicatedStorage")

local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
local playerGui = player.PlayerGui
local textLabel = playerGui.ScreenGui.Frame.TextLabel

local debounce = false

mouse.Button1Down:Connect(function()
	if debounce then return end 
	debounce = true
	rps.CombatFolder.SkillEvent:FireServer("punch")
	wait(0.5)
	debounce = false
end)

mouse.Button2Down:Connect(function()
	rps.CombatFolder.SkillEvent:FireServer("block")
end)

mouse.Button2Up:Connect(function()
	rps.CombatFolder.BlockEndEvent:FireServer()
end)

rps.CombatFolder.ChangeOutlineColourEvent.OnClientEvent:Connect(function(typeOfLabel, onoroff)
	if onoroff then
		playerGui.ScreenGui.Frame:FindFirstChild(typeOfLabel).UIStroke.Color = Color3.fromRGB(1, 255, 255)
	else
		playerGui.ScreenGui.Frame:FindFirstChild(typeOfLabel).UIStroke.Color = Color3.fromRGB(0, 0, 0)
	end
	
end)

task.spawn(function()
	while wait() do
		textLabel.Text = tostring(game.Players.LocalPlayer.Character:WaitForChild("Stamina").Value)
	end
end)

-- SERVER SCRIPT

-- services
local rps = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local dataStoreService = game:GetService("DataStoreService")

--datastore
local KoDataStore = dataStoreService:GetDataStore("KoDataStore")

-- server variables for players
local stamina = {}
local blocking = {}
local punching = {}
local punchAnim = {}
local blockAnim = {}

-- LOAD PLAYER KOS FROM DATASTORE
function loadData(player: Player)
	local key = player.UserId
	local success, data = pcall(function()
		return KoDataStore:GetAsync(key) -- player data
	end)
	
	if success then
		if data then
			if player:FindFirstChild("leaderstats") and player:FindFirstChild("leaderstats"):FindFirstChild("KOs") then
				player.leaderstats.KOs.Value = data -- setting data to leaderstats
				print("Successfully loaded data for " .. player.Name)
			end
		else
			print("Loaded data but data was empty for " .. player.Name)
		end
	else
		warn("Failed to load data!")
	end
end

-- SAVE PLAYER DATA TO DATASTORE

function saveData(player: Player)
	local key = player.UserId
	local attemptCount = 0
	local success, err
	repeat
		attemptCount += 1
		success, err = pcall(function()
			if player:FindFirstChild("leaderstats") and player:FindFirstChild("leaderstats"):FindFirstChild("KOs") then
				KoDataStore:SetAsync(key, player.leaderstats.KOs.Value) -- set datastore value for player to stats in leaderstats
			end
		end)
		if err then 
			print("Failed to save " .. player.Name .. "'s data on attempt " .. attemptCount .. "Retrying in 6 seconds...")
			wait(6)
		end
		
	until success or attemptCount == 5
	if success then
		print("Successfully saved data for " .. player.Name)
	else
		print("Failed to save data for player " .. player.Name .. " , error message: " .. err) 
	end
end

function updateStamina(player)
	task.spawn(function()
		while player and player.Parent and player.Character and wait(0.5) do
			if (punching[player.Name]) or (player.Character and player.Character:FindFirstChild("hit")) then
				continue 
			end
			if stamina[player.Name] and stamina[player.Name].Value < 100 then
				stamina[player.Name].Value = math.min(stamina[player.Name].Value + 5, 100) -- adding stamina but not letting go over 100
			end
		end
	end)
end

function isAnimationPlaying(animationTrack, humanoid)
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		if track.Animation == animationTrack.Animation then
			return true
		end
	end
	return false
end

game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		local notMovingAnim = humanoid:LoadAnimation(script.notmoving)
		
		local staminaInstance = Instance.new("IntValue", character)
		staminaInstance.Name = "Stamina"
		staminaInstance.Value = 100
		stamina[player.Name] = staminaInstance
		print("Stamina made for " .. player.Name)
		
		humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
			local moveDirection = humanoid.MoveDirection

			if moveDirection.Magnitude == 0 then -- if player is not moving anywhere
				if not isAnimationPlaying(notMovingAnim, humanoid) then
					notMovingAnim:Play()
				end
			else
				notMovingAnim:Stop() -- else stop the not moving animation
			end
		end)
	end)
	
	loadData(player) -- load player datastore
	updateStamina(player) -- start updating player stamina
end)

rps.CombatFolder.SkillEvent.OnServerEvent:Connect(function(player, typeOfSkill)
	if not stamina[player.Name] then return end

	if typeOfSkill == "punch" and not blocking[player.Name] and not punching[player.Name] then -- if player is not already punching or blocking 
		if stamina[player.Name].Value >= 20 then
			print("player punched and over stamina is over 20")
			punching[player.Name] = true
			punchAnim[player.Name] = player.Character:FindFirstChild("Humanoid"):LoadAnimation(script.PunchAnimation)
			punchAnim[player.Name]:Play()
			rps.CombatFolder.ChangeOutlineColourEvent:FireClient(player, "PunchLabel", true) -- change ui colours

			stamina[player.Name].Value = math.max(stamina[player.Name].Value - 20, 0) -- take away stamina but make sure it doesnt go below 0

			local character = player.Character
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local forwardOffset = 1.5 -- how many studs the punch radius should be infront of the hrp centre
			local cubeSize = Vector3.new(5, 8, 5)
			local centerPosition = rootPart.Position + (rootPart.CFrame.LookVector * forwardOffset) -- centre of region 3 position infront of player in their facing direction with forward offset
			local minCorner = centerPosition - (cubeSize / 2)
			local maxCorner = centerPosition + (cubeSize / 2) -- getting the corner positons of the region 3 to make the cube shape
			local region = Region3.new(minCorner, maxCorner) -- making region 3

			for _, v in workspace:FindPartsInRegion3(region, player.Character, math.huge) do -- checking for parts in region 3 with no limit on how many parts can be checked
				if v.Parent:FindFirstChild("Humanoid") or v:FindFirstChild("Humanoid") then
					local enemyPlayer = (v:IsA("Model") and v) or v.Parent -- get the enemy player from either a body part or the player model itself
					if enemyPlayer and enemyPlayer:FindFirstChild("Humanoid") then
						if enemyPlayer:FindFirstChild("blocking") then 
							print("enemy player is blocking")
							local enemyStamina = enemyPlayer:FindFirstChild("Stamina")
							if enemyStamina then
								enemyStamina.Value = math.max(enemyStamina.Value - 25, 0) -- take away stamina making sure it doesnt exceed 0
								break
							end
						else
							enemyPlayer.Humanoid:TakeDamage(25) -- make enemy player take damage
							if enemyPlayer.Humanoid.Health <= 0 then
								print("enemy died")
								if player:FindFirstChild("leaderstats") and player:FindFirstChild("leaderstats"):FindFirstChild("KOs") then
									player.leaderstats.KOs.Value += 1 -- add 1 to KOs
									print("successfully added ko to player stats")
								end
							end
							local hit = Instance.new("BoolValue", enemyPlayer) -- add a hit instance to player so they cant regenerate stamina for .5 seconds
							hit.Name = "hit"
							print("hit instance successfully made")
							task.wait(0.5)
							hit:Destroy() -- destroy hit instance so player can regen stamina again
							print("hit successfully destroyed")
							break
						end
					end
				end
			end
			punching[player.Name] = false
			rps.CombatFolder.ChangeOutlineColourEvent:FireClient(player, "PunchLabel", false) -- change colour of ui
		end
	elseif typeOfSkill == "block" and not punching[player.Name] and not blocking[player.Name] then
		if stamina[player.Name].Value >= 10 then
			print("player blocking and stamina over 10")
			blocking[player.Name] = true
			rps.CombatFolder.ChangeOutlineColourEvent:FireClient(player, "BlockLabel", true) -- change colour of ui
			blockAnim[player.Name] = player.Character:FindFirstChild("Humanoid"):LoadAnimation(script.BlockAnimation) -- make them do blocking animation
			blockAnim[player.Name]:Play()
			local blockingBool = Instance.new("BoolValue", player.Character) -- making blocking instance to show player is blocking
			blockingBool.Name = "blocking"
		end
	end

	stamina[player.Name].Changed:Connect(function()
		if stamina[player.Name].Value <= 0 and blocking[player.Name] then -- if player's stamina is 0 then stop their blocking 
			print("player stamina broken, stopping block")
			if blockAnim[player.Name] then
				blockAnim[player.Name]:Stop() -- stop the blocking animation
			end
			blocking[player.Name] = false
			local blockingInstance = player.Character:FindFirstChild("blocking")
			if blockingInstance then blockingInstance:Destroy() end -- destroy the blocking instnce
			rps.CombatFolder.ChangeOutlineColourEvent:FireClient(player, "BlockLabel", false) -- change gui colour
			print("block ended")
		end
	end)
end)

rps.CombatFolder.BlockEndEvent.OnServerEvent:Connect(function(player) -- player stops holding down right click
	print("block key stopped being held, block ending")
	if blocking[player.Name] then
		blocking[player.Name] = false
		if blockAnim[player.Name] then
			blockAnim[player.Name]:Stop() -- stop blocking animation
		end
		local blockingInstance = player.Character:FindFirstChild("blocking")
		if blockingInstance then blockingInstance:Destroy() end -- blocking instance destroyed
		rps.CombatFolder.ChangeOutlineColourEvent:FireClient(player, "BlockLabel", false) -- change gui colour
		print("block ended")
	end
end)

game.Players.PlayerRemoving:Connect(function(player) -- remove all of their server variables to reduce lag
	saveData(player) -- save data to datastore
	stamina[player.Name] = nil
	blocking[player.Name] = nil
	punching[player.Name] = nil
	punchAnim[player.Name] = nil
	blockAnim[player.Name] = nil
	print("cleared player data from sevrer")
end)

game:BindToClose(function() -- on the scenario the server crashes or closes save players data
	for _, player in game.Players:GetPlayers() do
		saveData(player)
		print("saved " .. player.Name .. "'s data")
	end
end)
