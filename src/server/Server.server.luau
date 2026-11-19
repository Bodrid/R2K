-- Server: owns the rules. It decides who holds the ball, shot results, steals and points.
-- While someone holds the ball, the server only stores WHO (the "Holder" attribute);
-- every client draws the ball in that player's hand itself, so dribbling never waits on the network.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hoops = require(ReplicatedStorage.Hoops)
local ServerStorage = game:GetService("ServerStorage")

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

-- In Studio, everyone plays the animations saved in the place (see Hoops.animationId): the generated placeholders,
-- with anything you've saved from the Animation Editor (RBX_ANIMSAVES) on top, matched by name.
if Hoops.STUDIO_ANIMATIONS and RunService:IsStudio() then
	local copy = new("Folder", { Name = "StudioAnimations" })
	for _, sourceName in { "PlaceholderAnimations", "RBX_ANIMSAVES" } do
		local source = ServerStorage:FindFirstChild(sourceName)
		for _, sequence in if source then source:GetDescendants() else {} do
			if sequence:IsA("KeyframeSequence") then
				local older = copy:FindFirstChild(sequence.Name)
				if older then
					older:Destroy()
				end
				sequence:Clone().Parent = copy
			end
		end
	end
	copy.Parent = ReplicatedStorage
end

-- Court (built in code so every position lives in this file). Real-proportioned markings, scaled so the
-- three-point arc sits exactly THREE_DIST from the rim, the distance scoring uses.
local wood, paint, apron = Color3.fromRGB(205, 160, 105), Color3.fromRGB(28, 60, 140), Color3.fromRGB(30, 34, 48)
local white, orange, black = Color3.new(1, 1, 1), Color3.fromRGB(255, 110, 20), Color3.fromRGB(15, 15, 18)
local LINE_Y = Hoops.FLOOR_Y + 0.1 -- floor layers sit >= 0.05 apart, so no two faces fight (flicker) at a distance
local BASELINE, HALF, SIDE_X = Hoops.BASELINE_Z, Hoops.HALF_Z, Hoops.COURT_X
local FT_Z, LANE = RIM.Z + 10.5, 6.75 -- free-throw line; half the lane's width
local arena = new("Folder", { Name = "Arena", Parent = workspace })
local hoop = new("Folder", { Name = "Hoop", Parent = workspace })

local function part(props) -- an anchored part in the arena (props.Parent overrides)
	props.Anchored = true
	props.Parent = props.Parent or arena
	return new("Part", props)
end
local function decal(name, size, cf, color) -- thin, non-solid markings
	return part({ Name = name, CanCollide = false, CanQuery = false, CastShadow = false, Size = size, CFrame = cf, Color = color, Material = Enum.Material.SmoothPlastic })
end
local function line(x1, z1, x2, z2, width, color) -- a floor line
	local a, b = Vector3.new(x1, LINE_Y, z1), Vector3.new(x2, LINE_Y, z2)
	decal("Line", Vector3.new(width or 0.3, 0.05, (b - a).Magnitude + (width or 0.3)), CFrame.lookAt((a + b) / 2, b), color or white)
end
local function arc(cx, cz, radius, fromDeg, toDeg) -- a floor arc in short straight pieces (0° = +X, 90° = toward half court)
	local steps = math.ceil(math.abs(toDeg - fromDeg) / 4)
	local step = (toDeg - fromDeg) / steps
	for i = 0, steps - 1 do
		local a = math.rad(fromDeg + (i + 0.5) * step)
		decal("Line", Vector3.new(0.3, 0.05, radius * math.rad(math.abs(step)) + 0.05), CFrame.new(cx + math.cos(a) * radius, LINE_Y, cz + math.sin(a) * radius) * CFrame.Angles(0, -a, 0), white)
	end
end
local function sign(text, size, cf, color, face) -- big text painted on a surface
	local board = part({ Name = "Sign", CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 1, Size = size, CFrame = cf })
	local gui = new("SurfaceGui", { Face = face or Enum.NormalId.Top, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 1, Parent = board })
	return new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text, TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = color, Parent = gui })
end

-- floor: the court on a dark apron, a team-color border band, the paint, a wordmark
-- Layers, bottom up: apron (top 0.2 under the floor), border band (0.1 under), court (the floor), paint, lines.
part({ Name = "Apron", Size = Vector3.new(96, 1, 86), Position = Vector3.new(0, Hoops.FLOOR_Y - 0.7, -5), Color = apron, Material = Enum.Material.SmoothPlastic })
part({ Name = "Court", Size = Vector3.new(SIDE_X * 2, 1, HALF - BASELINE), Position = Vector3.new(0, Hoops.FLOOR_Y - 0.5, (HALF + BASELINE) / 2), Color = wood, Material = Enum.Material.WoodPlanks })
part({ Name = "Border", Size = Vector3.new(SIDE_X * 2 + 6, 1, HALF - BASELINE + 6), Position = Vector3.new(0, Hoops.FLOOR_Y - 0.6, (HALF + BASELINE) / 2), Color = paint, Material = Enum.Material.SmoothPlastic })
decal("Paint", Vector3.new(LANE * 2, 0.02, FT_Z - BASELINE), CFrame.new(0, Hoops.FLOOR_Y + 0.04, (FT_Z + BASELINE) / 2), paint)
sign("R2K", Vector3.new(18, 0.05, 7), CFrame.new(0, Hoops.FLOOR_Y + 0.05, HALF - 7), Color3.fromRGB(150, 105, 60))
line(-SIDE_X, BASELINE, SIDE_X, BASELINE) -- baseline
line(-SIDE_X, HALF, SIDE_X, HALF) -- half court
line(-SIDE_X, BASELINE, -SIDE_X, HALF) -- sidelines
line(SIDE_X, BASELINE, SIDE_X, HALF)
line(-LANE, BASELINE, -LANE, FT_Z) -- lane
line(LANE, BASELINE, LANE, FT_Z)
line(-LANE, FT_Z, LANE, FT_Z) -- free-throw line
for _, z in { BASELINE + 7, BASELINE + 9.5, BASELINE + 12 } do -- lane hash marks
	line(-LANE - 0.8, z, -LANE, z)
	line(LANE, z, LANE + 0.8, z)
end
arc(0, FT_Z, 5, 0, 180) -- free-throw circle
arc(RIM.X, RIM.Z, 3.4, 0, 180) -- restricted area
arc(0, HALF, 5, 180, 360) -- center circle
-- Three-point line: exactly THREE_DIST from the rim, baseline to baseline.
local corner = math.deg(math.asin((BASELINE - RIM.Z) / Hoops.THREE_DIST))
arc(RIM.X, RIM.Z, Hoops.THREE_DIST, corner, 180 - corner)
new("SpawnLocation", { Anchored = true, CanCollide = false, Transparency = 1, Size = Vector3.new(6, 0.2, 6), Position = CENTER - Vector3.new(0, 2.9, 0), Parent = arena })

-- arena: padded walls round the apron, bleachers, light towers with real spotlights
local WALL_X, WALL_BACK, WALL_FRONT = 46, -47, 37
for _, w in {
	{ Vector3.new(WALL_X * 2, 3, 1), Vector3.new(0, 0, WALL_BACK) },
	{ Vector3.new(WALL_X * 2, 3, 1), Vector3.new(0, 0, WALL_FRONT) },
	{ Vector3.new(1, 3, WALL_FRONT - WALL_BACK), Vector3.new(-WALL_X, 0, (WALL_FRONT + WALL_BACK) / 2) },
	{ Vector3.new(1, 3, WALL_FRONT - WALL_BACK), Vector3.new(WALL_X, 0, (WALL_FRONT + WALL_BACK) / 2) },
} do
	local at = w[2] + Vector3.new(0, Hoops.FLOOR_Y + 1.5, 0)
	part({ Name = "Wall", Size = w[1], Position = at, Color = Color3.fromRGB(22, 26, 38), Material = Enum.Material.Fabric })
	part({ Name = "WallStripe", CanCollide = false, Size = w[1] + Vector3.new(0.05, -2.6, 0.05), Position = at + Vector3.new(0, 1.3, 0), Color = paint, Material = Enum.Material.SmoothPlastic })
end
for row = 0, 4 do -- bleachers along the right sideline
	part({ Name = "Bleacher", Size = Vector3.new(3, 1 + row * 1.6, 52), Position = Vector3.new(WALL_X + 2 + row * 3, Hoops.FLOOR_Y + (1 + row * 1.6) / 2 - 0.5, -5), Color = if row % 2 == 0 then Color3.fromRGB(60, 64, 78) else Color3.fromRGB(48, 52, 64), Material = Enum.Material.Metal })
end
for _, x in { -WALL_X + 2, WALL_X - 2 } do -- light towers at the corners, aimed at the court
	for _, z in { WALL_BACK + 2, WALL_FRONT - 2 } do
		part({ Name = "LightPole", Size = Vector3.new(0.8, 34, 0.8), Position = Vector3.new(x, Hoops.FLOOR_Y + 17, z), Color = Color3.fromRGB(40, 42, 50), Material = Enum.Material.Metal })
		local lamp = part({ Name = "Lamp", CanCollide = false, Size = Vector3.new(4, 1.2, 1.2), Position = Vector3.new(x, Hoops.FLOOR_Y + 34, z), Color = Color3.fromRGB(255, 245, 220), Material = Enum.Material.Neon })
		lamp.CFrame = CFrame.lookAt(lamp.Position, Vector3.new(0, Hoops.FLOOR_Y, -5))
		new("SpotLight", { Brightness = 2.2, Range = 60, Angle = 55, Face = Enum.NormalId.Front, Shadows = true, Color = Color3.fromRGB(255, 244, 225), Parent = lamp })
	end
end

-- Hoop: an NBA-style stanchion out of bounds behind the baseline, an arm over to the backboard (bordered,
-- shooter's square, padded edge), a smooth solid rim on a flange.
local boardZ = RIM.Z - (Hoops.RIM_RADIUS + 0.6)
local poleZ = BASELINE - 3
part({ Name = "StanchionPad", Size = Vector3.new(4, 4.5, 4), Position = Vector3.new(0, Hoops.FLOOR_Y + 2.25, poleZ - 0.5), Color = paint, Material = Enum.Material.Fabric, Parent = hoop })
part({ Name = "Pole", Size = Vector3.new(0.9, Hoops.RIM_Y + 3, 0.9), Position = Vector3.new(0, (Hoops.RIM_Y + 3) / 2, poleZ), Color = Color3.fromRGB(45, 45, 52), Material = Enum.Material.Metal, Parent = hoop })
local armFrom, armTo = Vector3.new(0, Hoops.RIM_Y + 2.8, poleZ), Vector3.new(0, RIM.Y + 1.8, boardZ - 0.2)
part({ Name = "Arm", Size = Vector3.new(0.6, 0.6, (armTo - armFrom).Magnitude), CFrame = CFrame.lookAt((armFrom + armTo) / 2, armTo), Color = Color3.fromRGB(45, 45, 52), Material = Enum.Material.Metal, Parent = hoop })
local board = part({ Name = "Backboard", Size = Vector3.new(7, 4.5, 0.3), Position = Vector3.new(RIM.X, RIM.Y + 1.8, boardZ), Color = Color3.new(1, 1, 1), Transparency = 0.35, Material = Enum.Material.Glass, Parent = hoop })
local function boardLine(width, height, x, y)
	local l = decal("BoardLine", Vector3.new(width, height, 0.02), CFrame.new(board.Position + Vector3.new(x, y, 0.16)), black)
	l.Parent = hoop
end
boardLine(7, 0.14, 0, 2.18) -- border
boardLine(7, 0.14, 0, -2.18)
boardLine(0.14, 4.5, 3.43, 0)
boardLine(0.14, 4.5, -3.43, 0)
boardLine(2.4, 0.1, 0, -1.65) -- shooter's square, just above the rim
boardLine(2.4, 0.1, 0, 0.15)
boardLine(0.1, 1.8, 1.2, -0.75)
boardLine(0.1, 1.8, -1.2, -0.75)
part({ Name = "BoardPad", Size = Vector3.new(7.2, 0.35, 0.5), Position = board.Position + Vector3.new(0, -2.4, 0), Color = paint, Material = Enum.Material.Fabric, Parent = hoop })
part({ Name = "Flange", Size = Vector3.new(0.7, 0.12, 0.75), Position = Vector3.new(RIM.X, RIM.Y - 0.05, boardZ + 0.5), Color = orange, Material = Enum.Material.Metal, Parent = hoop })
for i = 1, 24 do -- rim as a ring of solid segments so misses bounce off the iron for real
	local a = i / 24 * math.pi * 2
	part({ Name = "Rim", Size = Vector3.new(0.22, 0.22, 0.42), CFrame = CFrame.new(RIM + Vector3.new(math.cos(a), 0, math.sin(a)) * Hoops.RIM_RADIUS) * CFrame.Angles(0, -a, 0), Color = orange, Material = Enum.Material.Metal, Parent = hoop })
end

-- Scoreboard above the hoop: shows the game's live score (the same text as the on-screen banner).
part({ Name = "ScoreboardBox", Size = Vector3.new(16, 5, 1.5), Position = Vector3.new(0, RIM.Y + 9, poleZ - 2), Color = Color3.fromRGB(14, 14, 18), Material = Enum.Material.Metal })
local scoreboard = sign("", Vector3.new(15.4, 4.4, 0.05), CFrame.new(0, RIM.Y + 9, poleZ - 1.22), Color3.fromRGB(255, 205, 60), Enum.NormalId.Back)

-- Lighting: a bright, clean arena with a little haze in the air.
local Lighting = game:GetService("Lighting")
Lighting.ClockTime, Lighting.Brightness = 14.5, 2.5
Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 90), Color3.fromRGB(130, 130, 140)
Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = 0.6, 0.6
new("ColorCorrectionEffect", { Contrast = 0.08, Saturation = 0.12, Brightness = 0.02, Parent = Lighting })
new("BloomEffect", { Intensity = 0.25, Size = 18, Threshold = 1.6, Parent = Lighting })
new("Atmosphere", { Density = 0.22, Offset = 0.1, Haze = 1.2, Glare = 0.2, Color = Color3.fromRGB(200, 205, 220), Decay = Color3.fromRGB(110, 115, 130), Parent = Lighting })

-- Net: criss-crossed strands from the rim through a mid ring to a narrower bottom ring. Not solid, so made
-- shots fall through. Clients make it swish when a shot goes in.
local NET_MID, NET_DROP = Hoops.RIM_RADIUS * 0.8, 2.1
local NET_BOTTOM = Hoops.RIM_RADIUS * 0.6
local function ringPoint(radius, a, drop)
	return RIM + Vector3.new(math.cos(a) * radius, -drop, math.sin(a) * radius)
end
local function strand(a, b)
	part({ Name = "Net", CanCollide = false, CanQuery = false, CastShadow = false, Size = Vector3.new(0.05, 0.05, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = Color3.new(1, 1, 1), Material = Enum.Material.Fabric, Parent = hoop })
end
for i = 1, 16 do
	local a = i / 16 * math.pi * 2
	local half = math.pi / 16
	for _, side in { -1, 1 } do
		strand(ringPoint(Hoops.RIM_RADIUS, a, 0), ringPoint(NET_MID, a + side * half, NET_DROP * 0.5))
		strand(ringPoint(NET_MID, a + side * half, NET_DROP * 0.5), ringPoint(NET_BOTTOM, a, NET_DROP))
	end
end
-- The ball: pebbled leather with real seams (two great circles and the two curved side seams), welded on,
-- massless and not solid so the physics are the ball's own. A faint trail shows on shots and passes.
-- Persistent so instance streaming never removes the ball on any client.
local ballModel = new("Model", { Name = "Basketball", ModelStreamingMode = Enum.ModelStreamingMode.Persistent })
local R = Hoops.BALL_RADIUS
local ball = new("Part", {
	Name = "Ball",
	Shape = Enum.PartType.Ball,
	Size = Vector3.one * R * 2,
	Color = Color3.fromRGB(214, 98, 34),
	Material = Enum.Material.Leather,
	CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.5, 0.75, 1, 100), -- bouncy, and its bounce wins over the floor's
	Position = CENTER,
	Parent = ballModel,
})
local function seam(offset, axis) -- a thin disc through the ball; only its edge shows outside, as a seam line
	local radius = math.sqrt(R * R - offset * offset) + 0.012
	local cf = ball.CFrame * axis * CFrame.new(offset, 0, 0) -- a cylinder's round faces point along its X axis
	local disc = new("Part", { Name = "Seam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.035, radius * 2, radius * 2), CFrame = cf, Color = Color3.fromRGB(25, 18, 14), Material = Enum.Material.SmoothPlastic, Massless = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Parent = ballModel })
	new("WeldConstraint", { Part0 = ball, Part1 = disc, Parent = disc })
end
seam(0, CFrame.new()) -- over the top
seam(0, CFrame.Angles(0, 0, math.rad(90))) -- the equator
seam(R * 0.55, CFrame.new()) -- curved side seams
seam(-R * 0.55, CFrame.new())
local trailTop = new("Attachment", { Position = Vector3.new(0, R * 0.5, 0), Parent = ball })
local trailBottom = new("Attachment", { Position = Vector3.new(0, -R * 0.5, 0), Parent = ball })
local trail = new("Trail", { Attachment0 = trailTop, Attachment1 = trailBottom, Lifetime = 0.2, MinLength = 0.1, Enabled = false, FaceCamera = true, Color = ColorSequence.new(Color3.fromRGB(255, 225, 190)), Transparency = NumberSequence.new(0.55, 1), Parent = ball })
ballModel.Parent = workspace

local action = new("RemoteEvent", { Name = "Action", Parent = ReplicatedStorage })
local scored = new("RemoteEvent", { Name = "Scored", Parent = ReplicatedStorage }) -- (scorerId, scorerName, points): the score popup
local callout = new("RemoteEvent", { Name = "Callout", Parent = ReplicatedStorage }) -- (text): BLOCKED!, STOLEN! for everyone

-- Everyone on the court: real players, plus the practice bot when someone's alone. To the rules a bot looks
-- like a player (.Character, .UserId, .Name, .DisplayName); its UserId is negative, never a real player's.
local bots = {}
local botsFolder = new("Folder", { Name = "Bots", Parent = workspace })
local Brain = require(script.Parent.Bot)(Hoops, Vector3, CFrame) -- the practice bot's brain
botsFolder:SetAttribute("Level", Brain.level)
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
local stamina, tiredAt = {}, {} -- 0..1, and when they last spent some (it comes back after STAMINA_REGEN_DELAY)
local lastShot = nil -- { player, points } until the ball is caught
local lastPossessor = nil -- who had the ball last (an offensive rebound needn't be taken back)
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

-- Spend some of someone's stamina, and pause its regen for STAMINA_REGEN_DELAY.
local function tire(p, amount)
	if not p or not p.Character then
		return
	end
	stamina[p] = math.max((stamina[p] or 1) - amount, 0)
	tiredAt[p] = os.clock()
end

-- Held-ball state lives in attributes with server-clock times, so everyone computes the same ball (Hoops.ballSpot).
-- Set before Holder, so a client sees a new possession already in sync.
-- checked: given at the top of the key (check ball). Otherwise, a change of possession (a steal, a defensive
-- rebound, a picked-off pass) has to be taken back past the arc before it can score, like 2K's park.
local function give(p, checked)
	ball:SetAttribute("MustClear", if checked or p == lastPossessor then nil else true)
	lastPossessor = p
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
	if not move.finish then -- dribble moves cost stamina (escapes double)
		tire(holder(), Hoops.STAMINA_MOVE * (if name:find("Escape") then 2 else 1))
	end
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
local function nameOf(root) -- the name shown over someone (their display name, or the bot's)
	local hum = root.Parent:FindFirstChildOfClass("Humanoid")
	return if hum and hum.DisplayName ~= "" then hum.DisplayName else root.Parent.Name
end

local function swat(position, blockerRoot)
	callout:FireAllClients(`BLOCKED by {nameOf(blockerRoot)}!`)
	lastShot = nil
	table.clear(blocking)
	release(position, blockerRoot.CFrame.LookVector * Hoops.SWAT_SPEED + Vector3.new(0, 8, 0))
end

-- Game flow: a game starts once two are on the court (two players, or a player and the practice bot). First to
-- GAME_TO wins; after a make, the other one checks the ball up at the top of the key. More than 2: cutthroat.
-- shortcut: no take-it-back after a steal or rebound and no out of bounds; add them if 1v1s feel loose
local status = new("StringValue", { Name = "Status", Value = "Waiting for an opponent...", Parent = ReplicatedStorage })
scoreboard.Text = status.Value
status.Changed:Connect(function(text)
	scoreboard.Text = text
end)
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
		give(offense, true)
	end
end

local function startGame(on)
	for _, p in on do
		points[p] = 0
		stamina[p] = 1
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
	if math.random() >= Hoops.makeChance(Hoops.shotQuality(holdTime), dist, contested, stamina[p]) then
		local a = math.random() * math.pi * 2
		target += Vector3.new(math.cos(a), 0, math.sin(a)) * Hoops.RIM_RADIUS -- aim at the iron: a real clank and rebound
	end

	-- an uncleared shot can still go in, it just doesn't count
	lastShot = { player = p, points = if ball:GetAttribute("MustClear") then 0 elseif dist >= Hoops.THREE_DIST then 3 else 2 }
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
	tire(p, 0) -- no regen through the green window, so the green they saw on their meter is the one judged
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
		tire(p, Hoops.STAMINA_MOVE)
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

function act.level(_) -- practice: the bot's difficulty, Easy -> Medium -> Hard -> Easy
	local nextLevel = { Easy = "Medium", Medium = "Hard", Hard = "Easy" }
	Brain.setLevel(nextLevel[Brain.level])
	botsFolder:SetAttribute("Level", Brain.level)
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
	trail.Enabled = ball:GetAttribute("Holder") == nil and ball.AssemblyLinearVelocity.Magnitude > 22 -- shots and passes
	if ball:GetAttribute("Holder") then
		local h = holder()
		local hRoot = h and rootOf(h)
		if not hRoot then
			release(CENTER, Vector3.zero) -- holder left or died
			return
		end
		if ball:GetAttribute("MustClear") and ((hRoot.Position - RIM) * FLAT).Magnitude >= Hoops.THREE_DIST then
			ball:SetAttribute("MustClear", nil) -- taken back past the arc: live ball
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
				callout:FireAllClients(`STOLEN by {nameOf(r)}!`)
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
		if shot.points == 0 then
			scored:FireAllClients(shot.player.UserId, shot.player.DisplayName, 0) -- "take it back": no basket
		elseif table.find(participants(), shot.player) then -- not if the shooter left mid-shot
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

-- Stamina over time, for everyone on the court: sprinting (judged from how fast they really move, so it can't
-- be faked) drains it; easing off brings it back. Published as a "Stamina" attribute for the stamina bar.
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, p in participants() do
		local root = rootOf(p)
		if root then
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > Hoops.WALK_SPEED + 1.5 then
				tire(p, Hoops.STAMINA_SPRINT * dt)
			elseif now - (tiredAt[p] or 0) > Hoops.STAMINA_REGEN_DELAY then
				stamina[p] = math.min((stamina[p] or 1) + Hoops.STAMINA_REGEN * dt, 1)
			end
			local shown = p.Character:GetAttribute("Stamina")
			local value = math.floor((stamina[p] or 1) * 100 + 0.5) / 100
			if shown ~= value then
				p.Character:SetAttribute("Stamina", value)
			end
		end
	end
end)

-- Practice bot ------------------------------------------------------------------------------------
-- Appears when someone's alone, leaves when a second player joins. Its brain (Bot.luau, tested in
-- tests/bot.spec.luau) decides ~10 times a second; this part gives it a body: movement, facing, dashes,
-- animations, and its actions through `act` like anyone else.
local BOT_ID = -424242
local LOCOMOTION = { idle = "rbxassetid://507766666", run = "rbxassetid://507767714" } -- Roblox's own default R15 animations

-- id: a content id (Hoops.animationId). keep: leave it running if it already is (looping legs and stances);
-- otherwise (re)start it (moves, shots).
local function botPlay(bot, name, id, fade, keep)
	local track = bot.tracks[name]
	if not track then
		local hum = bot.Character:FindFirstChildOfClass("Humanoid")
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or new("Animator", { Parent = hum }))
		if not animator or not id then
			return nil
		end
		track = animator:LoadAnimation(new("Animation", { AnimationId = id }))
		bot.tracks[name] = track
	end
	if not (keep and track.IsPlaying) then
		track:Play(fade or 0.1)
	end
	return track
end

local botRetryAt = 0
local function makeBot()
	if os.clock() < botRetryAt then
		return
	end
	botRetryAt = os.clock() + 10 -- if Roblox can't build it, try again later instead of every half second
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
	for _, t in { shootStarts, nextSteal, reaching, nextBlock, blocking, points, wins, stamina, tiredAt } do
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
		botPlay(bot, name .. hand, Hoops.animationId(Hoops.animationFor(name, hand)))
		botDash(bot, name, hand)
	end
end

local function botShoot(bot, root, finish, hold)
	if holder() ~= bot then
		return
	end
	table.clear(bot.queue)
	bot.shooting = true
	local hand = ball:GetAttribute("Hand")
	act.shootStart(bot, root, finish, workspace:GetServerTimeNow())
	local shot = ball:GetAttribute("Move") -- the server may have turned it into a jump shot
	local track = botPlay(bot, shot .. hand, Hoops.animationId(Hoops.animationFor(shot, hand)))
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
			possessionAge = now - bot.possessionAt, mustClear = ball:GetAttribute("MustClear") == true, stamina = stamina[bot],
			mind = bot.mind, rng = math.random,
		})
	else
		bot.possessionAt = nil
		table.clear(bot.queue)
		local hRoot = h and rootOf(h)
		if hRoot then
			local seen = seenLate(bot, h, hRoot)
			local shooting = ball:GetAttribute("GatherAt") ~= nil
			-- a dribble move the handler just started (it might bite)
			local moveName, moveAt = ball:GetAttribute("Move"), ball:GetAttribute("MoveAt")
			local newMove = nil
			if moveAt ~= bot.lastMoveAt then
				bot.lastMoveAt = moveAt
				local move = Hoops.MOVES[moveName or ""]
				newMove = if move and not move.finish then moveName else nil
			end
			out = Brain.defense({
				now = now, me = me, opp = { pos = seen.pos, vel = seen.vel },
				canReach = (hRoot.Position - root.Position).Magnitude <= Hoops.STEAL_RANGE and Hoops.reaches(root.CFrame, heldSpot(hRoot)),
				shooting = shooting, shotKind = moveName, shotAge = serverNow - (moveAt or serverNow),
				newMove = newMove, stamina = stamina[bot], mind = bot.mind, rng = math.random,
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
		botPlay(bot, "StealSwipe", Hoops.animationId("StealSwipe"))
		act.steal(bot, root)
	elseif a.kind == "block" then
		botPlay(bot, "Block", Hoops.animationId("Block"))
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
		hum.WalkSpeed = if bot.stance then Hoops.STANCE_SPEED elseif bot.sprint then Hoops.sprintSpeed(stamina[bot]) else Hoops.WALK_SPEED
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
				botPlay(bot, overlay, Hoops.animationId(overlay), 0.2, true)
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
	for _, t in { shootStarts, nextSteal, reaching, nextBlock, blocking, points, wins, stamina, tiredAt } do
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
