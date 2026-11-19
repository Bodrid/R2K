-- Run: lune run tests/hoops.spec   (pure math only; gameplay is checked in Studio)
local Hoops = require("../src/shared/Hoops")
getfenv().Vector3 = require("@lune/roblox").Vector3 -- Hoops' finish helpers use the global Vector3, as in Roblox

assert(Hoops.shotQuality(Hoops.PERFECT_HOLD) == 1, "perfect hold is quality 1")
assert(Hoops.shotQuality(0) == 0 and Hoops.shotQuality(5) == 0, "way off is quality 0")
assert(Hoops.shotQuality(0 / 0) ~= 1, "NaN hold time is never a perfect release")

assert(Hoops.makeChance(1, 40, true) == 1, "green always goes in")
assert(Hoops.makeChance(0, 2, false) == 0, "awful timing never goes in")
local open = Hoops.makeChance(0.8, 10, false)
assert(Hoops.makeChance(0.8, 10, true) < open, "a contest lowers the odds")
assert(Hoops.makeChance(0.8, 25, false) < open, "longer shots are harder")

-- Stamina: tired shooting is worse and the green window shrinks; sprints slow down only once you're tired.
assert(Hoops.makeChance(0.8, 10, false, 0.2) < open, "tired shots go in less")
assert(Hoops.greenAt(0) > Hoops.greenAt(1) and Hoops.greenAt(1) == Hoops.GREEN, "tired, the green window shrinks")
assert(Hoops.makeChance(Hoops.GREEN, 20, true, 1) == 1 and Hoops.makeChance(Hoops.GREEN, 20, true, 0) < 1, "a fresh green is a make; the same release tired isn't")
assert(Hoops.sprintSpeed(1) == Hoops.SPRINT_SPEED and Hoops.sprintSpeed(Hoops.TIRED) == Hoops.SPRINT_SPEED, "full sprint until tired")
assert(Hoops.sprintSpeed(0) == Hoops.WALK_SPEED and Hoops.sprintSpeed(Hoops.TIRED / 2) < Hoops.SPRINT_SPEED, "empty: a jog")

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
local rig = require("@lune/serde").decode("json", fs.readFile("tools/preview/r15-rig.json"))
local HIP -- how far out each hip is, from the calibrated rig
for _, j in rig.joints do
	if j.name == "RightUpperLeg" then
		HIP = j.c0[1]
	end
end
local function keyTime(name, i) -- time of a move's i-th path keyframe (timings are authored in Hoops.MOVES)
	return Hoops.MOVES[name].path[i][1]
end
local crossBounce = spot("Left", "Crossover", "Right", T, T + keyTime("Crossover", 3))
assert(math.abs(crossBounce.X) < HIP and crossBounce.Z < 0 and math.abs(crossBounce.Y - floorY) < 1e-3, "a crossover bounces in front, between the feet")
assert(spot("Left", "BehindBack", "Right", T, T + keyTime("BehindBack", 3)).Z > 0, "a behind-the-back goes behind the body")
-- Top of the head above the root, standing, from the calibrated rig (root -> lower torso -> upper torso -> head).
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

-- Pro stick: directions are relative to the ball hand, so the left hand mirrors the right.
local stick = Hoops.proStick
assert(stick(0, 1, 0, 0.1, 1, false) == "Hesitation", "up: hesitation")
assert(stick(-1, 0, 0, 0.1, 1, false) == "Crossover" and stick(1, 0, 0, 0.1, -1, false) == "Crossover", "toward the other hand: crossover, either hand")
assert(stick(1, 0, 0, 0.1, 1, false) == "InAndOut" and stick(1, 0, 0, 0.4, 1, false) == "SideStep", "toward the ball hand: flick in-and-out, hold side-step")
assert(stick(0, -1, 0, 0.1, 1, false) == "Stepback" and stick(0, -1, 0, 0.1, 1, true) == "StepbackEscape", "down: stepback, L2 escape")
assert(stick(-0.7, -0.7, 0, 0.1, 1, false) == "BetweenLegs" and stick(0.7, -0.7, 0, 0.1, 1, false) == "BehindBack", "down diagonals: tween to the off hand, behind the back to the ball hand")
assert(stick(1, 0, 190, 0.3, 1, false) == "SpinMove" and stick(1, 0, -190, 0.3, -1, true) == "SpinEscape", "half circle: spin")
for _, x in { -1, -0.7, 0, 0.7, 1 } do
	for _, y in { -1, -0.7, 0, 0.7, 1 } do
		if x ~= 0 or y ~= 0 then
			assert(Hoops.MOVES[stick(x, y, 0, 0.1, 1, false)], "every direction is a real move")
		end
	end
end

-- Chaining: any move can follow any other, and the ball never jumps at the handover.
for a, moveA in Hoops.MOVES do
	if not moveA.finish then
		local handAfter = if moveA.switch then "Left" else "Right"
		local finishedA = spot(handAfter, a, "Right", T, T + moveA.duration)
		for b in Hoops.MOVES do
			local startB = spot(handAfter, b, handAfter, T + moveA.duration, T + moveA.duration)
			assert(near(finishedA, startB), `{a} -> {b}: the ball jumps when chaining`)
		end
	end
end

-- Every dribble move moves the player a little, within the move, and in the right direction.
for name, move in Hoops.MOVES do
	local d = Hoops.DASHES[name]
	if not move.finish then
		assert(d, `{name} has no dash: it would leave the player standing still`)
		assert(d[3] * d[4] >= 2.5, `{name} barely moves the player`)
		assert(d[1] + d[4] <= move.duration + 1e-6, `{name}'s dash outlasts the move`)
	end
end
do
	local cf = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -10)) -- facing the basket (-Z); right is +X
	local function dir(kind, hand)
		return Hoops.dashDirection(cf, kind, hand)
	end
	assert(dir("side", "Right").X > 0.99 and dir("side", "Left").X < -0.99, "side goes toward the ball hand")
	assert(dir("cross", "Right").X < -0.99 and dir("cross", "Left").X > 0.99, "cross goes toward the other hand")
	assert(dir("forward", "Right").Z < -0.99 and dir("back", "Left").Z > 0.99, "forward is toward the basket, back away")
end

-- The finishing package: every finish has its rules, glides within its own animation, and is timed to it.
for name, move in Hoops.MOVES do
	local f = Hoops.FINISHES[name]
	if move.finish and name ~= "JumpShot" then
		assert(f and f.range and f.glide, `{name} isn't in Hoops.FINISHES`)
		for i, w in f.glide do
			assert(w[1] > (if i > 1 then f.glide[i - 1][1] else 0), `{name}: glide times go forward`)
		end
		assert(f.glide[#f.glide][1] <= move.duration + 1e-6, `{name}: glides past its release`)
		assert(Hoops.perfectHold(name) == move.duration, `{name}: perfect at the top of its path`)
	end
end
for name in Hoops.FINISHES do
	assert(Hoops.MOVES[name] and Hoops.MOVES[name].finish, `{name} has no finish path`)
end
assert(Hoops.perfectHold("JumpShot") == Hoops.PERFECT_HOLD, "a jump shot is perfect after PERFECT_HOLD")
assert(Hoops.shotQuality(Hoops.perfectHold("EuroStep"), Hoops.perfectHold("EuroStep")) == 1, "a finish's own timing is perfect")
assert(Hoops.flightTime(2, "Dunk") < 0.3, "a dunk goes straight down through")
assert(Hoops.flightTime(7, "Floater") > Hoops.flightTime(7, "Layup") + 0.2, "a floater hangs")

do -- picking the finish
	local function at(x, z)
		return Vector3.new(x, 4, z)
	end
	local half = function()
		return 0.5
	end
	local pick = Hoops.pickFinish
	local R = Hoops.RIM_Z
	local function isDunk(name)
		return Hoops.FINISHES[name] ~= nil and Hoops.FINISHES[name].dunk == true
	end
	assert(pick(at(0, R + 15), nil, false, nil, half) == "JumpShot", "out of range: a jump shot")
	assert(isDunk(pick(at(0, R + 3), nil, false, nil, half)), "open at the rim: a dunk")
	assert(pick(at(0, R + 8), nil, false, nil, half) == "Layup", "open, a few steps out: a layup")
	assert(isDunk(pick(at(0, R + 8), nil, true, nil, half)), "on turbo, a dunk from further out")
	assert(pick(at(0, R + 9), at(0, R + 6), false, nil, half) == "Floater", "a big in the way, out there: float it")
	assert(pick(at(0, R + 6), at(0, R + 3.5), false, nil, half) == "EuroStep", "a defender in the way up close: euro around him")
	assert(pick(at(6, R - 1), nil, false, nil, half) == "ReverseLayup", "along the baseline: reverse it")
	assert(pick(at(0, R + 8), at(3, R + 8), false, nil, half) == "HopStep", "body on body beside you: power it up")
	assert(pick(at(0, R + 10), nil, true, "Hesitation", half) == "Layup" and isDunk(pick(at(0, R + 4), nil, false, "Hesitation", half)), "stick up: dunk if you can, else a layup")
	assert(pick(at(0, R + 6), nil, true, "Crossover", half) == "EuroStep" and pick(at(0, R + 6), nil, true, "Stepback", half) == "HopStep", "stick sideways: euro; down: hop step")
	assert(pick(at(0, R + 6), nil, true, "SpinMove", half) == "ReverseLayup" and pick(at(0, R + 6), nil, true, "DoubleTween", half) == "Floater", "spin: reverse; tween: floater")
	assert(pick(at(0, R + 15), nil, true, "Crossover", half) == "JumpShot", "the stick can't finish from out of range")
end

do -- where finishes carry you
	local from = Vector3.new(0, 4, Hoops.RIM_Z + 10)
	local glide = Hoops.finishGlide("Layup", "Right", from)
	local last = glide[#glide][2]
	assert(math.abs(last.Z - (Hoops.RIM_Z + 2.2)) < 1e-6 and math.abs(last.X) < 1e-6 and last.Y == 4, "a layup carries you in along your line")
	local close = Hoops.finishGlide("Layup", "Right", Vector3.new(0, 4, Hoops.RIM_Z + 1.5))
	assert(close[1][2].Z <= Hoops.RIM_Z + 1.5 + 1e-6, "never backs away from the rim")
	local euroR, euroL = Hoops.finishGlide("EuroStep", "Right", from), Hoops.finishGlide("EuroStep", "Left", from)
	assert(euroR[1][2].X > 1 and euroL[1][2].X < -1 and euroR[2][2].X < 0, "a euro steps out to the ball side, then across (mirrored left)")
	local reverse = Hoops.finishGlide("ReverseLayup", "Right", from)
	assert(reverse[#reverse][2].Z < Hoops.RIM_Z, "a reverse goes under the rim and finishes past it")
end

-- Animation ids: Studio plays the copies saved in the place (no upload needed); published games the uploaded ids.
do
	local studio, registered = true, 0
	local saved = { { Name = "Crossover" }, { Name = "DribbleStance" } }
	local services = {
		RunService = { IsStudio = function() return studio end },
		ReplicatedStorage = { WaitForChild = function() return { GetChildren = function() return saved end } end },
		KeyframeSequenceProvider = { RegisterKeyframeSequence = function(_, sequence)
			registered += 1
			return "temp://" .. sequence.Name
		end },
	}
	game = { GetService = function(_, name) return services[name] end }
	assert(Hoops.animationId("Crossover") == "temp://Crossover", "Studio plays the saved version")
	assert(Hoops.animationId("DribbleStance") == "temp://DribbleStance", "Studio plays animations that aren't uploaded yet")
	assert(Hoops.animationId("Block") == `rbxassetid://{Hoops.ANIMATIONS.Block}`, "Studio falls back to the uploaded id")
	assert(registered == 2, "registered once, on first use")
	studio = false
	assert(Hoops.animationId("Crossover") == `rbxassetid://{Hoops.ANIMATIONS.Crossover}`, "published games use uploaded ids")
	assert(Hoops.animationId("DribbleStance") == nil, "outside Studio, no upload means no animation")
	game = nil
end

print("hoops.spec: all passed")
