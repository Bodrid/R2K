-- Rules and tuning shared by server and client, plus the pure math (tested in tests/hoops.spec.luau).
-- Distances are studs, times are seconds.
local Hoops = {
	GAME_TO = 21, -- first to this many points wins (shots count 2 or 3)
	CHECK_DELAY = 1, -- after a make, the ball drops through the net, then the other player checks it up
	NEXT_GAME_DELAY = 4, -- the winner is shown this long before a new game starts

	FLOOR_Y = 1, -- court top; sits on a default Baseplate (top at 0) without z-fighting
	BALL_RADIUS = 0.6,
	RIM_Y = 11,
	RIM_Z = -20, -- the hoop is at x = 0; players shoot toward -Z

	-- Fixed broadcast camera, behind the arc looking at the hoop (movement stays relative to it)
	CAMERA_HEIGHT = 22,
	CAMERA_BACK = 52, -- distance behind the rim
	CAMERA_FOV = 55,
	RIM_RADIUS = 1.5,
	THREE_DIST = 20, -- horizontal distance from the rim

	DRIBBLE_HZ = 2, -- bounces per second

	-- Ball path, relative to the holder's HumanoidRootPart
	DRIBBLE_SIDE = 1.255, -- how far out to the side the ball bounces
	DRIBBLE_FORWARD = 0.797,
	DRIBBLE_TOP = -1.422, -- top of the bounce (ball center), below the root
	HAND_LOW = -0.973, -- the dribble hand follows the ball down to here, then waits
	RIG_HIP_HEIGHT = 1.807, -- the calibrated body's hip height; the server warns if players' bodies don't match
	SHOULDER_UP = 0.524, -- a one-hand ball above shoulder height sits on the palm (layups, dunks); below it the hand is on top
	GATHER_HEIGHT = 1.131, -- where the ball sits during the shot windup; the shot launches from here
	GATHER_FORWARD = 1.22, -- in front of the face, in reach of R15 arms
	GATHER_TIME = 0.2, -- seconds to bring the ball up into the shot

	PERFECT_HOLD = 0.6, -- hold shoot this long for a perfect release
	SHOT_WINDOW = 0.3, -- releasing this far off perfect is the worst timing
	GREEN = 0.85, -- timing quality at or above this always goes in
	HOLD_TOLERANCE = 0.15, -- max gap between client and server hold time before the server's wins

	LAYUP_RANGE = 12, -- shooting this close to the rim is a layup (with a jump) instead of a jump shot
	DUNK_RANGE = 5, -- and this close, a dunk

	CONTEST_RANGE = 6,
	STEAL_RANGE = 6, -- steal only does anything this close to the handler
	STEAL_REACH = 2, -- how close the defender's hands must get; small enough that the body shields the far side
	STEAL_UP = 0.018, -- where the reaching hand is at full stretch, from the defender's root
	STEAL_FORWARD = 1.877,
	REACH_TIME = 0.15, -- how long a reach stays live; short, so bounce timing matters
	STEAL_COOLDOWN = 1,
	MAX_BACKDATE = 0.25, -- how far back the server accepts a dribble move's start time (covers ping)
	POKE_SPEED = 14, -- how hard a steal knocks the ball loose
	BLOCK_RANGE = 8, -- block only does anything this close to the ball handler (or a shooter, ball in the air)
	BLOCK_REACH = 1.5, -- how close the raised hands must get to the ball; small, so you have to be in their face
	BLOCK_HEIGHT = 1.791, -- raised hands, above the root (the jump adds to it)
	BLOCK_FORWARD = 0.69,
	BLOCK_TIME = 0.5, -- block animation length, about one jump; the ball is live for contact this long
	BLOCK_COOLDOWN = 1.2,
	SWAT_SPEED = 25, -- how hard a block knocks the ball away
	PASS_DIST = 25, -- passes go this far in the direction you face
	PASS_TIME = 0.35, -- flight time; short, so passes stay flat under Roblox gravity
	PICKUP_RANGE = 4,
	PICKUP_LOCK = 0.5, -- after a shot nobody can grab the ball; after a pass or poke, only the old holder can't
}

-- 1 at a perfect release, falling to 0 at SHOT_WINDOW early or late.
function Hoops.shotQuality(holdTime)
	return math.clamp(1 - math.abs(holdTime - Hoops.PERFECT_HOLD) / Hoops.SHOT_WINDOW, 0, 1)
end

-- 2K-style: greens always go in, otherwise timing, distance and contest set the odds.
function Hoops.makeChance(quality, distance, contested)
	if quality >= Hoops.GREEN then
		return 1
	end
	local base = math.clamp(0.95 - distance * 0.02, 0.25, 0.95) -- layup ~0.9, three ~0.55
	return base * quality * (contested and 0.6 or 1)
end

-- Roblox gravity is strong (196 studs/s²), so real-looking arcs need short flights.
function Hoops.flightTime(distance)
	return 0.45 + distance * 0.012
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
-- Finishes (finish = true: layups, dunks) start there too but end at the release: the ball waits there until
-- the shot goes up, and the shot launches from wherever the ball is. jumpAt: when the animation takes off.
-- Positions are measured from the animations by tools/preview/fit.luau, which rewrites this block; edit
-- timing and hands here, then re-run it.
local S, T, F = Hoops.DRIBBLE_SIDE, Hoops.DRIBBLE_TOP, Hoops.DRIBBLE_FORWARD
-- BEGIN FITTED MOVES
Hoops.MOVES = {
	BehindBack = { switch = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.12, 1.194, -1.428, -0.363, "R" },
		{ 0.26, 0.29, -1.248, -0.698, "R" },
		{ 0.38, -0.349, "floor", -0.079 },
		{ 0.55, -S, T, F, "L" },
	} },
	BetweenLegs = { switch = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.12, 0.696, -1.957, 0.372, "R" },
		{ 0.26, 0, "floor", 0.364, "legs" },
		{ 0.4, -1.328, -1.503, 0.669, "L" },
		{ 0.55, -S, T, F, "L" },
	} },
	Crossover = { switch = true, path = {
		{ 0, S, T, F, "R" },
		{ 0.12, 1.032, -1.435, 0.954, "R" },
		{ 0.25, -0.175, "floor", 0.751 },
		{ 0.38, -1.382, -1.539, 0.549, "L" },
		{ 0.5, -S, T, F, "L" },
	} },
	DoubleTween = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.12, 0.696, -1.957, 0.372, "R" },
		{ 0.26, 0, "floor", 0.364, "legs" },
		{ 0.4, -1.328, -1.503, 0.669, "L" },
		{ 0.52, -0.696, -1.97, 0.36, "L" },
		{ 0.64, 0, "floor", 0.364, "legs" },
		{ 0.76, 1.259, -1.662, 0.57, "R" },
		{ 0.85, S, T, F, "R" },
	} },
	Dunk = { switch = false, finish = true, jumpAt = 0.4, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.182, 1.226, "both" },
		{ 0.32, 0, -1.192, -0.044, "both" },
		{ 0.5, 0, 2.036, 0.055, "both" },
		{ 0.66, 1.02, 1.961, -0.896, "R" },
		{ 0.8, 1.129, 2.23, 1.045, "R" },
	} },
	DunkTwoHand = { switch = false, finish = true, jumpAt = 0.38, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.182, 1.226, "both" },
		{ 0.3, 0, -1.021, -0.339, "both" },
		{ 0.48, 0, 2.137, 0.324, "both" },
		{ 0.64, 0, 1.455, -0.996, "both" },
		{ 0.78, 0, 1.525, 1.34, "both" },
	} },
	Hesitation = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 1.144, -0.364, 0.908, "R" },
		{ 0.32, 1.152, -0.47, 0.942, "R" },
		{ 0.45, 1.2, "floor", 0.875 },
		{ 0.6, S, T, F, "R" },
	} },
	InAndOut = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.14, -0.001, -1.241, 1.148, "R" },
		{ 0.28, 1.628, -1.284, 0.434, "R" },
		{ 0.38, 1.459, "floor", 0.599 },
		{ 0.5, S, T, F, "R" },
	} },
	Layup = { switch = false, finish = true, jumpAt = 0.4, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0, -0.182, 1.226, "both" },
		{ 0.32, 0, 0.174, 1.025, "both" },
		{ 0.5, 1.144, 2.532, 0.04, "R" },
		{ 0.68, 1.06, 2.622, -0.29, "R" },
	} },
	SideStep = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.1, 1.202, "floor", 0.892 },
		{ 0.26, 1.118, -0.094, 1.043, "R" },
		{ 0.42, 0.093, 0.302, 0.898, "both" },
		{ 0.52, 0.039, 0.377, 0.873, "both" },
		{ 0.6, S, T, F, "R" },
	} },
	SideStepEscape = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.077, 1.202, "floor", 0.892 },
		{ 0.2, 1.118, 1.143, 1.043, "R" },
		{ 0.323, 0.093, 0.228, 0.898, "both" },
		{ 0.4, 0.039, 0.346, 0.873, "both" },
		{ 0.462, S, T, F, "R" },
	} },
	SpinEscape = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.1, 1.381, -0.45, -0.26, "R" },
		{ 0.157, 0.859, -0.45, -1.112, "R" },
		{ 0.213, -0.239, -0.45, -1.384, "R" },
		{ 0.27, -0.985, -0.45, -1.001, "R" },
		{ 0.327, -1.392, -0.45, 0.189, "R" },
		{ 0.383, -0.971, -0.45, 1.016, "R" },
		{ 0.44, 0.26, -0.45, 1.381, "R" },
		{ 0.55, S, T, F, "R" },
	} },
	SpinMove = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.15, 0.84, -0.106, -0.968, "R" },
		{ 0.2, 0.388, -0.106, -1.222, "R" },
		{ 0.25, -0.556, -0.106, -1.155, "R" },
		{ 0.3, -0.968, -0.106, -0.84, "R" },
		{ 0.35, -1.222, -0.106, -0.388, "R" },
		{ 0.4, -1.155, -0.106, 0.556, "R" },
		{ 0.45, -0.84, -0.106, 0.968, "R" },
		{ 0.6, S, T, F, "R" },
	} },
	Stepback = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.1, 1.142, "floor", 0.966 },
		{ 0.22, 1.007, -0.402, 1.169, "R" },
		{ 0.42, 0, 0.243, 0.899, "both" },
		{ 0.6, 0, 0.383, 0.855, "both" },
		{ 0.7, S, T, F, "R" },
	} },
	StepbackEscape = { switch = false, path = {
		{ 0, S, T, F, "R" },
		{ 0.09, 1.138, "floor", 0.897 },
		{ 0.22, 0.968, 1.329, 1.041, "R" },
		{ 0.34, 0.968, "floor", 1.041 },
		{ 0.46, 0.968, 1.328, 1.041, "R" },
		{ 0.58, 0, 0.179, 0.899, "both" },
		{ 0.7, 0, 0.372, 0.855, "both" },
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
-- held in both hands (0..1: two-handed gathers and the shot windup).
function Hoops.ballSpot(rootCFrame, hand, move, moveHand, moveAt, gatherAt, now)
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
	-- the jump shot gather (a finish's path already carries the ball up)
	local g = if gatherAt and not finishing then math.clamp((now - gatherAt) / Hoops.GATHER_TIME, 0, 1) else 0
	g = g * g * (3 - 2 * g) -- ease in and out
	return offset(rootCFrame, lerp(right, 0, g), lerp(up, Hoops.GATHER_HEIGHT, g), lerp(forward, Hoops.GATHER_FORWARD, g)), side, math.max(hold, g)
end

-- Where the ball sits during a shot windup; shots launch from here.
function Hoops.gatherSpot(rootCFrame)
	return offset(rootCFrame, 0, Hoops.GATHER_HEIGHT, Hoops.GATHER_FORWARD)
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
