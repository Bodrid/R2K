-- Server: owns the rules. It decides who holds the ball, shot results, steals and points.
-- While someone holds the ball, the server only stores WHO (the "Holder" attribute);
-- every client draws the ball in that player's hand itself, so dribbling never waits on the network.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hoops = require(ReplicatedStorage.Hoops)

local RIM = Vector3.new(0, Hoops.RIM_Y, -20)
local CENTER = Vector3.new(0, Hoops.FLOOR_Y + 3, 0)
local FLAT = Vector3.new(1, 0, 1)

local function new(className, props)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	return inst
end

-- Court (built in code so every position lives in this file)
local wood, orange = Color3.fromRGB(200, 150, 95), Color3.fromRGB(255, 110, 20)
new("Part", { Name = "Court", Anchored = true, Size = Vector3.new(60, 1, 50), Position = Vector3.new(0, Hoops.FLOOR_Y - 0.5, -5), Color = wood, Material = Enum.Material.WoodPlanks, Parent = workspace })
new("SpawnLocation", { Anchored = true, CanCollide = false, Transparency = 1, Size = Vector3.new(6, 0.2, 6), Position = CENTER - Vector3.new(0, 2.9, 0), Parent = workspace })
new("Part", { Name = "Pole", Anchored = true, Size = Vector3.new(0.6, Hoops.RIM_Y + 2, 0.6), Position = Vector3.new(0, (Hoops.RIM_Y + 2) / 2, RIM.Z - Hoops.RIM_RADIUS - 1.1), Color = Color3.new(0.2, 0.2, 0.2), Parent = workspace })
new("Part", { Name = "Backboard", Anchored = true, Size = Vector3.new(7, 4.5, 0.3), Position = RIM + Vector3.new(0, 1.8, -(Hoops.RIM_RADIUS + 0.6)), Color = Color3.new(1, 1, 1), Transparency = 0.3, Parent = workspace })
for i = 1, 12 do -- rim as a ring of solid segments so misses bounce off the iron for real
	local a = i / 12 * math.pi * 2
	new("Part", { Name = "Rim", Anchored = true, Size = Vector3.new(0.2, 0.2, 0.85), CFrame = CFrame.new(RIM + Vector3.new(math.cos(a), 0, math.sin(a)) * Hoops.RIM_RADIUS) * CFrame.Angles(0, -a, 0), Color = orange, Parent = workspace })
end

-- Persistent so instance streaming never removes the ball on any client.
local ballModel = new("Model", { Name = "Basketball", ModelStreamingMode = Enum.ModelStreamingMode.Persistent })
local ball = new("Part", {
	Name = "Ball",
	Shape = Enum.PartType.Ball,
	Size = Vector3.one * Hoops.BALL_RADIUS * 2,
	Color = orange,
	CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.75, 1, 100), -- bouncy, and its bounce wins over the floor's
	Position = CENTER,
	Parent = ballModel,
})
ballModel.Parent = workspace

local action = new("RemoteEvent", { Name = "Action", Parent = ReplicatedStorage })

local shootStarts = {} -- [player] = os.clock() when they started holding shoot
local nextSteal = {} -- [player] = os.clock() when they may try again
local lastShot = nil -- { player, points } until the ball is caught
local pickupLockUntil = 0
local prevY = ball.Position.Y

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") or nil
end

local function holder()
	local id = ball:GetAttribute("Holder")
	return id and Players:GetPlayerByUserId(id)
end

local function give(player)
	ball.Anchored = true
	ball.CanCollide = false
	ball:SetAttribute("Hand", "Right") -- set before Holder; clients reset to Right on a new holder too
	ball:SetAttribute("Holder", player.UserId)
	lastShot = nil
end

local function release(position, velocity)
	ball:SetAttribute("Holder", nil)
	ball.Anchored = false
	ball.CanCollide = true
	ball.CFrame = CFrame.new(position)
	ball.AssemblyLinearVelocity = velocity
	ball:SetNetworkOwner(nil) -- server simulates loose balls, so a client can't fake a make
	pickupLockUntil = os.clock() + Hoops.PICKUP_LOCK
	prevY = position.Y
end

local function shoot(player, root, holdTime)
	local dist = ((root.Position - RIM) * FLAT).Magnitude
	local contested = false
	for _, other in Players:GetPlayers() do
		local r = other ~= player and rootOf(other)
		if r and (r.Position - root.Position).Magnitude <= Hoops.CONTEST_RANGE then
			contested = true
		end
	end

	local target = RIM
	if math.random() >= Hoops.makeChance(Hoops.shotQuality(holdTime), dist, contested) then
		local a = math.random() * math.pi * 2
		target += Vector3.new(math.cos(a), 0, math.sin(a)) * Hoops.RIM_RADIUS -- aim at the iron: a real clank and rebound
	end

	lastShot = { player = player, points = dist >= Hoops.THREE_DIST and 3 or 2 }
	local from = root.Position + Vector3.new(0, 3.5, 0) -- above the head so the ball clears the shooter
	local t = Hoops.flightTime(dist)
	release(from, Hoops.launchVelocity(from, target, t, Vector3.new(0, -workspace.Gravity, 0)))
end

action.OnServerEvent:Connect(function(player, kind, value)
	local root = rootOf(player)
	if not root then
		return
	end
	local h = holder()

	if kind == "cross" then
		if h == player and (value == "Left" or value == "Right") then
			ball:SetAttribute("Hand", value)
		end
	elseif kind == "shootStart" then
		if h == player then
			shootStarts[player] = os.clock()
		end
	elseif kind == "shoot" then
		local started = shootStarts[player]
		shootStarts[player] = nil
		if h ~= player or not started then
			return
		end
		-- Trust the client's timing so lag doesn't ruin releases, unless it's far from what the server saw.
		-- shortcut: a cheater can still claim perfect within HOLD_TOLERANCE, tighten or add anti-cheat before launch
		local serverHold = os.clock() - started
		if typeof(value) ~= "number" or not (math.abs(value - serverHold) <= Hoops.HOLD_TOLERANCE) then
			value = serverHold
		end
		shoot(player, root, value)
	elseif kind == "steal" then
		if h and h ~= player and os.clock() >= (nextSteal[player] or 0) then
			nextSteal[player] = os.clock() + Hoops.STEAL_COOLDOWN
			local hRoot = rootOf(h)
			-- Dice roll within range, like 2K: hides lag better than exact hand hitboxes.
			if hRoot and (hRoot.Position - root.Position).Magnitude <= Hoops.STEAL_RANGE and math.random() < Hoops.STEAL_CHANCE then
				give(player)
			end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	if ball:GetAttribute("Holder") then
		local h = holder()
		if not (h and rootOf(h)) then
			release(CENTER, Vector3.zero) -- holder left or died
		end
		return
	end

	local pos = ball.Position
	if lastShot and prevY > RIM.Y and pos.Y <= RIM.Y and ((pos - RIM) * FLAT).Magnitude < Hoops.RIM_RADIUS then
		local stats = lastShot.player:FindFirstChild("leaderstats")
		if stats then
			stats.Points.Value += lastShot.points
		end
		lastShot = nil
	end
	prevY = pos.Y

	if pos.Y < Hoops.FLOOR_Y - 20 then
		release(CENTER, Vector3.zero) -- fell off the map
	elseif os.clock() >= pickupLockUntil then
		for _, p in Players:GetPlayers() do
			local r = rootOf(p)
			if r and (r.Position - pos).Magnitude <= Hoops.PICKUP_RANGE then
				give(p)
				break
			end
		end
	end
end)

local function addStats(player)
	local stats = new("Folder", { Name = "leaderstats" })
	new("IntValue", { Name = "Points", Parent = stats })
	stats.Parent = player
end
Players.PlayerAdded:Connect(addStats)
for _, player in Players:GetPlayers() do -- Play Solo can add the player before this script runs
	addStats(player)
end

Players.PlayerRemoving:Connect(function(player)
	shootStarts[player] = nil
	nextSteal[player] = nil
end)
