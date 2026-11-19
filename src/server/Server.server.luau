-- Server: owns the rules. It decides who holds the ball, shot results, steals and points.
-- While someone holds the ball, the server only stores WHO (the "Holder" attribute);
-- every client draws the ball in that player's hand itself, so dribbling never waits on the network.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hoops = require(ReplicatedStorage.Hoops)

local RIM = Vector3.new(0, Hoops.RIM_Y, Hoops.RIM_Z)
local CENTER = Vector3.new(0, Hoops.FLOOR_Y + 3, 0)
local FLAT = Vector3.new(1, 0, 1)

local function new(className, props)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	return inst
end

-- Court (built in code so every position lives in this file). Real-proportioned markings, scaled so the
-- three-point arc sits exactly THREE_DIST from the rim, the distance scoring uses.
local wood, paint, apron = Color3.fromRGB(205, 160, 105), Color3.fromRGB(28, 60, 140), Color3.fromRGB(30, 34, 48)
local white, orange, black = Color3.new(1, 1, 1), Color3.fromRGB(255, 110, 20), Color3.fromRGB(15, 15, 18)
local LINE_Y = Hoops.FLOOR_Y + 0.03
local BASELINE, HALF, SIDE_X = RIM.Z - 5.5, 20, 28 -- the baseline sits just behind the backboard, like a real court
local FT_Z, LANE = RIM.Z + 10.5, 6.75 -- free-throw line; half the lane's width

local function decal(name, size, cf, color) -- thin, non-solid markings
	return new("Part", { Name = name, Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Size = size, CFrame = cf, Color = color, Material = Enum.Material.SmoothPlastic, Parent = workspace })
end
local function line(x1, z1, x2, z2) -- a floor line
	local a, b = Vector3.new(x1, LINE_Y, z1), Vector3.new(x2, LINE_Y, z2)
	decal("Line", Vector3.new(0.3, 0.05, (b - a).Magnitude + 0.3), CFrame.lookAt((a + b) / 2, b), white)
end
local function arc(cx, cz, radius, fromDeg, toDeg) -- a floor arc in short straight pieces (0° = +X, 90° = toward half court)
	local steps = math.ceil(math.abs(toDeg - fromDeg) / 4)
	local step = (toDeg - fromDeg) / steps
	for i = 0, steps - 1 do
		local a = math.rad(fromDeg + (i + 0.5) * step)
		decal("Line", Vector3.new(0.3, 0.05, radius * math.rad(math.abs(step)) + 0.05), CFrame.new(cx + math.cos(a) * radius, LINE_Y, cz + math.sin(a) * radius) * CFrame.Angles(0, -a, 0), white)
	end
end

new("Part", { Name = "Apron", Anchored = true, Size = Vector3.new(90, 1, 80), Position = Vector3.new(0, Hoops.FLOOR_Y - 0.52, -5), Color = apron, Material = Enum.Material.SmoothPlastic, Parent = workspace })
new("Part", { Name = "Court", Anchored = true, Size = Vector3.new(SIDE_X * 2, 1, HALF - BASELINE), Position = Vector3.new(0, Hoops.FLOOR_Y - 0.5, (HALF + BASELINE) / 2), Color = wood, Material = Enum.Material.WoodPlanks, Parent = workspace })
decal("Paint", Vector3.new(LANE * 2, 0.02, FT_Z - BASELINE), CFrame.new(0, Hoops.FLOOR_Y + 0.01, (FT_Z + BASELINE) / 2), paint)
line(-SIDE_X, BASELINE, SIDE_X, BASELINE) -- baseline
line(-SIDE_X, HALF, SIDE_X, HALF) -- half court
line(-SIDE_X, BASELINE, -SIDE_X, HALF) -- sidelines
line(SIDE_X, BASELINE, SIDE_X, HALF)
line(-LANE, BASELINE, -LANE, FT_Z) -- lane
line(LANE, BASELINE, LANE, FT_Z)
line(-LANE, FT_Z, LANE, FT_Z) -- free-throw line
arc(0, FT_Z, 5, 0, 180) -- free-throw circle
arc(RIM.X, RIM.Z, 3.4, 0, 180) -- restricted area
arc(0, HALF, 5, 180, 360) -- center circle
-- Three-point line: exactly THREE_DIST from the rim, baseline to baseline.
local corner = math.deg(math.asin((BASELINE - RIM.Z) / Hoops.THREE_DIST))
arc(RIM.X, RIM.Z, Hoops.THREE_DIST, corner, 180 - corner)
new("SpawnLocation", { Anchored = true, CanCollide = false, Transparency = 1, Size = Vector3.new(6, 0.2, 6), Position = CENTER - Vector3.new(0, 2.9, 0), Parent = workspace })

-- Hoop: padded pole, backboard with a border and shooter's square, solid rim.
local poleZ = RIM.Z - Hoops.RIM_RADIUS - 1.1
new("Part", { Name = "Pole", Anchored = true, Size = Vector3.new(0.6, Hoops.RIM_Y + 2, 0.6), Position = Vector3.new(0, (Hoops.RIM_Y + 2) / 2, poleZ), Color = Color3.fromRGB(45, 45, 52), Material = Enum.Material.Metal, Parent = workspace })
new("Part", { Name = "Pad", Anchored = true, Size = Vector3.new(1.2, 5, 1.2), Position = Vector3.new(0, Hoops.FLOOR_Y + 2.5, poleZ), Color = paint, Material = Enum.Material.SmoothPlastic, Parent = workspace })
local board = new("Part", { Name = "Backboard", Anchored = true, Size = Vector3.new(7, 4.5, 0.3), Position = RIM + Vector3.new(0, 1.8, -(Hoops.RIM_RADIUS + 0.6)), Color = Color3.new(1, 1, 1), Transparency = 0.35, Material = Enum.Material.Glass, Parent = workspace })
local function boardLine(width, height, x, y)
	decal("BoardLine", Vector3.new(width, height, 0.02), CFrame.new(board.Position + Vector3.new(x, y, 0.16)), black)
end
boardLine(7, 0.14, 0, 2.18) -- border
boardLine(7, 0.14, 0, -2.18)
boardLine(0.14, 4.5, 3.43, 0)
boardLine(0.14, 4.5, -3.43, 0)
boardLine(2.4, 0.1, 0, -1.65) -- shooter's square, just above the rim
boardLine(2.4, 0.1, 0, 0.15)
boardLine(0.1, 1.8, 1.2, -0.75)
boardLine(0.1, 1.8, -1.2, -0.75)
for i = 1, 12 do -- rim as a ring of solid segments so misses bounce off the iron for real
	local a = i / 12 * math.pi * 2
	new("Part", { Name = "Rim", Anchored = true, Size = Vector3.new(0.2, 0.2, 0.85), CFrame = CFrame.new(RIM + Vector3.new(math.cos(a), 0, math.sin(a)) * Hoops.RIM_RADIUS) * CFrame.Angles(0, -a, 0), Color = orange, Material = Enum.Material.Metal, Parent = workspace })
end

-- Lighting: a bright, clean gym.
local Lighting = game:GetService("Lighting")
Lighting.ClockTime, Lighting.Brightness = 14.5, 2.5
Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 90), Color3.fromRGB(130, 130, 140)
Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = 0.6, 0.6
new("ColorCorrectionEffect", { Contrast = 0.08, Saturation = 0.12, Brightness = 0.02, Parent = Lighting })
new("BloomEffect", { Intensity = 0.25, Size = 18, Threshold = 1.6, Parent = Lighting })

-- Net: criss-crossed strands from the rim down to a narrower ring. Not solid, so made shots fall through.
local NET_DROP, NET_BOTTOM = 2, Hoops.RIM_RADIUS * 0.6
for i = 1, 12 do
	local top = RIM + Vector3.new(math.cos(i / 12 * math.pi * 2), 0, math.sin(i / 12 * math.pi * 2)) * Hoops.RIM_RADIUS
	for _, step in { -0.5, 0.5 } do
		local b = (i + step) / 12 * math.pi * 2
		local bottom = RIM + Vector3.new(math.cos(b) * NET_BOTTOM, -NET_DROP, math.sin(b) * NET_BOTTOM)
		new("Part", { Name = "Net", Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Size = Vector3.new(0.06, 0.06, (bottom - top).Magnitude), CFrame = CFrame.lookAt((top + bottom) / 2, bottom), Color = Color3.new(1, 1, 1), Parent = workspace })
	end
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
local scored = new("RemoteEvent", { Name = "Scored", Parent = ReplicatedStorage }) -- tells everyone to show the score popup

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
	ball:SetAttribute("Move", nil)
	ball:SetAttribute("MoveHand", nil)
	ball:SetAttribute("MoveAt", workspace:GetServerTimeNow()) -- the dribble starts at the top, right now
	ball:SetAttribute("GatherAt", nil)
	ball:SetAttribute("Holder", player.UserId)
	lastShot = nil
	table.clear(reaching)
end

local function heldSpot(hRoot)
	return Hoops.ballSpot(hRoot.CFrame, ball:GetAttribute("Hand"), ball:GetAttribute("Move"), ball:GetAttribute("MoveHand"), ball:GetAttribute("MoveAt"), workspace:GetServerTimeNow())
end

-- Start a dribble move or finish on the ball. Uses the client's start time so its path lines up with ours,
-- within MAX_BACKDATE (covers ping), and never before the last move has finished.
local function startPath(name, at)
	local move = Hoops.MOVES[name]
	local now = workspace:GetServerTimeNow()
	local t = if typeof(at) == "number" and at == at then math.clamp(at, now - Hoops.MAX_BACKDATE, now) else now
	local last = Hoops.MOVES[ball:GetAttribute("Move") or ""]
	t = math.max(t, ball:GetAttribute("MoveAt") + (if last then last.duration else 0))
	local hand = ball:GetAttribute("Hand")
	ball:SetAttribute("MoveHand", hand)
	ball:SetAttribute("Move", name)
	ball:SetAttribute("MoveAt", t)
	ball:SetAttribute("Hand", if move.switch then (if hand == "Right" then "Left" else "Right") else hand)
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

-- Game flow: a game starts once two players are in. First to GAME_TO wins; after a make, the other
-- player checks the ball up at the top of the key. With more than 2 in a server it plays as cutthroat.
-- shortcut: no take-it-back after a steal or rebound and no out of bounds; add them if 1v1s feel loose
local status = new("StringValue", { Name = "Status", Value = "Waiting for an opponent...", Parent = ReplicatedStorage })
local CHECK = Vector3.new(0, Hoops.FLOOR_Y + 3, RIM.Z + Hoops.THREE_DIST + 4) -- top of the key, behind the arc
local inGame, nextGameAt = false, 0

local function checkBall(offense)
	local defenseSpot = CHECK + Vector3.new(0, 0, -4) -- between the offense and the rim
	for _, p in Players:GetPlayers() do
		if rootOf(p) then
			p.Character:PivotTo(if p == offense then CFrame.lookAt(CHECK, Vector3.new(RIM.X, CHECK.Y, RIM.Z)) else CFrame.lookAt(defenseSpot, CHECK))
		end
	end
	if rootOf(offense) then
		give(offense)
	end
end

local function startGame(players)
	for _, p in players do
		p.leaderstats.Points.Value = 0
	end
	inGame = true
	status.Value = `First to {Hoops.GAME_TO}`
	checkBall(players[math.random(#players)])
end

local function onScore(scorer)
	local stats = scorer.leaderstats
	if stats.Points.Value >= Hoops.GAME_TO then
		stats.Wins.Value += 1
		status.Value = `{scorer.DisplayName} wins!`
		inGame, nextGameAt = false, os.clock() + Hoops.NEXT_GAME_DELAY
		return
	end
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= scorer and rootOf(p) then
			table.insert(others, p)
		end
	end
	if #others == 0 then
		return
	end
	-- Nobody grabs the ball while it drops through the net; then the other player checks it up.
	pickupLockUntil, pickupLockPlayer = os.clock() + Hoops.CHECK_DELAY + 0.1, nil
	task.delay(Hoops.CHECK_DELAY, function()
		if inGame then
			checkBall(others[math.random(#others)])
		end
	end)
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
		local range = Hoops.CONTEST_RANGE + (if r and r.Parent:GetAttribute("Stance") then Hoops.STANCE_CONTEST else 0) -- intense D
		if r and (r.Position - root.Position).Magnitude <= range then
			contested = true
		end
	end

	local target = RIM
	if math.random() >= Hoops.makeChance(Hoops.shotQuality(holdTime), dist, contested) then
		local a = math.random() * math.pi * 2
		target += Vector3.new(math.cos(a), 0, math.sin(a)) * Hoops.RIM_RADIUS -- aim at the iron: a real clank and rebound
	end

	lastShot = { player = player, points = dist >= Hoops.THREE_DIST and 3 or 2 }
	local from = heldSpot(root) -- wherever the ball is: the windup spot, or a layup/dunk path's current point
	local t = Hoops.flightTime(dist)
	release(from, Hoops.launchVelocity(from, target, t, Vector3.new(0, -workspace.Gravity, 0)))
end

action.OnServerEvent:Connect(function(player, kind, value, at)
	local root = rootOf(player)
	if not root then
		return
	end
	local h = holder()

	if kind == "move" then
		local move = Hoops.MOVES[value]
		local current = Hoops.MOVES[ball:GetAttribute("Move") or ""]
		if h == player and move and not move.finish and not (current and current.finish) then
			startPath(value, at)
		end
	elseif kind == "shootStart" then
		if h == player then
			shootStarts[player] = os.clock()
			-- Every shot is a path (Hoops.MOVES). Near the rim the client asks for a layup or dunk: check it's really in
			-- range (with slack for ping), otherwise it's a jump shot.
			local finish = Hoops.MOVES[value]
			local rimDist = ((root.Position - RIM) * FLAT).Magnitude
			local inRange = rimDist <= (if value == "Layup" then Hoops.LAYUP_RANGE else Hoops.DUNK_RANGE) + 3
			startPath(if finish and finish.finish and (value == "JumpShot" or inRange) then value else "JumpShot", at)
			ball:SetAttribute("GatherAt", workspace:GetServerTimeNow()) -- marks a shot under way (no steals)
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
	elseif kind == "stance" then
		-- intense D (L2 on defense): only for someone without the ball
		player.Character:SetAttribute("Stance", if value == true and h ~= player then true else nil)
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
			-- a ball in a shot windup can only be blocked, not stolen (like 2K)
			if r and not ball:GetAttribute("GatherAt") and Hoops.reaches(r.CFrame, spot) then
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
		local shot = lastShot
		lastShot = nil
		local stats = shot.player:FindFirstChild("leaderstats") -- gone if the shooter left mid-shot
		if stats then
			stats.Points.Value += shot.points
			scored:FireAllClients(shot.player, shot.points)
			if inGame then
				onScore(shot.player)
			end
		end
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

-- Same body for everyone on the court: keep each player's look (clothes, accessories, skin, face) on Roblox's
-- default body at default scale, the body the animations and ball spots are calibrated to.
local function standardBody(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- The avatar can finish loading before the character is in the world, and ApplyDescription only works there.
	while not character:IsDescendantOf(workspace) do
		character.AncestryChanged:Wait()
		if player.Character ~= character then
			return -- respawned meanwhile; the new character gets its own call
		end
	end
	local ok, err = pcall(function()
		local look = humanoid:GetAppliedDescription()
		look.Head, look.Torso, look.LeftArm, look.RightArm, look.LeftLeg, look.RightLeg = 0, 0, 0, 0, 0, 0
		look.HeightScale, look.WidthScale, look.DepthScale, look.HeadScale = 1, 1, 1, 1
		look.BodyTypeScale, look.ProportionScale = 0, 0
		humanoid:ApplyDescription(look)
	end)
	if not ok then
		warn(`couldn't standardize {player.Name}'s body: {err}`)
	elseif math.abs(humanoid.HipHeight - Hoops.RIG_HIP_HEIGHT) > 0.05 then
		warn(`the standard body (hip height {humanoid.HipHeight}) isn't the calibrated rig ({Hoops.RIG_HIP_HEIGHT}): re-dump the rig from a player character and re-run tools/preview/fit (see README)`)
	end
end

local function addStats(player)
	local stats = new("Folder", { Name = "leaderstats" })
	new("IntValue", { Name = "Points", Parent = stats })
	new("IntValue", { Name = "Wins", Parent = stats })
	stats.Parent = player
end
local function setUp(player)
	addStats(player)
	player.CharacterAppearanceLoaded:Connect(function()
		standardBody(player) -- after the avatar loads, or it would put the player's own body back
	end)
	if player:HasAppearanceLoaded() then
		task.spawn(standardBody, player) -- it can wait; don't hold up setting up other players
	end
end
Players.PlayerAdded:Connect(setUp)
for _, player in Players:GetPlayers() do -- Play Solo can add the player before this script runs
	setUp(player)
end

Players.PlayerRemoving:Connect(function(player)
	shootStarts[player] = nil
	nextSteal[player] = nil
	reaching[player] = nil
	nextBlock[player] = nil
	blocking[player] = nil
end)

-- Start a game once two players have spawned; stop if someone leaves mid-game.
while task.wait(0.5) do
	local players = Players:GetPlayers()
	if #players < 2 then
		if inGame or os.clock() >= nextGameAt then -- let a winner's name show out its time
			inGame = false
			status.Value = "Waiting for an opponent..."
		end
	elseif not inGame and os.clock() >= nextGameAt then
		local ready = true
		for _, p in players do
			ready = ready and rootOf(p) ~= nil
		end
		if ready then
			startGame(players)
		end
	end
end
