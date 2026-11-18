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
local reaching = {} -- [player] = os.clock() until their reach stays live
local nextBlock = {} -- [player] = os.clock() when they may block again
local blocking = {} -- [player] = os.clock() until their block stays live
local lastShot = nil -- { player, points } until the ball is caught
local pickupLockUntil, pickupLockPlayer = 0, nil
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

-- Held-ball state lives in attributes with server-clock times, so everyone computes the same ball (Hoops.ballSpot).
-- Set before Holder, so a client sees a new possession already in sync.
local function give(player)
	ball.Anchored = true
	ball.CanCollide = false
	ball:SetAttribute("Hand", "Right")
	ball:SetAttribute("FromHand", "Right")
	ball:SetAttribute("CrossAt", workspace:GetServerTimeNow() - Hoops.CROSS_TIME) -- dribble starts at the top
	ball:SetAttribute("GatherAt", nil)
	ball:SetAttribute("Holder", player.UserId)
	lastShot = nil
	table.clear(reaching)
end

local function heldSpot(hRoot)
	return Hoops.ballSpot(hRoot.CFrame, ball:GetAttribute("Hand"), ball:GetAttribute("FromHand"), ball:GetAttribute("CrossAt"), ball:GetAttribute("GatherAt"), workspace:GetServerTimeNow())
end

-- lockOnly: lock just that player out of the pickup (passes, pokes); nil locks everyone (shots).
local function release(position, velocity, lockOnly)
	table.clear(reaching)
	ball:SetAttribute("GatherAt", nil)
	ball:SetAttribute("Holder", nil)
	ball.Anchored = false
	ball.CanCollide = true
	ball.CFrame = CFrame.new(position)
	ball.AssemblyLinearVelocity = velocity
	ball:SetNetworkOwner(nil) -- server simulates loose balls, so a client can't fake a make
	pickupLockUntil, pickupLockPlayer = os.clock() + Hoops.PICKUP_LOCK, lockOnly
	prevY = position.Y
end

-- A block knocks the ball away from the blocker. Nobody can grab it for a moment, and a shot can't score.
local function swat(position, blockerRoot)
	lastShot = nil
	table.clear(blocking)
	release(position, blockerRoot.CFrame.LookVector * Hoops.SWAT_SPEED + Vector3.new(0, 8, 0))
end

-- The player's root if their reach or block (in `live`) is still going; otherwise forget it.
local function liveRoot(live, player)
	local r = os.clock() <= live[player] and rootOf(player)
	if not r then
		live[player] = nil
	end
	return r
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
	local from = Hoops.gatherSpot(root.CFrame) -- same spot clients draw the windup, so the ball doesn't jump
	local t = Hoops.flightTime(dist)
	release(from, Hoops.launchVelocity(from, target, t, Vector3.new(0, -workspace.Gravity, 0)))
end

action.OnServerEvent:Connect(function(player, kind, value, at)
	local root = rootOf(player)
	if not root then
		return
	end
	local h = holder()

	if kind == "cross" then
		local hand = ball:GetAttribute("Hand")
		if h == player and (value == "Left" or value == "Right") and value ~= hand then
			-- Use the client's start time so its crossover lines up with ours, within MAX_BACKDATE (covers ping).
			-- Never overlap the last crossover.
			local now = workspace:GetServerTimeNow()
			local t = if typeof(at) == "number" and at == at then math.clamp(at, now - Hoops.MAX_BACKDATE, now) else now
			ball:SetAttribute("FromHand", hand)
			ball:SetAttribute("CrossAt", math.max(t, ball:GetAttribute("CrossAt") + Hoops.CROSS_TIME))
			ball:SetAttribute("Hand", value)
		end
	elseif kind == "shootStart" then
		if h == player then
			shootStarts[player] = os.clock()
			ball:SetAttribute("GatherAt", workspace:GetServerTimeNow()) -- so everyone else sees the gather
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
	elseif kind == "pass" then
		if h == player then
			-- A pass is a real physics ball, so anyone near its path can pick it off.
			-- shortcut: passes go where you face; aim at a teammate once teams exist
			local from = root.CFrame * Vector3.new(0, 0.5, -1.5)
			local to = root.CFrame * Vector3.new(0, 0.5, -Hoops.PASS_DIST)
			release(from, Hoops.launchVelocity(from, to, Hoops.PASS_TIME, Vector3.new(0, -workspace.Gravity, 0)), player)
		end
	elseif kind == "steal" then
		-- A reach only counts near the handler. It stays live for REACH_TIME, checked every frame below.
		local hRoot = h and h ~= player and rootOf(h)
		if hRoot and (hRoot.Position - root.Position).Magnitude <= Hoops.STEAL_RANGE and os.clock() >= (nextSteal[player] or 0) then
			nextSteal[player] = os.clock() + Hoops.STEAL_COOLDOWN
			reaching[player] = os.clock() + Hoops.REACH_TIME
		end
	elseif kind == "block" then
		if h ~= player and os.clock() >= (nextBlock[player] or 0) then
			nextBlock[player] = os.clock() + Hoops.BLOCK_COOLDOWN - 0.1 -- slack so the client's own cooldown never disagrees
			player.Character:SetAttribute("BlockAt", workspace:GetServerTimeNow()) -- everyone plays the animation
			-- Only near the ball handler (or a shooter while the shot is up) does the ball go live for contact,
			-- until the animation ends. Anywhere else it's just the animation.
			local carrier = h or (lastShot and lastShot.player)
			local cRoot = carrier and carrier ~= player and rootOf(carrier)
			if cRoot and (cRoot.Position - root.Position).Magnitude <= Hoops.BLOCK_RANGE then
				blocking[player] = os.clock() + Hoops.BLOCK_TIME
			end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	if ball:GetAttribute("Holder") then
		local h = holder()
		local hRoot = h and rootOf(h)
		if not hRoot then
			release(CENTER, Vector3.zero) -- holder left or died
			return
		end
		-- Live blocks and reaches: the server knows exactly where the ball is (side, bounce height, crossover,
		-- gather), so only real contact counts.
		local spot = heldSpot(hRoot)
		for p in blocking do
			local r = liveRoot(blocking, p)
			if r and p ~= h and Hoops.blocks(r.CFrame, spot) then
				swat(spot, r)
				return
			end
		end
		for p in reaching do
			local r = liveRoot(reaching, p)
			if r and Hoops.reaches(r.CFrame, spot) then
				-- A steal knocks it loose away from the handler; whoever gets there first keeps it.
				release(spot, ((spot - hRoot.Position) * FLAT).Unit * Hoops.POKE_SPEED + Vector3.new(0, 10, 0), h)
				return
			end
		end
		return
	end

	local pos = ball.Position
	if lastShot then -- a shot in the air: live blocks check contact against the server's own physics ball
		for p in blocking do
			local r = liveRoot(blocking, p)
			if r and p ~= lastShot.player and Hoops.blocks(r.CFrame, pos) then
				swat(pos, r)
				return
			end
		end
	end
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
	else
		local locked = os.clock() < pickupLockUntil
		for _, p in Players:GetPlayers() do
			local r = rootOf(p)
			local lockedOut = locked and (pickupLockPlayer == nil or pickupLockPlayer == p)
			if r and not lockedOut and (r.Position - pos).Magnitude <= Hoops.PICKUP_RANGE then
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
	reaching[player] = nil
	nextBlock[player] = nil
	blocking[player] = nil
end)
