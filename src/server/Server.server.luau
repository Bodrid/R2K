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
local scored = new("RemoteEvent", { Name = "Scored", Parent = ReplicatedStorage }) -- (scorerId, scorerName, points): the score popup

-- Everyone on the court: real players, plus the practice bot when someone's alone. To the rules a bot looks
-- like a player (.Character, .UserId, .Name, .DisplayName); its UserId is negative, never a real player's.
local bots = {}
local botsFolder = new("Folder", { Name = "Bots", Parent = workspace })
local function participants()
	local list = Players:GetPlayers()
	for _, bot in bots do
		table.insert(list, bot)
	end
	return list
end
local function byId(id)
	if id == nil then
		return nil
	end
	local player = Players:GetPlayerByUserId(id)
	if player then
		return player
	end
	for _, bot in bots do
		if bot.UserId == id then
			return bot
		end
	end
	return nil
end

-- Per participant:
local shootStarts = {} -- os.clock() when they started holding shoot
local nextSteal = {} -- os.clock() when they may try again
local reaching = {} -- os.clock() until their reach stays live
local nextBlock = {} -- os.clock() when they may block again
local blocking = {} -- os.clock() until their block stays live
local points, wins = {}, {} -- this game's points and total wins (players also see them in the leaderboard)
local lastShot = nil -- { player, points } until the ball is caught
local pickupLockUntil, pickupLockPlayer = 0, nil
local prevY = ball.Position.Y

local function rootOf(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") or nil
end

local function holder()
	return byId(ball:GetAttribute("Holder"))
end

-- Held-ball state lives in attributes with server-clock times, so everyone computes the same ball (Hoops.ballSpot).
-- Set before Holder, so a client sees a new possession already in sync.
local function give(p)
	ball.Anchored = true
	ball.CanCollide = false
	ball:SetAttribute("Hand", "Right")
	ball:SetAttribute("Move", nil)
	ball:SetAttribute("MoveHand", nil)
	ball:SetAttribute("MoveAt", workspace:GetServerTimeNow()) -- the dribble starts at the top, right now
	ball:SetAttribute("GatherAt", nil)
	ball:SetAttribute("Holder", p.UserId)
	lastShot = nil
	table.clear(reaching)
end

local function heldSpot(hRoot)
	return Hoops.ballSpot(hRoot.CFrame, ball:GetAttribute("Hand"), ball:GetAttribute("Move"), ball:GetAttribute("MoveHand"), ball:GetAttribute("MoveAt"), workspace:GetServerTimeNow())
end

-- When the move (or shot) on the ball ends, server time.
local function moveEndsAt()
	local move = Hoops.MOVES[ball:GetAttribute("Move") or ""]
	return (ball:GetAttribute("MoveAt") or 0) + (if move then move.duration else 0)
end

-- Start a dribble move or finish on the ball. Uses the client's start time so its path lines up with ours,
-- within MAX_BACKDATE (covers ping), and never before the last move has finished.
local function startPath(name, at)
	local move = Hoops.MOVES[name]
	local now = workspace:GetServerTimeNow()
	local t = if typeof(at) == "number" and at == at then math.clamp(at, now - Hoops.MAX_BACKDATE, now) else now
	t = math.max(t, moveEndsAt())
	local hand = ball:GetAttribute("Hand")
	ball:SetAttribute("MoveHand", hand)
	ball:SetAttribute("Move", name)
	ball:SetAttribute("MoveAt", t)
	ball:SetAttribute("Hand", if move.switch then (if hand == "Right" then "Left" else "Right") else hand)
end

-- lockOnly: lock just that participant out of the pickup (passes, pokes); nil locks everyone (shots).
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

-- Game flow: a game starts once two are on the court (two players, or a player and the practice bot). First to
-- GAME_TO wins; after a make, the other one checks the ball up at the top of the key. More than 2: cutthroat.
-- shortcut: no take-it-back after a steal or rebound and no out of bounds; add them if 1v1s feel loose
local status = new("StringValue", { Name = "Status", Value = "Waiting for an opponent...", Parent = ReplicatedStorage })
local CHECK = Vector3.new(0, Hoops.FLOOR_Y + 3, RIM.Z + Hoops.THREE_DIST + 4) -- top of the key, behind the arc
local inGame, nextGameAt = false, 0

local function leaderstat(p, name) -- a player's leaderboard value (bots have none)
	local stats = typeof(p) == "Instance" and p:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild(name)
end

local function showScore()
	local on = participants()
	if #on == 2 then
		status.Value = `{on[1].DisplayName} {points[on[1]] or 0}  -  {points[on[2]] or 0} {on[2].DisplayName}`
	else
		status.Value = `First to {Hoops.GAME_TO}`
	end
end

local function checkBall(offense)
	local defenseSpot = CHECK + Vector3.new(0, 0, -4) -- between the offense and the rim
	for _, p in participants() do
		if rootOf(p) then
			p.Character:PivotTo(if p == offense then CFrame.lookAt(CHECK, Vector3.new(RIM.X, CHECK.Y, RIM.Z)) else CFrame.lookAt(defenseSpot, CHECK))
		end
	end
	if rootOf(offense) then
		give(offense)
	end
end

local function startGame(on)
	for _, p in on do
		points[p] = 0
		local stat = leaderstat(p, "Points")
		if stat then
			stat.Value = 0
		end
	end
	inGame = true
	showScore()
	checkBall(on[math.random(#on)])
end

local function onScore(scorer)
	if (points[scorer] or 0) >= Hoops.GAME_TO then
		wins[scorer] = (wins[scorer] or 0) + 1
		local stat = leaderstat(scorer, "Wins")
		if stat then
			stat.Value = wins[scorer]
		end
		status.Value = `{scorer.DisplayName} wins!`
		inGame, nextGameAt = false, os.clock() + Hoops.NEXT_GAME_DELAY
		return
	end
	showScore()
	local others = {}
	for _, p in participants() do
		if p ~= scorer and rootOf(p) then
			table.insert(others, p)
		end
	end
	if #others == 0 then
		return
	end
	-- Nobody grabs the ball while it drops through the net; then the other one checks it up.
	pickupLockUntil, pickupLockPlayer = os.clock() + Hoops.CHECK_DELAY + 0.1, nil
	task.delay(Hoops.CHECK_DELAY, function()
		if inGame then
			checkBall(others[math.random(#others)])
		end
	end)
end

-- The participant's root if their reach or block (in `live`) is still going; otherwise forget it.
local function liveRoot(live, p)
	local r = os.clock() <= live[p] and rootOf(p)
	if not r then
		live[p] = nil
	end
	return r
end

local function shoot(p, root, holdTime)
	local dist = ((root.Position - RIM) * FLAT).Magnitude
	local contested = false
	for _, other in participants() do
		local r = other ~= p and rootOf(other)
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

	lastShot = { player = p, points = dist >= Hoops.THREE_DIST and 3 or 2 }
	local from = heldSpot(root) -- wherever the ball is on the shot's path
	local t = Hoops.flightTime(dist)
	release(from, Hoops.launchVelocity(from, target, t, Vector3.new(0, -workspace.Gravity, 0)))
	-- backspin, around the shooter's right-hand axis (a real shot's spin; shows on the ball's seams)
	ball.AssemblyAngularVelocity = root.CFrame.RightVector * 18
end

-- What anyone on the court can do. Players get here through their buttons (the remote below), the practice
-- bot calls these directly; the checks are the same.
local act = {}

function act.move(p, root, name)
	local move = Hoops.MOVES[name]
	local current = Hoops.MOVES[ball:GetAttribute("Move") or ""]
	if holder() == p and move and not move.finish and not (current and current.finish) then
		return true, root
	end
	return false
end

function act.shootStart(p, root, name, at)
	if holder() ~= p then
		return
	end
	shootStarts[p] = os.clock()
	-- Every shot is a path (Hoops.MOVES). Near the rim a layup or dunk is asked for: check it's really in range
	-- (with slack for ping), otherwise it's a jump shot.
	local finish = Hoops.MOVES[name]
	local rimDist = ((root.Position - RIM) * FLAT).Magnitude
	local inRange = rimDist <= (if name == "Layup" then Hoops.LAYUP_RANGE else Hoops.DUNK_RANGE) + 3
	startPath(if finish and finish.finish and (name == "JumpShot" or inRange) then name else "JumpShot", at)
	ball:SetAttribute("GatherAt", workspace:GetServerTimeNow()) -- marks a shot under way (no steals)
end

function act.shoot(p, root, hold)
	local started = shootStarts[p]
	shootStarts[p] = nil
	if holder() ~= p or not started then
		return
	end
	-- Trust the client's timing so lag doesn't ruin releases, unless it's far from what the server saw.
	-- shortcut: a cheater can still claim perfect within HOLD_TOLERANCE, tighten or add anti-cheat before launch
	local serverHold = os.clock() - started
	if typeof(hold) ~= "number" or not (math.abs(hold - serverHold) <= Hoops.HOLD_TOLERANCE) then
		hold = serverHold
	end
	shoot(p, root, hold)
end

function act.pass(p, root)
	if holder() == p then
		-- A pass is a real physics ball, so anyone near its path can pick it off.
		-- shortcut: passes go where you face; aim at a teammate once teams exist
		local from = root.CFrame * Vector3.new(0, 0.5, -1.5)
		local to = root.CFrame * Vector3.new(0, 0.5, -Hoops.PASS_DIST)
		release(from, Hoops.launchVelocity(from, to, Hoops.PASS_TIME, Vector3.new(0, -workspace.Gravity, 0)), p)
	end
end

function act.steal(p, root)
	-- A reach only counts near the handler. It stays live for REACH_TIME, checked every frame below.
	local h = holder()
	local hRoot = h and h ~= p and rootOf(h)
	if hRoot and (hRoot.Position - root.Position).Magnitude <= Hoops.STEAL_RANGE and os.clock() >= (nextSteal[p] or 0) then
		nextSteal[p] = os.clock() + Hoops.STEAL_COOLDOWN
		reaching[p] = os.clock() + Hoops.REACH_TIME
	end
end

function act.stance(p, _, on)
	-- intense D (L2 on defense): only for someone without the ball
	p.Character:SetAttribute("Stance", if on == true and holder() ~= p then true else nil)
end

function act.block(p, root)
	local h = holder()
	if h ~= p and os.clock() >= (nextBlock[p] or 0) then
		nextBlock[p] = os.clock() + Hoops.BLOCK_COOLDOWN - 0.1 -- slack so the client's own cooldown never disagrees
		p.Character:SetAttribute("BlockAt", workspace:GetServerTimeNow()) -- everyone plays the animation
		-- Only near the ball handler (or a shooter while the shot is up) does the ball go live for contact,
		-- until the animation ends. Anywhere else it's just the animation.
		local carrier = h or (lastShot and lastShot.player)
		local cRoot = carrier and carrier ~= p and rootOf(carrier)
		if cRoot and (cRoot.Position - root.Position).Magnitude <= Hoops.BLOCK_RANGE then
			blocking[p] = os.clock() + Hoops.BLOCK_TIME
		end
	end
end

function act.drill(_) -- practice: the bot gets the ball at the top of the key, so you can work on your defense
	local bot = bots[1]
	if bot and rootOf(bot) then
		checkBall(bot)
	end
end

action.OnServerEvent:Connect(function(player, kind, value, at)
	local root = rootOf(player)
	local f = root and type(kind) == "string" and act[kind]
	if not f then
		return
	end
	if kind == "move" then
		if f(player, root, value) then
			startPath(value, at)
		end
	else
		f(player, root, value, at)
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
		if table.find(participants(), shot.player) then -- not if the shooter left mid-shot
			points[shot.player] = (points[shot.player] or 0) + shot.points
			local stat = leaderstat(shot.player, "Points")
			if stat then
				stat.Value = points[shot.player]
			end
			scored:FireAllClients(shot.player.UserId, shot.player.DisplayName, shot.points)
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
		for _, p in participants() do
			local r = rootOf(p)
			local lockedOut = locked and (pickupLockPlayer == nil or pickupLockPlayer == p)
			if r and not lockedOut and (r.Position - pos).Magnitude <= Hoops.PICKUP_RANGE then
				give(p)
				break
			end
		end
	end
end)

-- Practice bot ------------------------------------------------------------------------------------
-- Appears when someone's alone, leaves when a second player joins. Its brain (Bot.luau, tested in
-- tests/bot.spec.luau) decides ~10 times a second; this part gives it a body: movement, facing, dashes,
-- animations, and its actions through `act` like anyone else.
local Brain = require(script.Parent.Bot)(Hoops, Vector3, CFrame)
local BOT_ID = -424242
local LOCOMOTION = { idle = 507766666, run = 507767714 } -- Roblox's own default R15 animations

-- keep: leave it running if it already is (looping legs and stances); otherwise (re)start it (moves, shots).
local function botPlay(bot, name, id, fade, keep)
	local track = bot.tracks[name]
	if not track then
		local hum = bot.Character:FindFirstChildOfClass("Humanoid")
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or new("Animator", { Parent = hum }))
		if not animator or not id then
			return nil
		end
		track = animator:LoadAnimation(new("Animation", { AnimationId = `rbxassetid://{id}` }))
		bot.tracks[name] = track
	end
	if not (keep and track.IsPlaying) then
		track:Play(fade or 0.1)
	end
	return track
end

local function makeBot()
	local look = new("HumanoidDescription", {}) -- Roblox's default body, the one everything is calibrated to
	local skin, jersey, shorts = Color3.fromRGB(160, 110, 80), Color3.fromRGB(200, 40, 50), Color3.fromRGB(30, 30, 36)
	look.HeadColor, look.LeftArmColor, look.RightArmColor = skin, skin, skin
	look.TorsoColor, look.LeftLegColor, look.RightLegColor = jersey, shorts, shorts
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, look, Enum.HumanoidRigType.R15)
	if not ok then
		warn(`couldn't make the practice bot: {model}`)
		return
	end
	model.Name = "Practice Bot"
	model:SetAttribute("Id", BOT_ID) -- clients find the bot's body from the ball's Holder id
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = "Practice Bot"
	model:PivotTo(CFrame.lookAt(CHECK + Vector3.new(0, 0, -4), CHECK))
	model.Parent = botsFolder
	model.HumanoidRootPart:SetNetworkOwner(nil) -- the server moves it; don't hand it to a nearby player's machine
	local attachment = model.HumanoidRootPart:FindFirstChild("RootAttachment") or new("Attachment", { Parent = model.HumanoidRootPart })
	local bot = {
		Character = model, UserId = BOT_ID, Name = "PracticeBot", DisplayName = "Practice Bot",
		mind = {}, tracks = {}, seen = {}, queue = {}, dir = Vector3.zero, nextThink = 0,
		align = new("AlignOrientation", { Mode = Enum.OrientationAlignmentMode.OneAttachment, Attachment0 = attachment, Responsiveness = 25, MaxTorque = 1e6, Enabled = false, Parent = model.HumanoidRootPart }),
	}
	table.insert(bots, bot)
end

local function removeBot(bot)
	table.remove(bots, table.find(bots, bot))
	for _, t in { shootStarts, nextSteal, reaching, nextBlock, blocking, points, wins } do
		t[bot] = nil
	end
	bot.Character:Destroy()
end

local function botDash(bot, name, hand)
	local d = Hoops.DASHES[name]
	if not d then
		return
	end
	task.delay(d[1], function()
		local root = rootOf(bot)
		if not root then
			return
		end
		local cf = root.CFrame
		local dir = if d[2] == "back" then -cf.LookVector elseif d[2] == "side" then cf.RightVector * (if hand == "Left" then -1 else 1) else cf.LookVector
		local flatDir = Vector3.new(dir.X, 0, dir.Z).Unit * d[3]
		local attachment = new("Attachment", { Parent = root })
		new("LinearVelocity", { Attachment0 = attachment, RelativeTo = Enum.ActuatorRelativeTo.World, VelocityConstraintMode = Enum.VelocityConstraintMode.Plane, PrimaryTangentAxis = Vector3.xAxis, SecondaryTangentAxis = Vector3.zAxis, PlaneVelocity = Vector2.new(flatDir.X, flatDir.Z), MaxForce = 50000, Parent = root })
		task.delay(d[4], function()
			attachment:Destroy()
		end)
	end)
end

-- The bot's next buffered move starts the moment the current one ends (chaining, like a player's).
local function botNextMove(bot, root)
	local name = bot.queue[1]
	if not name or workspace:GetServerTimeNow() < moveEndsAt() or bot.shooting then
		return
	end
	table.remove(bot.queue, 1)
	local hand = ball:GetAttribute("Hand")
	if name == "SpinMove" and hand == "Left" then
		name = "SpinEscape" -- SpinMove only has a right-hand animation
	end
	if act.move(bot, root, name) then
		startPath(name, workspace:GetServerTimeNow())
		botPlay(bot, name .. hand, Hoops.ANIMATIONS[Hoops.animationFor(name, hand)])
		botDash(bot, name, hand)
	end
end

local function botShoot(bot, root, finish, hold)
	table.clear(bot.queue)
	bot.shooting = true
	local hand = ball:GetAttribute("Hand")
	act.shootStart(bot, root, finish, workspace:GetServerTimeNow())
	local shot = ball:GetAttribute("Move") -- the server may have turned it into a jump shot
	local track = botPlay(bot, shot .. hand, Hoops.ANIMATIONS[Hoops.animationFor(shot, hand)])
	local move = Hoops.MOVES[shot]
	if shot == "JumpShot" and track then
		task.delay(move.duration, function() -- hold the set point while "the meter fills"
			if bot.shooting then
				track:AdjustSpeed(0)
			end
		end)
	elseif move and move.jumpAt then
		task.delay(move.jumpAt, function()
			local r = rootOf(bot)
			if r and bot.shooting then
				r.Parent.Humanoid.Jump = true
			end
		end)
	end
	task.delay(hold, function()
		bot.shooting = false
		if track then
			track:AdjustSpeed(1)
		end
		local r = rootOf(bot)
		if r then
			act.shoot(bot, r, hold)
		end
	end)
end

-- Where the bot saw someone `reaction` seconds ago (it plays a beat behind, like a person).
local function seenLate(bot, p, root)
	local now = os.clock()
	table.insert(bot.seen, { t = now, p = p, pos = root.Position, vel = root.AssemblyLinearVelocity })
	while #bot.seen > 1 and (bot.seen[2].t <= now - Brain.SKILL.reaction or bot.seen[1].p ~= p) do
		table.remove(bot.seen, 1)
	end
	return bot.seen[1]
end

local function botThink(bot, root)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local h = holder()
	local oppRoot = nil -- the nearest other body on the court
	for _, p in participants() do
		local r = p ~= bot and rootOf(p)
		if r and (not oppRoot or (r.Position - root.Position).Magnitude < (oppRoot.Position - root.Position).Magnitude) then
			oppRoot = r
		end
	end
	local me = { pos = root.Position, vel = root.AssemblyLinearVelocity }
	local out
	if h == bot then
		if not bot.possessionAt then
			bot.possessionAt = now
		end
		out = Brain.offense({
			now = now, me = me, opp = oppRoot and { pos = oppRoot.Position, vel = oppRoot.AssemblyLinearVelocity },
			hand = ball:GetAttribute("Hand"), busy = bot.shooting or #bot.queue > 0 or serverNow < moveEndsAt(),
			possessionAge = now - bot.possessionAt, mind = bot.mind, rng = math.random,
		})
	else
		bot.possessionAt = nil
		table.clear(bot.queue)
		local hRoot = h and rootOf(h)
		if hRoot then
			local seen = seenLate(bot, h, hRoot)
			local shooting = ball:GetAttribute("GatherAt") ~= nil
			out = Brain.defense({
				now = now, me = me, opp = { pos = seen.pos, vel = seen.vel },
				canReach = (hRoot.Position - root.Position).Magnitude <= Hoops.STEAL_RANGE and Hoops.reaches(root.CFrame, heldSpot(hRoot)),
				shooting = shooting, shotKind = ball:GetAttribute("Move"), shotAge = serverNow - (ball:GetAttribute("MoveAt") or serverNow),
				mind = bot.mind, rng = math.random,
			})
		else
			out = Brain.chase({ me = me, ballPos = ball.Position, ballVel = ball.AssemblyLinearVelocity })
		end
	end
	bot.dir, bot.sprint, bot.face = out.dir or Vector3.zero, out.sprint, out.face
	if (out.stance or false) ~= (bot.stance or false) then
		bot.stance = out.stance
		act.stance(bot, root, out.stance)
	end

	local a = out.act
	if not a then
		return
	elseif a.kind == "move" then
		table.insert(bot.queue, a.name)
		if a.chain then
			table.insert(bot.queue, a.chain)
		end
	elseif a.kind == "shoot" then
		botShoot(bot, root, a.finish, a.hold)
	elseif a.kind == "steal" then
		botPlay(bot, "StealSwipe", Hoops.ANIMATIONS.StealSwipe)
		act.steal(bot, root)
	elseif a.kind == "block" then
		botPlay(bot, "Block", Hoops.ANIMATIONS.Block)
		root.Parent.Humanoid.Jump = true
		act.block(bot, root)
	end
end

RunService.Heartbeat:Connect(function()
	for _, bot in bots do
		local root = rootOf(bot)
		if not root then
			continue
		end
		if root.Position.Y < Hoops.FLOOR_Y - 20 then
			bot.Character:PivotTo(CFrame.new(CHECK)) -- fell off somehow: back on the court
		end
		if os.clock() >= bot.nextThink then
			bot.nextThink = os.clock() + 0.1
			botThink(bot, root)
		end
		botNextMove(bot, root)
		-- move, like a player: face the basket with the ball (unless sprinting), face the ball in stance
		local hum = root.Parent.Humanoid
		hum.WalkSpeed = if bot.stance then Hoops.STANCE_SPEED elseif bot.sprint then Hoops.SPRINT_SPEED else Hoops.WALK_SPEED
		hum:Move(if bot.shooting then Vector3.zero else bot.dir)
		local flatFace = bot.face and Vector3.new(bot.face.X - root.Position.X, 0, bot.face.Z - root.Position.Z)
		local facing = flatFace ~= nil and flatFace.Magnitude > 0.5
		hum.AutoRotate = not facing
		bot.align.Enabled = facing
		if facing then
			bot.align.CFrame = CFrame.lookAt(root.Position, root.Position + flatFace)
		end
		-- legs: Roblox's run and idle; stance overlays on top (once their animations are published)
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local run = botPlay(bot, "run", LOCOMOTION.run, 0.2, true)
		local idle = botPlay(bot, "idle", LOCOMOTION.idle, 0.2, true)
		if run and idle then
			run:AdjustWeight(math.clamp(speed / 6, 0.01, 1))
			run:AdjustSpeed(math.max(speed / 16, 0.1))
			idle:AdjustWeight(math.clamp(1 - speed / 6, 0.01, 1))
		end
		local overlay = if holder() == bot then Hoops.animationFor("DribbleStance", ball:GetAttribute("Hand")) elseif bot.stance then "DefenseStance" else nil
		if overlay ~= bot.overlay then
			if bot.overlay and bot.tracks[bot.overlay] then
				bot.tracks[bot.overlay]:Stop(0.2)
			end
			bot.overlay = overlay
			if overlay then
				botPlay(bot, overlay, Hoops.ANIMATIONS[overlay], 0.2, true)
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
	for _, t in { shootStarts, nextSteal, reaching, nextBlock, blocking, points, wins } do
		t[player] = nil
	end
end)

-- Every half second: the practice bot comes and goes (alone = a bot to play), games start once two are on the
-- court, and stop if someone leaves mid-game.
while task.wait(0.5) do
	local humans = Players:GetPlayers()
	if #humans == 1 and #bots == 0 and rootOf(humans[1]) then
		makeBot()
	elseif #humans ~= 1 then
		for i = #bots, 1, -1 do
			removeBot(bots[i])
		end
	end
	local on = participants()
	if #on < 2 then
		if inGame or os.clock() >= nextGameAt then -- let a winner's name show out its time
			inGame = false
			status.Value = "Waiting for an opponent..."
		end
	elseif not inGame and os.clock() >= nextGameAt then
		local ready = true
		for _, p in on do
			ready = ready and rootOf(p) ~= nil
		end
		if ready then
			startGame(on)
		end
	end
end
