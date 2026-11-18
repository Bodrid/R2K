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
local Y = Hoops.FLOOR_Y + 3
local handler = CFrame.lookAt(Vector3.new(0, Y, 0), Vector3.new(0, Y, -1))
local T = 1000 -- any server time
local function spot(hand, fromHand, crossAt, gatherAt, now)
	return (Hoops.ballSpot(handler, hand, fromHand, crossAt, gatherAt, now))
end
local function near(a, b)
	return (a - b).Magnitude < 1e-3
end
local floorY = Hoops.FLOOR_Y + Hoops.BALL_RADIUS
local right = spot("Right", "Right", T - Hoops.CROSS_TIME, nil, T) -- top of the bounce, right side
local left = spot("Left", "Left", T - Hoops.CROSS_TIME, nil, T)
local low = spot("Right", "Right", T - Hoops.CROSS_TIME, nil, T + 0.5 / Hoops.DRIBBLE_HZ) -- half a bounce later
local midCross = spot("Left", "Right", T, nil, T + Hoops.CROSS_TIME / 2)
assert(right.X > 0 and left.X < 0, "hand picks the side")
assert(math.abs(right.Y - (Y + Hoops.DRIBBLE_TOP)) < 1e-3, "a new dribble starts at the top")
assert(math.abs(low.Y - floorY) < 1e-3, "half a bounce later the ball is on the floor")
assert(math.abs(midCross.X) < 1e-3 and math.abs(midCross.Y - floorY) < 1e-3, "mid-crossover it bounces between the feet")
assert(near(spot("Left", "Right", T, nil, T + Hoops.CROSS_TIME), left), "a finished crossover lands at the top, other side")
assert(near(spot("Right", "Right", T - 5, T, T + Hoops.GATHER_TIME), Hoops.gatherSpot(handler)), "a gathered ball sits at the gather spot")

-- Steal contact: the defender's hands must actually touch the ball where it is right now.
local function defenderAt(x, z)
	return CFrame.lookAt(Vector3.new(x, Y, z), Vector3.new(0, Y, 0))
end
assert(Hoops.reaches(defenderAt(0, -3), right) and Hoops.reaches(defenderAt(0, -3), left), "head-on, both sides are exposed")
assert(not Hoops.reaches(defenderAt(0, -3), low), "a ball low in its bounce slips under the reach")
assert(Hoops.reaches(defenderAt(2, -2.5), right), "defender on the ball side can reach it")
assert(not Hoops.reaches(defenderAt(2, -2.5), left), "a crossover away from the defender protects the ball")
assert(not Hoops.reaches(defenderAt(0, 3), right), "no reaching around from behind")
assert(not Hoops.reaches(defenderAt(0, -3), Hoops.gatherSpot(handler)), "a shot windup is out of reach")

-- Block contact: raised hands must touch the ball where it is right now.
local gathered = Hoops.gatherSpot(handler)
assert(Hoops.blocks(defenderAt(0, -2.5), gathered), "in your face, a block reaches the windup")
assert(not Hoops.blocks(defenderAt(0, -5), gathered), "from too far, a block can't reach the windup")
assert(not Hoops.blocks(defenderAt(0, -2.5), right), "a dribble is too low to block")
local released = gathered + Vector3.new(0, 3, 0) -- the shot just left the hands
local jumped = CFrame.lookAt(Vector3.new(0, Y + 3, -2.5), Vector3.new(0, Y + 3, 0))
assert(not Hoops.blocks(defenderAt(0, -2.5), released), "standing, the released shot is over your hands")
assert(Hoops.blocks(jumped, released), "a timed jump gets to the released shot")

print("hoops.spec: all passed")
