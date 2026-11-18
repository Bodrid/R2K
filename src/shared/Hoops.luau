-- Rules and tuning shared by server and client, plus the pure math (tested in tests/hoops.spec.luau).
-- Distances are studs, times are seconds.
local Hoops = {
	FLOOR_Y = 1, -- court top; sits on a default Baseplate (top at 0) without z-fighting
	BALL_RADIUS = 0.6,
	RIM_Y = 11,
	RIM_RADIUS = 1.5,
	THREE_DIST = 20, -- horizontal distance from the rim

	DRIBBLE_HZ = 2, -- bounces per second
	CROSS_TIME = 0.18, -- how long a crossover takes

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

	CONTEST_RANGE = 6,
	STEAL_RANGE = 6, -- steal only does anything this close to the handler
	STEAL_REACH = 2, -- how close the defender's hands must get; small enough that the body shields the far side
	REACH_TIME = 0.15, -- how long a reach stays live; short, so bounce timing matters
	STEAL_COOLDOWN = 1,
	MAX_BACKDATE = 0.25, -- how far back the server accepts a crossover start time (covers ping)
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

-- Where a held ball is at server time `now`. Times come from the shared server clock, so the server
-- and every client get the same answer: clients draw it, the server judges steals with it.
-- Also returns crossover progress `a` (1 = done) and gather progress `g` (0..1, eased) for the arms.
function Hoops.ballSpot(rootCFrame, hand, fromHand, crossAt, gatherAt, now)
	local a = math.clamp((now - crossAt) / Hoops.CROSS_TIME, 0, 1)
	-- s: 0 = top of the bounce, 1 = on the floor. A crossover is one low bounce; a dribble uses |cos|
	-- so the ball snaps off the floor and floats near the hand.
	local s = if a < 1 then math.sin(math.pi * a) else 1 - math.abs(math.cos(math.pi * Hoops.DRIBBLE_HZ * (now - crossAt - Hoops.CROSS_TIME)))
	local g = if gatherAt then math.clamp((now - gatherAt) / Hoops.GATHER_TIME, 0, 1) else 0
	g = g * g * (3 - 2 * g) -- ease in and out
	local floorUp = Hoops.FLOOR_Y + Hoops.BALL_RADIUS - rootCFrame.Position.Y -- root stays upright, so its up is world up
	local right = lerp(sideOf(fromHand), sideOf(hand), a) * Hoops.DRIBBLE_SIDE
	local up = lerp(Hoops.DRIBBLE_TOP, floorUp, s)
	return offset(rootCFrame, lerp(right, 0, g), lerp(up, Hoops.GATHER_HEIGHT, g), lerp(Hoops.DRIBBLE_FORWARD, Hoops.GATHER_FORWARD, g)), a, g
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
