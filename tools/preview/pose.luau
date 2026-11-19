-- Poses an R15 rig through each animation and writes every frame (part positions + the game's ball
-- position) to JSON, for render.py to draw. Lets us look at animations without Studio.
-- Run from the repo root: lune run tools/preview/pose [AnimationName ...]   (no names = all)
-- The rig comes from tools/preview/r15-rig.json if present (dumped from Studio, exact), else a best guess.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Hoops = require("../../src/shared/Hoops")

local FRAMES = 6

local Rig = require("./rig")
local Vector3 = require("@lune/roblox").Vector3
local rig, exact, posesAt, solve = Rig.rig, Rig.exact, Rig.posesAt, Rig.solve

local function ballFor(name, root, t)
	local base = name:gsub("_L$", "")
	local left = base ~= name
	local move = Hoops.MOVES[base]
	if move then
		local startHand = if left then "Left" else "Right"
		local endHand = if move.switch then (if left then "Right" else "Left") else startHand
		return Hoops.ballSpot(root, endHand, base, startHand, 0, nil, t)
	elseif base == "JumpShot" or base == "Layup" or base == "Dunk" or base == "DunkTwoHand" then
		return Hoops.ballSpot(root, if left then "Left" else "Right", nil, nil, -10, 0, t) -- the shot gather
	end
	return nil
end

local names = table.clone(process.args)
if #names == 0 then
	for _, file in fs.readDir("assets/animations") do
		table.insert(names, (file:gsub("%.rbxmx$", "")))
	end
	table.sort(names)
end

fs.writeDir("tools/preview/out")
for _, name in names do
	local keyframes, length = Rig.load(name)
	local frames, trail = {}, {}
	local worstGap, lowestFoot, highestFoot = 0, math.huge, -math.huge
	local R = Hoops.BALL_RADIUS
	for i = 0, 40 do -- dense samples for the trail and the checks; FRAMES of them get drawn
		local t = length * i / 40
		local parts, root = solve(posesAt(keyframes, t))
		local ball, side, hold = ballFor(name, root, t)
		local frame = { t = t, parts = {}, ball = ball and { ball.X, ball.Y, ball.Z } }
		for part, cf in parts do
			table.insert(frame.parts, { name = part, cf = { cf:GetComponents() }, size = rig.sizes[part] })
		end
		for _, foot in { "RightFoot", "LeftFoot" } do
			local bottom = parts[foot].Position.Y - rig.sizes[foot][2] / 2 - Hoops.FLOOR_Y
			lowestFoot, highestFoot = math.min(lowestFoot, bottom), math.max(highestFoot, bottom)
		end
		if ball then
			-- How far the game's arm IK must pull the animated hand(s) to the ball while a hand holds it:
			-- one hand on top of the ball, or both hands on its sides. Skipped while the ball is in the air.
			if hold >= 0.5 then
				for sign, hand in { [1] = "RightHand", [-1] = "LeftHand" } do
					worstGap = math.max(worstGap, (ball + root.RightVector * sign * (R + 0.2) - parts[hand].Position).Magnitude)
				end
			elseif math.abs(side) > 0.5 then
				local hand = if side > 0 then "RightHand" else "LeftHand"
				worstGap = math.max(worstGap, (ball + Vector3.new(0, R, 0) - parts[hand].Position).Magnitude)
			end
			table.insert(trail, frame.ball)
		end
		if i % (40 // (FRAMES - 1)) == 0 then
			table.insert(frames, frame)
		end
	end
	fs.writeFile(`tools/preview/out/{name}.json`, serde.encode("json", { name = name, length = length, exact = exact, frames = frames, trail = trail }))
	print(string.format("%-18s %.2fs  feet %+.2f..%+.2f above floor%s", name, length, lowestFoot, highestFoot, if #trail > 0 then string.format("  hand off the ball by up to %.2f studs", worstGap) else ""))
end
