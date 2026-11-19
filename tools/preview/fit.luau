-- Calibrates the game to the animations: measures where the animated hands really are (on the real rig)
-- and rewrites the ball spots in src/shared/Hoops.luau to match: the dribble spot, every move's ball path,
-- the shot windup, the blocker's hands and the steal reach. Timing and hands come from Hoops.MOVES.
-- Run from the repo root after changing animations: lune run tools/preview/fit
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Rig = require("./rig")
local Hoops = require("../../src/shared/Hoops")
assert(Rig.exact, "fit needs the real rig in tools/preview/r15-rig.json (see the README)")

local R = Hoops.BALL_RADIUS
local HOOPS = "src/shared/Hoops.luau"

local function dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

-- A world point in the standing root's body space: right, up, forward.
local function body(root, p)
	local d = p - root.Position
	return dot(d, root.RightVector), dot(d, root.UpVector), dot(d, root.LookVector)
end

-- Where the ball is when `hand` ("R", "L", "both") has it: under the palm (the arms' IK puts the hand on top
-- of the ball) or between both hands.
local function ballIn(name, t, hand)
	local parts, root = Rig.at(name, t)
	local p = if hand == "both"
		then (parts.RightHand.Position + parts.LeftHand.Position) / 2
		else parts[(if hand == "R" then "Right" else "Left") .. "Hand"].Position - Vector3.new(0, R, 0)
	return body(root, p)
end

local function between(name, t, a, b) -- midpoint of two parts, body space
	local parts, root = Rig.at(name, t)
	return body(root, (parts[a].Position + parts[b].Position) / 2)
end

local fitted = {}

-- The dribble: the right hand at the start of a move is the ready stance.
fitted.DRIBBLE_SIDE, fitted.DRIBBLE_TOP, fitted.DRIBBLE_FORWARD = ballIn("Crossover", 0, "R")

-- An arm's reach (shoulder to hand centre) and the right shoulder's position, body space, at time t.
local joint = {}
for _, j in Rig.rig.joints do
	joint[j.name] = j
end
local function v(t)
	return Vector3.new(t[1], t[2], t[3])
end
local REACH = (v(joint.RightUpperArm.c1) - v(joint.RightLowerArm.c0)).Magnitude
	+ (v(joint.RightLowerArm.c1) - v(joint.RightHand.c0)).Magnitude
	+ v(joint.RightHand.c1).Magnitude
local function shoulder(name, t)
	local parts, root = Rig.at(name, t)
	return Vector3.new(body(root, (parts.UpperTorso * roblox.CFrame.new(v(joint.RightUpperArm.c0))).Position))
end

-- How low the dribble hand can follow the ball: 95% of the arm's reach from the shoulder, but no more
-- than 0.4 below the top of the bounce.
do
	local s = shoulder("Crossover", 0)
	local across = math.sqrt((fitted.DRIBBLE_SIDE - s.X) ^ 2 + (fitted.DRIBBLE_FORWARD - s.Z) ^ 2)
	local lowest = s.Y - math.sqrt(math.max((0.95 * REACH) ^ 2 - across ^ 2, 0))
	fitted.HAND_LOW = math.max(fitted.DRIBBLE_TOP + R - 0.4, lowest)
end

-- Shot windup: between the hands at the jump shot's set point (where it holds while the meter fills), but
-- out in front of the face (heads are solid: a shot launched inside one bounces off the shooter), and
-- lowered if needed so both hands can still reach the ball's sides.
do
	local parts, root = Rig.at("JumpShot", 0.35)
	local _, up, forward = body(root, (parts.RightHand.Position + parts.LeftHand.Position) / 2)
	local _, _, headForward = body(root, parts.Head.Position)
	forward = math.max(forward, headForward + Rig.rig.sizes.Head[3] / 2 + R + 0.05)
	local s = shoulder("JumpShot", 0.35)
	while (Vector3.new(R + 0.2, up, forward) - s).Magnitude > 0.95 * REACH do
		up -= 0.02
	end
	fitted.GATHER_HEIGHT, fitted.GATHER_FORWARD = up, forward
end
local _
-- Block: between the raised hands at the top of the block.
_, fitted.BLOCK_HEIGHT, fitted.BLOCK_FORWARD = between("Block", 0.25, "RightHand", "LeftHand")
-- Steal: the reaching hand at full stretch.
do
	local parts, root = Rig.at("StealSwipe", 0.12)
	_, fitted.STEAL_UP, fitted.STEAL_FORWARD = body(root, parts.RightHand.Position)
end

-- Move paths: hand keyframes from the hands, bounces between the feet ("legs") or along the way between
-- the hand positions either side. First and last keyframes are the dribble spot itself.
local function fmt(x)
	return string.format("%.3f", x):gsub("%.?0+$", ""):gsub("^%-0$", "0")
end
local names = {}
for name in Hoops.MOVES do
	table.insert(names, name)
end
table.sort(names)
local lines = { "Hoops.MOVES = {" }
for _, name in names do
	local move = Hoops.MOVES[name]
	local path, out = move.path, {}
	for i, k in path do
		if i == 1 or i == #path then
			out[i] = { k[1], if k[5] == "L" then "-S" else "S", "T", "F", k[5] }
		elseif k[3] ~= "floor" then
			local right, up, forward = ballIn(name, k[1], k[5])
			out[i] = { k[1], right, up, forward, k[5] }
		end
	end
	local function value(x, symbol) -- resolve S/T/F symbols to numbers for interpolation
		return if type(x) == "number" then x elseif x == "S" then fitted.DRIBBLE_SIDE elseif x == "-S" then -fitted.DRIBBLE_SIDE elseif x == "T" then fitted.DRIBBLE_TOP else fitted.DRIBBLE_FORWARD
	end
	for i, k in path do
		if not out[i] then -- a bounce
			local right, forward
			if k[5] == "legs" then
				right, _, forward = between(name, k[1], "LeftFoot", "RightFoot")
			else
				local a, b = out[i - 1], out[i + 1]
				local u = (k[1] - a[1]) / (b[1] - a[1])
				right = value(a[2]) + (value(b[2]) - value(a[2])) * u
				forward = value(a[4]) + (value(b[4]) - value(a[4])) * u
			end
			out[i] = { k[1], right, "floor", forward, k[5] }
		end
	end
	table.insert(lines, `\t{name} = \{ switch = {move.switch}, path = \{`)
	for _, k in out do
		local fields = {}
		for j = 1, 4 do
			local x = k[j]
			fields[j] = if type(x) == "number" then fmt(x) elseif x == "floor" then '"floor"' else x
		end
		local hand = if k[5] then `, "{k[5]}"` else ""
		table.insert(lines, `\t\t\{ {table.concat(fields, ", ")}{hand} },`)
	end
	table.insert(lines, "\t} },")
end
table.insert(lines, "}")

-- Rewrite Hoops.luau: the measured constants, and the moves block.
local src = fs.readFile(HOOPS)
for key, x in fitted do
	local count
	src, count = src:gsub(`(\n\t{key} = )%-?[%d%.]+,`, "%1" .. fmt(x) .. ",")
	assert(count == 1, `{key} not found exactly once in Hoops.luau`)
end
local head, tail = src:match("^(.-%-%- BEGIN FITTED MOVES\n).-(%-%- END FITTED MOVES.*)$")
assert(head and tail, "fitted moves markers missing in Hoops.luau")
fs.writeFile(HOOPS, head .. table.concat(lines, "\n") .. "\n" .. tail)

local keys = {}
for key in fitted do
	table.insert(keys, key)
end
table.sort(keys)
for _, key in keys do
	print(string.format("%-16s %s", key, fmt(fitted[key])))
end
print(`fitted {#names} move paths into {HOOPS}`)
