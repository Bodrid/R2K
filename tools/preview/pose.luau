-- Poses an R15 rig through each animation and writes every frame (part positions + the game's ball
-- position) to JSON, for render.py to draw. Lets us look at animations without Studio.
-- Run from the repo root: lune run tools/preview/pose [AnimationName ...]   (no names = all)
-- The rig comes from tools/preview/r15-rig.json if present (dumped from Studio, exact), else a best guess.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Hoops = require("../../src/shared/Hoops")

local FRAMES = 6

-- Best-guess R15 block rig: part sizes and, per joint, the attachment offsets in Part0 (c0) and Part1 (c1).
-- shortcut: guessed numbers; dump the real rig from Studio into r15-rig.json for exact previews
local rig = {
	hipHeight = 2,
	sizes = {
		HumanoidRootPart = { 2, 2, 1 }, LowerTorso = { 2, 0.4, 1 }, UpperTorso = { 2, 1.6, 1 }, Head = { 1.2, 1.2, 1.2 },
		RightUpperArm = { 1, 1.169, 1 }, RightLowerArm = { 1, 1.052, 1 }, RightHand = { 1, 0.3, 1 },
		LeftUpperArm = { 1, 1.169, 1 }, LeftLowerArm = { 1, 1.052, 1 }, LeftHand = { 1, 0.3, 1 },
		RightUpperLeg = { 1, 1.217, 1 }, RightLowerLeg = { 1, 1.193, 1 }, RightFoot = { 1, 0.3, 1 },
		LeftUpperLeg = { 1, 1.217, 1 }, LeftLowerLeg = { 1, 1.193, 1 }, LeftFoot = { 1, 0.3, 1 },
	},
	joints = {
		{ name = "LowerTorso", parent = "HumanoidRootPart", c0 = { 0, -1, 0 }, c1 = { 0, -0.2, 0 } },
		{ name = "UpperTorso", parent = "LowerTorso", c0 = { 0, 0.2, 0 }, c1 = { 0, -0.8, 0 } },
		{ name = "Head", parent = "UpperTorso", c0 = { 0, 0.8, 0 }, c1 = { 0, -0.6, 0 } },
		{ name = "RightUpperArm", parent = "UpperTorso", c0 = { 1, 0.563, 0 }, c1 = { -0.5, 0.394, 0 } },
		{ name = "RightLowerArm", parent = "RightUpperArm", c0 = { 0, -0.334, 0 }, c1 = { 0, 0.2, 0 } },
		{ name = "RightHand", parent = "RightLowerArm", c0 = { 0, -0.501, 0 }, c1 = { 0, 0.125, 0 } },
		{ name = "LeftUpperArm", parent = "UpperTorso", c0 = { -1, 0.563, 0 }, c1 = { 0.5, 0.394, 0 } },
		{ name = "LeftLowerArm", parent = "LeftUpperArm", c0 = { 0, -0.334, 0 }, c1 = { 0, 0.2, 0 } },
		{ name = "LeftHand", parent = "LeftLowerArm", c0 = { 0, -0.501, 0 }, c1 = { 0, 0.125, 0 } },
		{ name = "RightUpperLeg", parent = "LowerTorso", c0 = { 0.5, -0.2, 0 }, c1 = { 0, 0.42, 0 } },
		{ name = "RightLowerLeg", parent = "RightUpperLeg", c0 = { 0, -0.411, 0 }, c1 = { 0, 0.3, 0 } },
		{ name = "RightFoot", parent = "RightLowerLeg", c0 = { 0, -0.547, 0 }, c1 = { 0, 0.15, 0 } },
		{ name = "LeftUpperLeg", parent = "LowerTorso", c0 = { -0.5, -0.2, 0 }, c1 = { 0, 0.42, 0 } },
		{ name = "LeftLowerLeg", parent = "LeftUpperLeg", c0 = { 0, -0.411, 0 }, c1 = { 0, 0.3, 0 } },
		{ name = "LeftFoot", parent = "LeftLowerLeg", c0 = { 0, -0.547, 0 }, c1 = { 0, 0.15, 0 } },
	},
}
local exact = fs.isFile("tools/preview/r15-rig.json")
if exact then
	rig = serde.decode("json", fs.readFile("tools/preview/r15-rig.json"))
end

local function toCFrame(t) -- {x,y,z} offset or the 12 numbers of CFrame:GetComponents()
	return if #t == 3 then CFrame.new(t[1], t[2], t[3]) else CFrame.new(table.unpack(t))
end

-- Pose CFrames of one animation at time t (interpolated between keyframes; unkeyed = rest).
local function posesAt(keyframes, t)
	local a, b = keyframes[1], keyframes[#keyframes]
	for i = 2, #keyframes do
		if t <= keyframes[i].Time then
			a, b = keyframes[i - 1], keyframes[i]
			break
		end
	end
	local u = if b.Time > a.Time then math.clamp((t - a.Time) / (b.Time - a.Time), 0, 1) else 1
	u = u * u * (3 - 2 * u) -- the generator keys use cubic easing; ease in-out is close enough to look at
	local function read(keyframe)
		local out = {}
		for _, pose in keyframe:GetDescendants() do
			if pose.Weight > 0 then
				out[pose.Name] = pose.CFrame
			end
		end
		return out
	end
	local pa, pb, out = read(a), read(b), {}
	for name, cf in pa do
		out[name] = cf:Lerp(pb[name] or CFrame.new(), u)
	end
	for name, cf in pb do
		out[name] = out[name] or CFrame.new():Lerp(cf, u)
	end
	return out
end

-- Forward kinematics, the way Roblox does it: Part1 = Part0 * C0 * Transform * C1:Inverse()
local function solve(poses)
	local root = CFrame.new(0, Hoops.FLOOR_Y + rig.hipHeight + rig.sizes.HumanoidRootPart[2] / 2, 0) -- facing -Z
	local parts = { HumanoidRootPart = root }
	local pending = table.clone(rig.joints)
	while #pending > 0 do
		for i = #pending, 1, -1 do
			local j = pending[i]
			if parts[j.parent] then
				parts[j.name] = parts[j.parent] * toCFrame(j.c0) * (poses[j.name] or CFrame.new()) * toCFrame(j.c1):Inverse()
				table.remove(pending, i)
			end
		end
	end
	return parts, root
end

local function ballFor(name, root, t)
	local base = name:gsub("_L$", "")
	local left = base ~= name
	local move = Hoops.MOVES[base]
	if move then
		local startHand = if left then "Left" else "Right"
		local endHand = if move.switch then (if left then "Right" else "Left") else startHand
		return (Hoops.ballSpot(root, endHand, base, startHand, 0, nil, t))
	elseif base == "JumpShot" or base == "Layup" or base == "Dunk" or base == "DunkTwoHand" then
		return (Hoops.ballSpot(root, if left then "Left" else "Right", nil, nil, -10, 0, t)) -- the shot gather
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
	local seq = roblox.deserializeModel(fs.readFile(`assets/animations/{name}.rbxmx`))[1]
	local keyframes = seq:GetChildren()
	table.sort(keyframes, function(x, y)
		return x.Time < y.Time
	end)
	local length = keyframes[#keyframes].Time
	local frames, trail = {}, {}
	local worstGap, lowestFoot, highestFoot = 0, math.huge, -math.huge
	for i = 0, 40 do -- dense samples for the trail and the checks; FRAMES of them get drawn
		local t = length * i / 40
		local parts, root = solve(posesAt(keyframes, t))
		local ball = ballFor(name, root, t)
		local frame = { t = t, parts = {}, ball = ball and { ball.X, ball.Y, ball.Z } }
		for part, cf in parts do
			table.insert(frame.parts, { name = part, cf = { cf:GetComponents() }, size = rig.sizes[part] })
		end
		for _, foot in { "RightFoot", "LeftFoot" } do
			local bottom = parts[foot].Position.Y - rig.sizes[foot][2] / 2 - Hoops.FLOOR_Y
			lowestFoot, highestFoot = math.min(lowestFoot, bottom), math.max(highestFoot, bottom)
		end
		if ball then
			local gap = math.min((ball - parts.RightHand.Position).Magnitude, (ball - parts.LeftHand.Position).Magnitude)
			worstGap = math.max(worstGap, gap)
			table.insert(trail, frame.ball)
		end
		if i % (40 // (FRAMES - 1)) == 0 then
			table.insert(frames, frame)
		end
	end
	fs.writeFile(`tools/preview/out/{name}.json`, serde.encode("json", { name = name, length = length, exact = exact, frames = frames, trail = trail }))
	print(string.format("%-18s %.2fs  feet %+.2f..%+.2f above floor%s", name, length, lowestFoot, highestFoot, if #trail > 0 then string.format("  ball-to-hand up to %.2f studs", worstGap) else ""))
end
