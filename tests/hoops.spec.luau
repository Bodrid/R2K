-- Run: lune run tests/hoops.spec   (pure math only; gameplay is checked in Studio)
local Hoops = require("../src/shared/Hoops")

assert(Hoops.shotQuality(Hoops.PERFECT_HOLD) == 1, "perfect hold is quality 1")
assert(Hoops.shotQuality(0) == 0 and Hoops.shotQuality(5) == 0, "way off is quality 0")
assert(Hoops.shotQuality(0 / 0) ~= 1, "NaN hold time is never a perfect release")

assert(Hoops.makeChance(1, 40, true) == 1, "green always goes in")
assert(Hoops.makeChance(0, 2, false) == 0, "awful timing never goes in")
local open = Hoops.makeChance(0.8, 10, false)
assert(Hoops.makeChance(0.8, 10, true) < open, "a contest lowers the odds")
assert(Hoops.makeChance(0.8, 25, false) < open, "longer shots are harder")

-- The arc must land on the rim after t seconds and be falling when it gets there.
local from, to = vector.create(0, 7, 0), vector.create(3, Hoops.RIM_Y, -20)
local gravity = vector.create(0, -196.2, 0)
local t = Hoops.flightTime(vector.magnitude(to - from))
local v = Hoops.launchVelocity(from, to, t, gravity)
local landed = from + v * t + gravity * (t * t / 2)
assert(vector.magnitude(landed - to) < 0.01, "arc lands on the target")
assert((v + gravity * t).y < 0, "ball is falling at the rim")

-- Held ball path. The handler stands at x=0, z=0 facing -Z, root at normal height above the floor.
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Y = Hoops.FLOOR_Y + Hoops.RIG_HIP_HEIGHT + 1 -- standing root height of the calibrated rig (hip height + half the root)
local handler = CFrame.lookAt(Vector3.new(0, Y, 0), Vector3.new(0, Y, -1))
local T = 1000 -- any server time
local function spot(hand, move, moveHand, moveAt, now)
	return (Hoops.ballSpot(handler, hand, move, moveHand, moveAt, now))
end
local function near(a, b)
	return (a - b).Magnitude < 1e-3
end
local floorY = Hoops.FLOOR_Y + Hoops.BALL_RADIUS
local right = spot("Right", nil, nil, T, T) -- a new dribble: top of the bounce, right side
local left = spot("Left", nil, nil, T, T)
local low = spot("Right", nil, nil, T, T + 0.5 / Hoops.DRIBBLE_HZ) -- half a bounce later
assert(right.X > 0 and left.X < 0, "hand picks the side")
assert(math.abs(right.Y - (Y + Hoops.DRIBBLE_TOP)) < 1e-3, "a new dribble starts at the top")
assert(math.abs(low.Y - floorY) < 1e-3, "half a bounce later the ball is on the floor")

-- Dribble moves: every path joins the dribble cleanly at both ends and lasts as long as its animation.
local fs = require("@lune/fs")
for name, move in Hoops.MOVES do
	local endHand = if move.switch then "Left" else "Right"
	for i = 2, #move.path do
		assert(move.path[i][1] > move.path[i - 1][1], `{name}: path times go forward`)
	end
	assert(near(spot(endHand, name, "Right", T, T), right), `{name}: starts at the top of the dribble`)
	local before, after = spot(endHand, name, "Right", T, T + move.duration - 1e-6), spot(endHand, name, "Right", T, T + move.duration)
	if move.finish then -- a finish waits at its release point until the shot goes up (even mid-windup)
		assert(near(spot(endHand, name, "Right", T, T + move.duration + 0.5), after), `{name}: waits at the release point`)
		assert(not move.jumpAt or move.jumpAt < move.duration, `{name}: takes off before the release`)
	else
		assert(near(before, after) and near(after, if move.switch then left else right), `{name}: hands back to the dribble on the right side`)
	end
	local mirrored = spot(if move.switch then "Right" else "Left", name, "Left", T, T + move.duration / 2)
	local original = spot(endHand, name, "Right", T, T + move.duration / 2)
	assert(near(mirrored, Vector3.new(-original.X, original.Y, original.Z)), `{name}: the left-hand version is a mirror`)
	local animation = roblox.deserializeModel(fs.readFile(`assets/animations/{name}.rbxmx`))[1]
	local length = 0
	for _, keyframe in animation:GetChildren() do
		length = math.max(length, keyframe.Time)
	end
	if move.finish then
		assert(move.duration < length, `{name}: releases before its animation ends`)
	else
		assert(math.abs(length - move.duration) < 0.01, `{name}: ball path lasts {move.duration}s but the animation lasts {length}s`)
	end
end
local crossBounce = spot("Left", "Crossover", "Right", T, T + 0.25)
assert(math.abs(crossBounce.X) < 0.35 and crossBounce.Z < 0 and math.abs(crossBounce.Y - floorY) < 1e-3, "a crossover bounces in front, between the feet (hips are 0.35 either side)")
assert(spot("Left", "BehindBack", "Right", T, T + 0.26).Z > 0, "a behind-the-back goes behind the body")
-- Top of the head above the root, standing, from the calibrated rig (root -> lower torso -> upper torso -> head).
local rig = require("@lune/serde").decode("json", fs.readFile("tools/preview/r15-rig.json"))
local HEAD_TOP = rig.sizes.Head[2] / 2
for _, j in rig.joints do
	if j.name == "LowerTorso" or j.name == "UpperTorso" or j.name == "Head" then
		HEAD_TOP += j.c0[2] - j.c1[2]
	end
end
local function headTop(spotAt) -- how far above the top of the head a ball is
	return spotAt.Y - Y - HEAD_TOP
end
assert(headTop(spot("Right", "Dunk", "Right", T, T + 0.5)) > 0, "a dunk takes the ball up over the head")
assert(headTop(spot("Right", "Layup", "Right", T, T + Hoops.MOVES.Layup.duration)) > -0.5, "a layup releases up high at full stretch")
local spinHalf = spot("Right", "SpinMove", "Right", T, T + 0.3)
assert(spinHalf.Z > 0 and spinHalf.X < 0, "halfway through a spin the ball has swung round behind, to the far side")

-- Steal contact: the defender's hands must actually touch the ball where it is right now.
local function defenderAt(x, z)
	return CFrame.lookAt(Vector3.new(x, Y, z), Vector3.new(0, Y, 0))
end
assert(Hoops.reaches(defenderAt(0, -3), right) and Hoops.reaches(defenderAt(0, -3), left), "head-on, both sides are exposed")
assert(not Hoops.reaches(defenderAt(0, -3), low), "a ball low in its bounce slips under the reach")
assert(Hoops.reaches(defenderAt(2, -2.5), right), "defender on the ball side can reach it")
assert(not Hoops.reaches(defenderAt(2, -2.5), left), "a crossover away from the defender protects the ball")
assert(not Hoops.reaches(defenderAt(0, 3), right), "no reaching around from behind")
-- (a shot windup can't be stolen at all: the server ignores reaches while a shot is gathering)

-- Block contact: raised hands must touch the ball where it is right now.
local gathered = spot("Right", "JumpShot", "Right", T, T + 2) -- a jump shot held at its set point
assert(Hoops.blocks(defenderAt(0, -2.5), gathered), "in your face, a block reaches the windup")
assert(not Hoops.blocks(defenderAt(0, -5), gathered), "from too far, a block can't reach the windup")
assert(not Hoops.blocks(defenderAt(0, -2.5), right), "a dribble is too low to block")
local released = gathered + Vector3.new(0, 3, 0) -- the shot just left the hands
local jumped = CFrame.lookAt(Vector3.new(0, Y + 3, -2.5), Vector3.new(0, Y + 3, 0))
assert(not Hoops.blocks(defenderAt(0, -2.5), released), "standing, the released shot is over your hands")
assert(Hoops.blocks(jumped, released), "a timed jump gets to the released shot")

print("hoops.spec: all passed")
