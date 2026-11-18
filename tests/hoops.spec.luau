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

-- Steal reach: the handler stands at the origin facing -Z, with the ball on the right or left.
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local handler = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(0, 0, -1))
local function defenderAt(x, z)
	return CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, 0))
end
local right, left = Hoops.dribbleSpot(handler, "Right"), Hoops.dribbleSpot(handler, "Left")
assert(right.X > 0 and left.X < 0, "hand picks the side")
assert(Hoops.reaches(defenderAt(0, -3), right) and Hoops.reaches(defenderAt(0, -3), left), "head-on, both sides are exposed")
assert(Hoops.reaches(defenderAt(2, -2.5), right), "defender on the ball side can reach it")
assert(not Hoops.reaches(defenderAt(2, -2.5), left), "a crossover away from the defender protects the ball")
assert(not Hoops.reaches(defenderAt(0, 3), right), "no reaching around from behind")
assert(not Hoops.reaches(defenderAt(0, -3), Hoops.gatherSpot(handler)), "a shot windup is out of reach")

print("hoops.spec: all passed")
