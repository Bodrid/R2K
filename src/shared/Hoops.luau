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
	DRIBBLE_SIDE = 1.5, -- how far out to the side the ball bounces
	DRIBBLE_FORWARD = 1.2,
	DRIBBLE_TOP = -0.6, -- top of the bounce (ball center), below the root
	HAND_LOW = -0.8, -- the dribble hand follows the ball down to here, then waits
	GATHER_HEIGHT = 3.2, -- where the ball sits during the shot windup; the shot launches from here
	GATHER_FORWARD = 1.2, -- in front of the face, in reach of R15 arms
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
	REACH_TIME = 0.15, -- how long a reach stays live; short, so bounce timing matters
	STEAL_COOLDOWN = 1,
	MAX_BACKDATE = 0.25, -- how far back the server accepts a dribble move's start time (covers ping)
	POKE_SPEED = 14, -- how hard a steal knocks the ball loose
	BLOCK_RANGE = 8, -- block only does anything this close to the ball handler (or a shooter, ball in the air)
	BLOCK_REACH = 1.5, -- how close the raised hands must get to the ball; small, so you have to be in their face
	BLOCK_HEIGHT = 3.6, -- raised hands, above the root (the jump adds to it)
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

-- Dribble moves: the ball's path, in the holder's body space, as { time, right, up, forward } keyframes.
-- Authored from the right hand; from the left hand the path is mirrored (right negated). Each path starts
-- at the top of the right-hand bounce and ends at the top of the bounce on the side it finishes, so the
-- dribble picks up seamlessly. Times match the move's animation (tests check it). up = "floor" is a bounce.
local S, T, F = Hoops.DRIBBLE_SIDE, Hoops.DRIBBLE_TOP, Hoops.DRIBBLE_FORWARD
local CHEST = 0.6 -- ball held at the chest (two hands), above the root

local function scaled(path, factor)
	local out = {}
	for i, k in path do
		out[i] = { k[1] * factor, k[2], k[3], k[4] }
	end
	return out
end

-- Spins: the ball, pulled in tight, turns with the body. keys = { time, degrees turned (clockwise) } from the animation.
local function spinPath(keys)
	local function turnAt(t)
		for i = 2, #keys do
			if t <= keys[i][1] then
				return keys[i - 1][2] + (keys[i][2] - keys[i - 1][2]) * (t - keys[i - 1][1]) / (keys[i][1] - keys[i - 1][1])
			end
		end
		return keys[#keys][2]
	end
	local path = { { 0, S, T, F } }
	local t0, t1 = keys[2][1], keys[#keys - 1][1]
	for i = 0, 6 do
		local t = t0 + (t1 - t0) * i / 6
		local a = math.rad(turnAt(t))
		local r, f = 0.7, 0.8 -- tucked at the right hip, slightly in front
		table.insert(path, { t, r * math.cos(a) + f * math.sin(a), -0.1, -r * math.sin(a) + f * math.cos(a) })
	end
	table.insert(path, { keys[#keys][1], S, T, F })
	return path
end

local STEPBACK = { -- pound it on the plant, carry it up through the hop, land gathered at the chest
	{ 0, S, T, F },
	{ 0.1, S, "floor", 1.4 },
	{ 0.22, 0.6, 0, 0.9 },
	{ 0.42, 0, CHEST, 0.9 },
	{ 0.6, 0, CHEST, 0.9 },
	{ 0.7, S, T, F },
}
local SIDESTEP = {
	{ 0, S, T, F },
	{ 0.1, 1.6, "floor", 1.3 },
	{ 0.26, 0.5, 0.3, 0.9 },
	{ 0.42, 0, CHEST, 0.9 },
	{ 0.52, 0, CHEST, 0.9 },
	{ 0.6, S, T, F },
}

Hoops.MOVES = {
	Crossover = { switch = true, path = { -- one low bounce across the front
		{ 0, S, T, F },
		{ 0.12, 1.3, -0.9, 1.3 },
		{ 0.25, 0, "floor", 1.5 },
		{ 0.38, -1.3, -0.8, 1.3 },
		{ 0.5, -S, T, F },
	} },
	BetweenLegs = { switch = true, path = { -- bounce through the gap under the front (left) leg, caught behind it
		{ 0, S, T, F },
		{ 0.12, 1, -1.2, 0.8 },
		{ 0.26, -0.2, "floor", 0.4 },
		{ 0.4, -1.4, -1, 0.6 },
		{ 0.55, -S, T, F },
	} },
	DoubleTween = { switch = false, path = { -- through the legs and straight back
		{ 0, S, T, F },
		{ 0.12, 1, -1.2, 0.8 },
		{ 0.26, -0.2, "floor", 0.4 },
		{ 0.4, -1.4, -1, 0.6 },
		{ 0.52, -1, -1.2, 0.8 },
		{ 0.64, 0.2, "floor", 0.4 },
		{ 0.76, 1.4, -1, 0.8 },
		{ 0.85, S, T, F },
	} },
	BehindBack = { switch = true, path = { -- pulled back past the hip, wrapped behind, bounced out on the left
		{ 0, S, T, F },
		{ 0.12, 1.5, -1, -0.2 },
		{ 0.26, 0.2, -1.2, -1 },
		{ 0.38, -1.2, "floor", 0.2 },
		{ 0.55, -S, T, F },
	} },
	InAndOut = { switch = false, path = { -- pulled in like a crossover, snapped back out, pushed wide
		{ 0, S, T, F },
		{ 0.14, 0.4, -1, 1.3 },
		{ 0.28, 1.6, -1.2, 1.2 },
		{ 0.38, 1.7, "floor", 1.4 },
		{ 0.5, S, T, F },
	} },
	Hesitation = { switch = false, path = { -- carried high while the body rises, then pounded forward on the burst
		{ 0, S, T, F },
		{ 0.15, 1.5, -0.2, 1 },
		{ 0.32, 1.5, -0.1, 1 },
		{ 0.45, 1.6, "floor", 1.6 },
		{ 0.6, S, T, F },
	} },
	Stepback = { switch = false, path = STEPBACK },
	StepbackEscape = { switch = false, path = { -- two hops: pound, carry, pound, carry up, land gathered
		{ 0, S, T, F },
		{ 0.09, S, "floor", 1.4 },
		{ 0.22, 1.4, -0.8, 1 },
		{ 0.34, S, "floor", 1.2 },
		{ 0.46, 0.6, 0.2, 0.9 },
		{ 0.58, 0, CHEST, 0.9 },
		{ 0.7, 0, CHEST, 0.9 },
		{ 0.8, S, T, F },
	} },
	SideStep = { switch = false, path = SIDESTEP },
	SideStepEscape = { switch = false, path = scaled(SIDESTEP, 1 / 1.3) }, -- same move, 1.3x faster
	SpinMove = { switch = false, path = spinPath({ { 0, 0 }, { 0.15, 90 }, { 0.3, 180 }, { 0.45, 270 }, { 0.6, 360 } }) },
	SpinEscape = { switch = false, path = spinPath({ { 0, 0 }, { 0.1, 60 }, { 0.22, 150 }, { 0.34, 240 }, { 0.44, 330 }, { 0.55, 360 } }) },
}
for _, move in Hoops.MOVES do
	move.duration = move.path[#move.path][1]
end

-- The ball's spot on a move's path `t` seconds in (right-hand version). Falling to the floor speeds up and
-- rising off it slows down, like a real bounce; everything else eases in and out.
local function onPath(path, t, floorUp)
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
			return lerp(a[2], b[2], across), lerp(height(a), height(b), fall), lerp(a[4], b[4], across)
		end
	end
end

-- Where a held ball is at server time `now`. Times come from the shared server clock, so the server
-- and every client get the same answer: clients draw it, the server judges steals and blocks with it.
--   hand: the hand it's in (after the current move), move/moveHand/moveAt: the dribble move under way,
--   the hand it started from, and when (with no move, moveAt is when the dribble started)
-- Also returns the ball's sideways position (+ right) and the shot-gather progress (0..1), for the arms.
function Hoops.ballSpot(rootCFrame, hand, move, moveHand, moveAt, gatherAt, now)
	local floorUp = Hoops.FLOOR_Y + Hoops.BALL_RADIUS - rootCFrame.Position.Y -- root stays upright, so its up is world up
	local m = move and Hoops.MOVES[move]
	local right, up, forward
	if m and now < moveAt + m.duration then
		right, up, forward = onPath(m.path, now - moveAt, floorUp)
		right *= sideOf(moveHand)
	else
		-- Dribbling: |cos| snaps the ball off the floor and lets it float near the hand; the first
		-- bounce starts at the top right when the move (or possession) ends.
		local since = now - moveAt - (if m then m.duration else 0)
		local s = 1 - math.abs(math.cos(math.pi * Hoops.DRIBBLE_HZ * since))
		right, up, forward = sideOf(hand) * S, lerp(T, floorUp, s), F
	end
	local g = if gatherAt then math.clamp((now - gatherAt) / Hoops.GATHER_TIME, 0, 1) else 0
	g = g * g * (3 - 2 * g) -- ease in and out
	right = lerp(right, 0, g)
	return offset(rootCFrame, right, lerp(up, Hoops.GATHER_HEIGHT, g), lerp(forward, Hoops.GATHER_FORWARD, g)), right, g
end

-- Where the ball sits during a shot windup; shots launch from here.
function Hoops.gatherSpot(rootCFrame)
	return offset(rootCFrame, 0, Hoops.GATHER_HEIGHT, Hoops.GATHER_FORWARD)
end

-- Can the defender's hands (just in front of them) touch a ball at `spot`?
function Hoops.reaches(defenderCFrame, spot)
	return (spot - offset(defenderCFrame, 0, 0, 1.5)).Magnitude <= Hoops.STEAL_REACH
end

-- Between a blocker's raised hands. Clients draw the hands here; the server judges blocks from it.
function Hoops.blockHands(blockerCFrame)
	return offset(blockerCFrame, 0, Hoops.BLOCK_HEIGHT, 0.4)
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
