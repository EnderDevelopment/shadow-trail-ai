-- Place this Script inside the ChaserNPC model.
-- The model must contain a Humanoid and HumanoidRootPart.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")
local root = npc:WaitForChild("HumanoidRootPart")
local homePosition = root.Position

local CONFIG = {
	DetectionRange = 50,
	LoseTargetRange = 62,
	RequireLineOfSight = true,
	WalkSpeed = 10,
	ChaseSpeed = 15,
	StaminaMax = 90,
	StaminaDrainPerSecond = 1,
	StaminaRegenPerSecond = 1.4,
	WanderRadius = 45,
	WanderPauseMin = 1,
	WanderPauseMax = 3,
	RepathTargetMoved = 7,
	StuckSeconds = 2.5,
	TeleportAfterUnreachable = 10,
	TeleportCooldown = 20,
	TeleportMinDistance = 20,
	TeleportMaxDistance = 30,
	FlashlightNames = { flashlight = true, torch = true },
}

local random = Random.new()
local stamina = CONFIG.StaminaMax
local targetPlayer = nil
local activePath = nil
local waypoints = {}
local waypointIndex = 0
local blockedConnection = nil
local needsRepath = true
local lastPathTarget = nil
local lastProgressPosition = root.Position
local lastProgressTime = os.clock()
local unreachableSince = nil
local lastTeleportTime = -math.huge
local nextWanderTime = 0
local wanderGoal = nil
local lastMoveWaypoint = nil

local function disconnectBlocked()
	if blockedConnection then
		blockedConnection:Disconnect()
		blockedConnection = nil
	end
end

local function hasLineOfSight(character)
	local targetRoot = character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc, character }
	local direction = targetRoot.Position - root.Position
	local hit = Workspace:Raycast(root.Position, direction, params)
	return hit == nil
end

local function characterIsSprinting(player, character)
	return player:GetAttribute("IsSprinting") == true
		or player:GetAttribute("Sprinting") == true
		or character:GetAttribute("IsSprinting") == true
		or character:GetAttribute("Sprinting") == true
end

local function characterHasFlashlight(character)
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") then
			local toolName = string.lower(item.Name)
			local recognized = CONFIG.FlashlightNames[toolName] == true
			local isOn = item:GetAttribute("IsOn") == true
				or item:GetAttribute("FlashlightOn") == true
				or item:GetAttribute("Enabled") == true
			if recognized and isOn then return true end
		end
	end
	return character:GetAttribute("FlashlightOn") == true
end

local function canSeePlayer(player, maxRange)
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not playerHumanoid or playerHumanoid.Health <= 0 then return nil end
	if (playerRoot.Position - root.Position).Magnitude > maxRange then return nil end
	if CONFIG.RequireLineOfSight and not hasLineOfSight(character) then return nil end
	return character, playerRoot
end

local function findTarget()
	local nearestPlayer, nearestDistance = nil, CONFIG.DetectionRange
	for _, player in ipairs(Players:GetPlayers()) do
		local character, playerRoot = canSeePlayer(player, CONFIG.DetectionRange)
		if character then
			local distance = (playerRoot.Position - root.Position).Magnitude
			if distance < nearestDistance then
				nearestPlayer, nearestDistance = player, distance
			end
		end
	end
	return nearestPlayer
end

local function makePath(destination)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = true,
		WaypointSpacing = 4,
	})
	local ok = pcall(function() path:ComputeAsync(root.Position, destination) end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		disconnectBlocked()
		activePath, waypoints, waypointIndex = nil, {}, 0
		needsRepath = false
		return false
	end
	disconnectBlocked()
	activePath = path
	waypoints = path:GetWaypoints()
	waypointIndex = (#waypoints > 1) and 2 or 1
	needsRepath = false
	blockedConnection = path.Blocked:Connect(function(blockedIndex)
		if blockedIndex >= waypointIndex then needsRepath = true end
	end)
	return #waypoints > 0
end

local function steerWander(goal)
	local offset = goal - root.Position
	local direction = offset.Magnitude > 1 and offset.Unit or Vector3.new(1, 0, 0)
	local influence = Vector3.zero
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		if playerRoot then
			local delta = playerRoot.Position - root.Position
			if delta.Magnitude <= CONFIG.DetectionRange and (characterHasFlashlight(character) or characterIsSprinting(player, character)) then
				local away = -Vector3.new(delta.X, 0, delta.Z)
				if away.Magnitude > 0 then influence += away.Unit end
			end
		end
	end
	if influence.Magnitude > 0 then direction = (direction + influence.Unit * 0.3).Unit end
	return root.Position + direction * math.min(12, math.max(5, offset.Magnitude))
end

local function chooseWanderGoal()
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = random:NextNumber(8, CONFIG.WanderRadius)
	local candidate = homePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc }
	local ground = Workspace:Raycast(candidate + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return ground and ground.Position or candidate
end

local function tryTeleportNear(playerRoot)
	if os.clock() - lastTeleportTime < CONFIG.TeleportCooldown then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc, playerRoot.Parent }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { npc, playerRoot.Parent }
	for _ = 1, 10 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(CONFIG.TeleportMinDistance, CONFIG.TeleportMaxDistance)
		local point = playerRoot.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local floor = Workspace:Raycast(point + Vector3.new(0, 35, 0), Vector3.new(0, -100, 0), params)
		if floor and floor.Normal.Y > 0.65 then
			local destination = floor.Position + Vector3.new(0, 3, 0)
			local parts = Workspace:GetPartBoundsInBox(CFrame.new(destination), Vector3.new(4, 6, 4), overlap)
			if #parts == 0 then
				npc:PivotTo(CFrame.lookAt(destination, Vector3.new(playerRoot.Position.X, destination.Y, playerRoot.Position.Z)))
				humanoid:MoveTo(destination)
				lastTeleportTime = os.clock()
				lastProgressPosition, lastProgressTime = root.Position, os.clock()
				needsRepath = true
				return true
			end
		end
	end
	return false
end

local function updateMovement(destination, now)
	if (root.Position - lastProgressPosition).Magnitude >= 1.5 then
		lastProgressPosition, lastProgressTime = root.Position, now
	elseif now - lastProgressTime >= CONFIG.StuckSeconds then
		needsRepath = true
	end
	if needsRepath or not activePath or not lastPathTarget or (destination - lastPathTarget).Magnitude >= CONFIG.RepathTargetMoved then
		lastPathTarget = destination
		if not makePath(destination) then
			humanoid:MoveTo(destination)
			return false
		end
	end
	local waypoint = waypoints[waypointIndex]
	if not waypoint then needsRepath = true return false end
	if (root.Position - waypoint.Position).Magnitude <= 3.5 then
		waypointIndex += 1
		waypoint = waypoints[waypointIndex]
	end
	if waypoint and waypoint ~= lastMoveWaypoint then
		if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
		humanoid:MoveTo(waypoint.Position)
		lastMoveWaypoint = waypoint
	end
	return waypoint ~= nil
end

while npc.Parent and humanoid.Health > 0 do
	local now = os.clock()
	local detected = findTarget()
	if detected then
		targetPlayer = detected
	elseif targetPlayer then
		local character = targetPlayer.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not playerRoot or (playerRoot.Position - root.Position).Magnitude > CONFIG.LoseTargetRange then
			targetPlayer, unreachableSince, needsRepath = nil, nil, true
		end
	end

	if targetPlayer and stamina > 0 then
		local character = targetPlayer.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		if playerRoot and playerHumanoid and playerHumanoid.Health > 0 and (playerRoot.Position - root.Position).Magnitude <= CONFIG.LoseTargetRange then
			humanoid.WalkSpeed = CONFIG.ChaseSpeed
			stamina = math.max(0, stamina - CONFIG.StaminaDrainPerSecond * 0.15)
			if updateMovement(playerRoot.Position, now) then
				unreachableSince = nil
			else
				unreachableSince = unreachableSince or now
				if now - unreachableSince >= CONFIG.TeleportAfterUnreachable and tryTeleportNear(playerRoot) then unreachableSince = nil end
			end
		else
			targetPlayer, unreachableSince, needsRepath = nil, nil, true
		end
	else
		stamina = math.min(CONFIG.StaminaMax, stamina + CONFIG.StaminaRegenPerSecond * 0.15)
		humanoid.WalkSpeed = CONFIG.WalkSpeed
		if targetPlayer and stamina <= 0 then targetPlayer = nil end
		if not wanderGoal or (root.Position - wanderGoal).Magnitude < 4 or now >= nextWanderTime then
			wanderGoal = chooseWanderGoal()
			nextWanderTime = now + random:NextNumber(CONFIG.WanderPauseMin, CONFIG.WanderPauseMax)
			needsRepath = true
		end
		updateMovement(steerWander(wanderGoal), now)
	end
	RunService.Heartbeat:Wait()
	task.wait(0.14)
end

disconnectBlocked()
