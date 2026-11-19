-- Rules and tuning shared by server and client, plus the pure math (tested in tests/hoops.spec.luau).
-- Distances are studs, times are seconds.
local Hoops = {
	GAME_TO = 21, -- first to this many points wins (shots count 2 or 3)
	CHECK_DELAY = 1, -- after a make, the ball drops through the net, then the other player checks it up
	NEXT_GAME_DELAY = 4, -- the winner is shown this long before a new game starts

	FLOOR_Y = 1, -- court top; sits on a default Baseplate (top at 0) without z-fighting
	COURT_X = 28, -- sidelines at ±COURT_X (the server builds the court from these; the bot stays inside them)
	BASELINE_Z = -25.5, -- just behind the backboard, like a real court
	HALF_Z = 20, -- the half-court line
	BALL_RADIUS = 0.6,
	RIM_Y = 11,
	RIM_Z = -20, -- the hoop is at x = 0; players shoot toward -Z

	-- 2K park camera: behind your player on the line from the rim, looking past them at the hoop
	CAMERA_DISTANCE = 16, -- behind the player
	CAMERA_HEIGHT = 7.5, -- above the player
	CAMERA_LOOK = 0.4, -- looks at a point this far from the player toward the rim
	CAMERA_FOV = 52,
	CAMERA_SMOOTH = 7, -- how quickly it catches up (higher = snappier)

	WALK_SPEED = 15,
	SPRINT_SPEED = 23, -- turbo (R2)
	STANCE_SPEED = 11, -- intense D (L2 on defense): slower, but you slide facing the ball handler
	STANCE_CONTEST = 2, -- intense D contests shots from this much further away

	-- Stamina (0..1), like 2K: sprinting drains it, dribble moves and blocks take a bite, it comes back when
	-- you ease off. Tired, your sprint slows and your green window shrinks.
	STAMINA_SPRINT = 0.11, -- per second of sprinting (about 9s from full to empty)
	STAMINA_MOVE = 0.035, -- per dribble move (escapes cost double), and per block
	STAMINA_REGEN = 0.2, -- per second once you've eased off...
	STAMINA_REGEN_DELAY = 0.75, -- ...for this long
	TIRED = 0.25, -- below this, your sprint slows toward a jog
	RIM_RADIUS = 1.5,
	THREE_DIST = 20, -- horizontal distance from the rim

	DRIBBLE_HZ = 2, -- bounces per second

	-- Ball path, relative to the holder's HumanoidRootPart
	DRIBBLE_SIDE = 1.8385, -- how far out to the side the ball bounces
	DRIBBLE_FORWARD = 0.9573,
	DRIBBLE_TOP = -1.5317, -- top of the bounce (ball center), below the root
	HAND_LOW = -1.0574, -- the dribble hand follows the ball down to here, then waits
	RIG_HIP_HEIGHT = 2, -- the calibrated body's hip height; the server warns if players' bodies don't match
	SHOULDER_UP = 0.763, -- a one-hand ball above shoulder height sits on the palm (layups, dunks); below it the hand is on top

	PERFECT_HOLD = 0.6, -- hold shoot this long for a perfect release
	SHOT_WINDOW = 0.3, -- releasing this far off perfect is the worst timing
	GREEN = 0.85, -- timing quality at or above this always goes in
	HOLD_TOLERANCE = 0.15, -- max gap between client and server hold time before the server's wins

	LAYUP_RANGE = 12, -- shooting this close to the rim is a layup (with a jump) instead of a jump shot
	DUNK_RANGE = 5, -- and this close, a dunk
	SPRINT_DUNK_RANGE = 9, -- on turbo, dunks start from further out (the finish carries you in)
	GLIDE_MAX = 26, -- fastest a finish carries you toward the rim (studs/s)

	CONTEST_RANGE = 6,
	STEAL_RANGE = 6, -- steal only does anything this close to the handler
	STEAL_REACH = 2, -- how close the defender's hands must get; small enough that the body shields the far side
	STEAL_UP = -1.1856, -- where the reaching hand is at full stretch, from the defender's root
	STEAL_FORWARD = 1.6252,
	REACH_TIME = 0.15, -- how long a reach stays live; short, so bounce timing matters
	STEAL_COOLDOWN = 1,
	MAX_BACKDATE = 0.25, -- how far back the server accepts a dribble move's start time (covers ping)
	POKE_SPEED = 14, -- how hard a steal knocks the ball loose
	BLOCK_RANGE = 8, -- block only does anything this close to the ball handler (or a shooter, ball in the air)
	BLOCK_REACH = 1.5, -- how close the raised hands must get to the ball; small, so you have to be in their face
	BLOCK_HEIGHT = 2.2197, -- raised hands, above the root (the jump adds to it)
	BLOCK_FORWARD = 0.8005,
	BLOCK_TIME = 0.5, -- block animation length, about one jump; the ball is live for contact this long
	BLOCK_COOLDOWN = 1.2,
	SWAT_SPEED = 25, -- how hard a block knocks the ball away
	PASS_DIST = 25, -- passes go this far in the direction you face
	PASS_TIME = 0.35, -- flight time; short, so passes stay flat under Roblox gravity
	PICKUP_RANGE = 4,
	PICKUP_LOCK = 0.5, -- after a shot nobody can grab the ball; after a pass or poke, only the old holder can't
}

-- Animations, published by the game's owner (the client plays them on players, the server on the practice bot).
-- Dribble moves, stances, Layup and Dunk are authored from the right hand; "_L" is the left-hand mirror.
-- shortcut: DribbleStance/DefenseStance have no IDs until they're published; outside Studio they don't play until then
Hoops.ANIMATIONS = {
	BehindBack = 97720416461332, BehindBack_L = 110947973652762,
	BetweenLegs = 119329621765672, BetweenLegs_L = 84879209746710,
	Block = 122226333881077,
	Crossover = 95030049810426, Crossover_L = 89350225332049,
	DoubleTween = 90668950670519, DoubleTween_L = 109728765164717,
	Dunk = 116371417778801, Dunk_L = 93055928232785, DunkTwoHand = 86215529812622,
	Hesitation = 115297373334157, Hesitation_L = 127581419750676,
	InAndOut = 125228112161422, InAndOut_L = 82658335277698,
	JumpShot = 84279351689285,
	Layup = 93244724633892, Layup_L = 79293506735548,
	SideStep = 88825168648212, SideStep_L = 134410382844275,
	SideStepEscape = 123156882174859, SideStepEscape_L = 90507189105160,
	SpinEscape = 134644387886968, SpinEscape_L = 71163240371728,
	SpinMove = 128724466317154,
	StealSwipe = 140227535096778,
	Stepback = 106350331428838, Stepback_L = 100781301809205,
	StepbackEscape = 113030727017982, StepbackEscape_L = 130891165327063,
}

-- In Studio, play the animations saved in the place, so edits show without uploading anything: the server copies
-- them (with your Animation Editor saves on top) to ReplicatedStorage.StudioAnimations, and each side registers them
-- for a temporary id. Published games always use the uploaded ids above. Set false to test the uploaded ones in Studio.
Hoops.STUDIO_ANIMATIONS = true
local studioIds = nil -- [name] = temporary id, registered on first use
-- The content id to play an animation by (nil if it has none yet).
function Hoops.animationId(name)
	if Hoops.STUDIO_ANIMATIONS and game:GetService("RunService"):IsStudio() then
		if not studioIds then
			studioIds = {}
			local folder = game:GetService("ReplicatedStorage"):WaitForChild("StudioAnimations", 5)
			local provider = game:GetService("KeyframeSequenceProvider")
			for _, sequence in if folder then folder:GetChildren() else {} do
				local ok, id = pcall(provider.RegisterKeyframeSequence, provider, sequence)
				if ok then
					studioIds[sequence.Name] = id
				end
			end
		end
		if studioIds[name] then
			return studioIds[name]
		end
	end
	local id = Hoops.ANIMATIONS[name]
	return id and `rbxassetid://{id}`
end

-- Every dribble move moves you (a move in place is useless): { delay, direction, speed, seconds }. Directions are
-- from the hand the move starts in: "back", "forward" (toward the basket), "side" (toward the ball hand), "cross"
-- (toward the other hand). Players and the practice bot both use them.
Hoops.DASHES = {
	Crossover = { 0.15, "cross", 15, 0.25 }, -- jab across with the ball
	BetweenLegs = { 0.15, "cross", 12, 0.25 },
	BehindBack = { 0.15, "cross", 14, 0.28 },
	InAndOut = { 0.2, "side", 14, 0.22 }, -- fake across, go back out
	Hesitation = { 0.35, "forward", 16, 0.25 }, -- the pause, then the burst
	DoubleTween = { 0.25, "back", 10, 0.3 }, -- rock back, making a little space
	Stepback = { 0.12, "back", 18, 0.3 },
	StepbackEscape = { 0.1, "back", 20, 0.55 },
	SideStep = { 0.12, "side", 18, 0.3 },
	SideStepEscape = { 0.1, "side", 24, 0.35 },
	SpinMove = { 0.05, "forward", 16, 0.45 },
	SpinEscape = { 0.05, "forward", 20, 0.45 },
}

-- Which way a dash goes, for a holder at cf whose move started with the ball in `hand`.
function Hoops.dashDirection(cf, kind, hand)
	local side = cf.RightVector * (if hand == "Left" then -1 else 1)
	return if kind == "back" then -cf.LookVector elseif kind == "side" then side elseif kind == "cross" then -side else cf.LookVector
end

-- The animation for a move from a given hand: the "_L" mirror from the left, except SpinMove (right only).
function Hoops.animationFor(name, hand)
	return if hand == "Left" and name ~= "SpinMove" and name ~= "DunkTwoHand" and name ~= "JumpShot" then name .. "_L" else name
end

-- 1 at a perfect release, falling to 0 at SHOT_WINDOW early or late. Hold time counts from when the shot's
-- path starts; perfect: this shot's perfect hold (Hoops.perfectHold), default a jump shot's.
function Hoops.shotQuality(holdTime, perfect)
	return math.clamp(1 - math.abs(holdTime - (perfect or Hoops.PERFECT_HOLD)) / Hoops.SHOT_WINDOW, 0, 1)
end

-- When a shot's perfect release is: a jump shot after PERFECT_HOLD at its set point; a layup or dunk right as
-- the ball reaches the top of its path (its release point), so every finish's timing matches its animation.
function Hoops.perfectHold(name)
	local move = Hoops.MOVES[name or ""]
	return if move and move.finish and name ~= "JumpShot" then move.duration else Hoops.PERFECT_HOLD
end

-- The timing quality a green needs: tired, the window shrinks (stamina 0..1, default fresh).
function Hoops.greenAt(stamina)
	return Hoops.GREEN + (1 - (stamina or 1)) * 0.08
end

-- 2K-style: greens always go in, otherwise timing, distance, contest and how tired you are set the odds.
function Hoops.makeChance(quality, distance, contested, stamina)
	if quality >= Hoops.greenAt(stamina) then
		return 1
	end
	local base = math.clamp(0.95 - distance * 0.02, 0.25, 0.95) -- layup ~0.9, three ~0.55
	return base * quality * (contested and 0.6 or 1) * (0.85 + 0.15 * (stamina or 1))
end

-- How fast a sprint goes at this stamina: full speed until you're tired, then down toward a jog.
function Hoops.sprintSpeed(stamina)
	local s = math.clamp((stamina or 1) / Hoops.TIRED, 0, 1)
	return Hoops.WALK_SPEED + (Hoops.SPRINT_SPEED - Hoops.WALK_SPEED) * s
end

-- Roblox gravity is strong (196 studs/s²), so real-looking arcs need short flights.
function Hoops.flightTime(distance, name)
	local f = Hoops.FINISHES[name or ""]
	if f and f.flight then -- straight down through the rim; slower if it went up early, further out
		return f.flight + math.max(distance - 2, 0) * 0.06
	end
	return 0.45 + distance * 0.012 + (f and f.hang or 0)
end

-- A point relative to a character, from its CFrame's own axes (no Roblox globals, so tests can run it).
local function offset(cf, right, up, forward)
	return cf.Position + cf.RightVector * right + cf.UpVector * up + cf.LookVector * forward
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function sideOf(hand)
	return hand == "Left" and -1 or 1
end

-- Dribble moves and finishes: the ball's path, in the holder's body space, as { time, right, up, forward, hand } keyframes.
-- hand: "R" or "L" (that hand has it), "both" (held in two hands), nil (in the air between hands), or "legs"
-- (bouncing between the feet). up = "floor" is a bounce. Authored from the right hand; from the left hand the
-- path is mirrored. Each path starts and ends at the top of the dribble, so moves join it seamlessly.
-- Finishes (finish = true: every shot, i.e. jump shots, layups and dunks) start there too but end at the release:
-- the ball waits there until the shot goes up, and the shot launches from wherever the ball is.
-- jumpAt: when the animation takes off (the character jumps).
-- Positions are measured from the animations by tools/preview/fit.luau, which rewrites this block; edit
-- timing and hands here, then re-run it.
local S, T, F = Hoops.DRIBBLE_SIDE, Hoops.DRIBBLE_TOP, Hoops.DRIBBLE_FORWARD
-- BEGIN FITTED MOVES
Hoops.MOVES = {
	BehindBack = { switch = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.102, 1.7524, -1.4059, -0.5746, "R" },
		{ 0.221, 0.6815, -1.232, -0.8298, "R" },
		{ 0.323, -0.3592, "floor", -0.0918 },
		{ 0.468, -S, T, F, "L" },
	} },
	BetweenLegs = { switch = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.102, 1.1764, -2.0757, 0.4542, "R" },
		{ 0.221, 0, "floor", 0.1711, "legs" },
		{ 0.34, -1.9214, -1.4926, 0.7699, "L" },
		{ 0.468, -S, T, F, "L" },
	} },
	Crossover = { switch = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.102, 1.5728, -1.514, 1.0917, "R" },
		{ 0.212, -0.1983, "floor", 0.8464 },
		{ 0.323, -1.9854, -1.5495, 0.5989, "L" },
		{ 0.425, -S, T, F, "L" },
	} },
	DoubleTween = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.102, 1.1764, -2.0757, 0.4542, "R" },
		{ 0.221, 0, "floor", 0.1711, "legs" },
		{ 0.34, -1.9214, -1.4926, 0.7699, "L" },
		{ 0.442, -1.1764, -2.0913, 0.4412, "L" },
		{ 0.544, 0, "floor", 0.1711, "legs" },
		{ 0.646, 1.8461, -1.7666, 0.6958, "R" },
		{ 0.723, S, T, F, "R" },
	} },
	Dunk = { switch = false, finish = true, jumpAt = 0.4, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.32, 0, -1.2501, -0.083, "both" },
		{ 0.5, 0, 2.6498, 0.2024, "both" },
		{ 0.66, 1.5669, 2.0276, -1.2077, "R" },
		{ 0.8, 1.7526, 2.5778, 1.628, "R" },
	} },
	DunkTomahawk = { switch = false, finish = true, jumpAt = 0.45, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.32, 0, -1.1409, -0.2182, "both" },
		{ 0.48, 0, 2.701, 0.3462, "both" },
		{ 0.66, 1.5788, 1.8008, -1.1417, "R" },
		{ 0.84, 1.7541, 2.31, 1.7848, "R" },
	} },
	DunkTwoHand = { switch = false, finish = true, jumpAt = 0.38, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.3, 0, -1.0216, -0.3785, "both" },
		{ 0.48, 0, 2.7041, 0.4814, "both" },
		{ 0.64, 0, 1.8677, -1.3805, "both" },
		{ 0.78, 0, 1.7891, 1.9362, "both" },
	} },
	EuroStep = { switch = false, finish = true, jumpAt = 0.55, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.3, 0.9437, -0.2975, 1.1772, "both" },
		{ 0.48, -1.0393, 0.1474, 1.1692, "both" },
		{ 0.6, 1.4452, 3.2987, 0.2473, "R" },
		{ 0.78, 1.4287, 3.4753, -0.1255, "R" },
	} },
	Floater = { switch = false, finish = true, jumpAt = 0.28, path = {
		{ 0, S, T, F, "R" },
		{ 0.12, 0, -0.1749, 1.4906, "both" },
		{ 0.25, 0, 0.7969, 1.2032, "both" },
		{ 0.38, 1.3945, 2.8588, 0.7778, "R" },
		{ 0.5, 1.5, 3.226, 0.2443, "R" },
	} },
	Hesitation = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 1.7498, -0.3143, 1.1165, "R" },
		{ 0.32, 1.7573, -0.4383, 1.144, "R" },
		{ 0.45, 1.795, "floor", 1.0573 },
		{ 0.6, S, T, F, "R" },
	} },
	HopStep = { switch = false, finish = true, jumpAt = 0.55, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.3, 0, 1.0115, 1.3612, "both" },
		{ 0.45, 0, -0.3011, 1.5025, "both" },
		{ 0.58, 0, 2.4443, 0.8945, "both" },
		{ 0.75, 0, 2.2591, 1.5919, "both" },
	} },
	InAndOut = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.119, 0.2782, -1.3779, 1.469, "R" },
		{ 0.238, 2.2756, -1.3239, 0.3729, "R" },
		{ 0.323, 2.0769, "floor", 0.6385 },
		{ 0.425, S, T, F, "R" },
	} },
	JumpShot = { switch = false, finish = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.2, 0, 0.5119, 1.1189, "both" },
		{ 0.35, 0, 1.5808, 1.3622, "both" },
	} },
	Layup = { switch = false, finish = true, jumpAt = 0.4, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.32, 0, 0.1378, 1.4013, "both" },
		{ 0.5, 1.744, 3.1316, 0.2473, "R" },
		{ 0.68, 1.6321, 3.3687, -0.1181, "R" },
	} },
	ReverseLayup = { switch = false, finish = true, jumpAt = 0.42, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.3172, 1.5421, "both" },
		{ 0.3, 0, 0.1378, 1.4013, "both" },
		{ 0.45, 1.7524, 3.1322, 0.2127, "R" },
		{ 0.68, 2.127, 2.8984, -0.105, "R" },
	} },
	SideStep = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.1, 1.7695, "floor", 1.1025 },
		{ 0.26, 1.659, -0.0898, 1.3348, "R" },
		{ 0.42, 0.103, 0.3105, 1.2667, "both" },
		{ 0.52, 0.0433, 0.4026, 1.2392, "both" },
		{ 0.6, S, T, F, "R" },
	} },
	SideStepEscape = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.077, 1.7694, "floor", 1.1026 },
		{ 0.2, 1.659, -0.0461, 1.3348, "R" },
		{ 0.323, 0.103, 0.2231, 1.2667, "both" },
		{ 0.4, 0.0433, 0.3662, 1.2392, "both" },
		{ 0.462, S, T, F, "R" },
	} },
	SpinEscape = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.1, 1.9245, -0.5077, -0.4969, "R" },
		{ 0.157, 1.1084, -0.5077, -1.6498, "R" },
		{ 0.213, -0.4672, -0.5077, -1.9319, "R" },
		{ 0.27, -1.4848, -0.5077, -1.3214, "R" },
		{ 0.327, -1.9475, -0.5077, 0.3975, "R" },
		{ 0.383, -1.2753, -0.5077, 1.5246, "R" },
		{ 0.44, 0.4969, -0.5077, 1.9245, "R" },
		{ 0.55, S, T, F, "R" },
	} },
	SpinMove = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 1.1459, -0.045, -1.5, "R" },
		{ 0.2, 0.458, -0.045, -1.8312, "R" },
		{ 0.25, -0.9235, -0.045, -1.6463, "R" },
		{ 0.3, -1.5, -0.045, -1.1459, "R" },
		{ 0.35, -1.8312, -0.045, -0.458, "R" },
		{ 0.4, -1.6463, -0.045, 0.9235, "R" },
		{ 0.45, -1.1459, -0.045, 1.5, "R" },
		{ 0.6, S, T, F, "R" },
	} },
	Stepback = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.1, 1.7099, "floor", 1.1734 },
		{ 0.22, 1.5555, -0.3855, 1.4327, "R" },
		{ 0.42, 0, 0.2412, 1.267, "both" },
		{ 0.6, 0, 0.4128, 1.2191, "both" },
		{ 0.7, S, T, F, "R" },
	} },
	StepbackEscape = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.09, 1.7002, "floor", 1.1137 },
		{ 0.22, 1.5004, 1.4227, 1.3397, "R" },
		{ 0.34, 1.5005, "floor", 1.3394 },
		{ 0.46, 1.5005, 1.4223, 1.3391, "R" },
		{ 0.58, 0, 0.1658, 1.2668, "both" },
		{ 0.7, 0, 0.3993, 1.2191, "both" },
		{ 0.8, S, T, F, "R" },
	} },
}
-- END FITTED MOVES
local HAND = { R = { 1, 0 }, L = { -1, 0 }, both = { 0, 1 } }
for _, move in Hoops.MOVES do
	move.duration = move.path[#move.path][1]
	move.hands = {}
	for i, k in move.path do
		move.hands[i] = HAND[k[5]]
	end
	for i, k in move.path do
		if not HAND[k[5]] then -- in the air: between the hands it left and the one it's going to
			local before, after = move.hands[i - 1] or move.hands[i + 1], move.hands[i + 1] or move.hands[i - 1]
			move.hands[i] = { (before[1] + after[1]) / 2, (before[2] + after[2]) / 2 }
		end
	end
end

-- The finishing package (2K's layup package, and dunks). For each finish: range, how close to the rim it can start;
-- dunk; glide, where the game carries the finisher while it plays: waypoints { time, across, short }, short =
-- studs short of the rim along the line they came in on (negative: past it, under the rim), across = studs to the
-- ball-hand side. A finisher never backs away from the rim to reach one. flight: the shot's air time (a dunk
-- goes straight down through), hang: extra air time (a floater's high arc).
Hoops.FINISHES = {
	Layup = { range = Hoops.LAYUP_RANGE, glide = { { 0.4, 0, 3.5 }, { 0.68, 0, 2.2 } } },
	EuroStep = { range = Hoops.LAYUP_RANGE, glide = { { 0.3, 1.8, 6 }, { 0.55, -1.2, 3.5 }, { 0.78, -1, 2.4 } } },
	HopStep = { range = Hoops.LAYUP_RANGE, glide = { { 0.35, 0, 4.5 }, { 0.55, 0, 3.6 }, { 0.75, 0, 2.6 } } },
	ReverseLayup = { range = Hoops.LAYUP_RANGE, glide = { { 0.42, 0.8, 0.6 }, { 0.68, 0.5, -1.6 } } },
	Floater = { range = Hoops.LAYUP_RANGE, glide = { { 0.28, 0, 7.5 }, { 0.5, 0, 6.6 } }, hang = 0.35 },
	Dunk = { range = Hoops.SPRINT_DUNK_RANGE, dunk = true, glide = { { 0.4, 0, 3 }, { 0.8, 0, 1.7 } }, flight = 0.22 },
	DunkTwoHand = { range = Hoops.SPRINT_DUNK_RANGE, dunk = true, glide = { { 0.38, 0, 3 }, { 0.78, 0, 1.9 } }, flight = 0.22 },
	DunkTomahawk = { range = Hoops.SPRINT_DUNK_RANGE, dunk = true, glide = { { 0.45, 0, 3.2 }, { 0.84, 0, 1.7 } }, flight = 0.22 },
}

-- Vectors here use the global Vector3 (the tests provide one), always flat on the finisher's height.
local function flatXZ(v, y)
	return Vector3.new(v.X, y, v.Z)
end

-- Which finish a shot from `pos` becomes, 2K style. stick: the pro-stick move flicked with turbo on near the rim
-- (up: dunk or layup, sideways: euro step, down: hop step, spin: reverse, double tween: floater), or nil and
-- it's picked for the situation. defender: the nearest defender's position, or nil.
function Hoops.pickFinish(pos, defender, sprinting, stick, rng)
	local toRim = Vector3.new(0, pos.Y, Hoops.RIM_Z) - flatXZ(pos, pos.Y)
	local dist = toRim.Magnitude
	if dist > Hoops.LAYUP_RANGE then
		return "JumpShot"
	end
	local canDunk = dist <= (if sprinting then Hoops.SPRINT_DUNK_RANGE else Hoops.DUNK_RANGE)
	local function dunk()
		local r = rng()
		return if sprinting and r < 0.35 then "DunkTomahawk" elseif r < 0.6 then "Dunk" else "DunkTwoHand"
	end
	if stick then
		if stick == "Hesitation" then
			return if canDunk then dunk() else "Layup"
		end
		return if stick:find("Stepback") then "HopStep" elseif stick:find("Spin") then "ReverseLayup" elseif stick == "DoubleTween" then "Floater" else "EuroStep"
	end
	local gap = defender and flatXZ(defender, pos.Y) - flatXZ(pos, pos.Y)
	local inTheWay = gap ~= nil and gap.Magnitude < 5 and dist > 0.5 and gap.Magnitude > 0.1 and gap.Unit:Dot(toRim.Unit) > 0.7
	if canDunk and not (inTheWay and gap.Magnitude < 2.5) then
		return dunk()
	elseif pos.Z < Hoops.RIM_Z + 1.5 then -- along the baseline: under the rim and up the other side
		return "ReverseLayup"
	elseif inTheWay then -- float it over them from out there, or step around them up close
		return if dist > 7 then "Floater" else "EuroStep"
	elseif gap and gap.Magnitude < 4 then -- body on body: power it up off two feet
		return "HopStep"
	end
	return "Layup"
end

-- Where a finish carries someone who starts it at `from` with the ball in `hand`: { { time, position } }, flat
-- at from's height, timed from the start of the finish.
function Hoops.finishGlide(name, hand, from)
	local f, out = Hoops.FINISHES[name], {}
	if not f then
		return out
	end
	local rim = Vector3.new(0, from.Y, Hoops.RIM_Z)
	local back = flatXZ(from, from.Y) - rim
	local short = back.Magnitude
	back = if short > 0.1 then back / short else Vector3.new(0, 0, 1)
	local side = Vector3.new(back.Z, 0, -back.X) * (if hand == "Left" then -1 else 1) -- ball-hand side, facing the rim
	for i, w in f.glide do
		short = math.min(w[3], short)
		out[i] = { w[1], rim + back * short + side * w[2] }
	end
	return out
end

-- The ball's spot on a move's path `t` seconds in (right-hand version). Falling to the floor speeds up and
-- rising off it slows down, like a real bounce; everything else eases in and out.
local function onPath(path, hands, t, floorUp)
	local function height(k)
		return if k[3] == "floor" then floorUp else k[3]
	end
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		if t <= b[1] or i == #path then
			local u = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
			local bounce = a[3] == "floor" or b[3] == "floor"
			local across = if bounce then u else u * u * (3 - 2 * u)
			local fall = if b[3] == "floor" then u * u elseif a[3] == "floor" then 1 - (1 - u) * (1 - u) else across
			local ha, hb = hands[i - 1], hands[i]
			return lerp(a[2], b[2], across), lerp(height(a), height(b), fall), lerp(a[4], b[4], across), lerp(ha[1], hb[1], across), lerp(ha[2], hb[2], across)
		end
	end
end

-- Where a held ball is at server time `now`. Times come from the shared server clock, so the server
-- and every client get the same answer: clients draw it, the server judges steals and blocks with it.
--   hand: the hand it's in (after the current move), move/moveHand/moveAt: the dribble move under way,
--   the hand it started from, and when (with no move, moveAt is when the dribble started)
-- Also returns, for the arms, which hand has it (+1 right, -1 left, between = in the air) and how much it's
-- held in both hands (0..1: two-handed gathers and shots).
function Hoops.ballSpot(rootCFrame, hand, move, moveHand, moveAt, now)
	local floorUp = Hoops.FLOOR_Y + Hoops.BALL_RADIUS - rootCFrame.Position.Y -- root stays upright, so its up is world up
	local m = move and Hoops.MOVES[move]
	local finishing = m and m.finish
	local right, up, forward, side, hold
	if m and (finishing or now < moveAt + m.duration) then
		right, up, forward, side, hold = onPath(m.path, m.hands, now - moveAt, floorUp)
		right *= sideOf(moveHand)
		side *= sideOf(moveHand)
	else
		-- Dribbling: |cos| snaps the ball off the floor and lets it float near the hand; the first
		-- bounce starts at the top right when the move (or possession) ends.
		local since = now - moveAt - (if m then m.duration else 0)
		local s = 1 - math.abs(math.cos(math.pi * Hoops.DRIBBLE_HZ * since))
		right, up, forward, side, hold = sideOf(hand) * S, lerp(T, floorUp, s), F, sideOf(hand), 0
	end
	return offset(rootCFrame, right, up, forward), side, hold
end

-- Pro stick (right stick) gesture -> dribble move, like 2K. x, y: where the flick went (x right, y toward the
-- basket), turned: degrees the stick swept round, held: seconds it was held, ballSide: +1 ball in the right
-- hand, -1 left, escape: L2 held. Returns a move name.
function Hoops.proStick(x, y, turned, held, ballSide, escape)
	if math.abs(turned) >= 150 then -- a half circle
		return if escape then "SpinEscape" else "SpinMove"
	end
	-- angle 0 = toward the ball hand's side, 90 = toward the basket, 180 = toward the other hand, -90 = back
	local angle = math.deg(math.atan2(y, x * ballSide))
	if angle > 45 and angle <= 135 then
		return "Hesitation"
	elseif angle > 135 or angle <= -157.5 then
		return "Crossover"
	elseif angle <= -112.5 then
		return "BetweenLegs"
	elseif angle <= -67.5 then
		return if escape then "StepbackEscape" else "Stepback"
	elseif angle <= -22.5 then
		return "BehindBack"
	elseif escape then
		return "SideStepEscape"
	end
	return if held >= 0.2 then "SideStep" else "InAndOut" -- toward the ball hand: flick it, or hold it
end

-- Can the defender's reaching hand touch a ball at `spot`?
function Hoops.reaches(defenderCFrame, spot)
	return (spot - offset(defenderCFrame, 0, Hoops.STEAL_UP, Hoops.STEAL_FORWARD)).Magnitude <= Hoops.STEAL_REACH
end

-- Between a blocker's raised hands. Clients draw the hands here; the server judges blocks from it.
function Hoops.blockHands(blockerCFrame)
	return offset(blockerCFrame, 0, Hoops.BLOCK_HEIGHT, Hoops.BLOCK_FORWARD)
end

-- Can a blocker's raised hands touch a ball at `spot`?
function Hoops.blocks(blockerCFrame, spot)
	return (spot - Hoops.blockHands(blockerCFrame)).Magnitude <= Hoops.BLOCK_REACH
end

-- Velocity that lands on `to` after `t` seconds: to = from + v*t + gravity*t²/2.
function Hoops.launchVelocity(from, to, t, gravity)
	return (to - from) / t - gravity * (t / 2)
end

return Hoops
