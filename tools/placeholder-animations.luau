-- Builds rough placeholder animations for R15 rigs as KeyframeSequences (assets/animations/*.rbxmx).
-- They're blockouts to open in Studio's Animation Editor, polish and publish, not final animations.
-- Run from the repo root: lune run tools/placeholder-animations
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Instance, CFrame, Enum = roblox.Instance, roblox.CFrame, roblox.Enum

-- R15 joints: each part's pose sits under the pose of the part it hangs from.
local PARENT = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
}

-- Joint rotation in degrees. +X swings an arm or leg forward (and bends an elbow); -X bends a knee;
-- +X on the torso leans back; +Y turns left.
local function rot(x, y, z)
	return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0))
end

-- Lower the hips by `drop` and bend both legs so the feet stay on the floor (R15 leg segments ~1.2 studs).
local function crouch(drop, poses)
	local hip = math.deg(math.acos(1 - drop / 2.4))
	poses.LowerTorso = (poses.LowerTorso or CFrame.new()) * CFrame.new(0, -drop, 0)
	for _, side in { "Right", "Left" } do
		poses[side .. "UpperLeg"], poses[side .. "LowerLeg"], poses[side .. "Foot"] = rot(hip), rot(-2 * hip), rot(hip)
	end
	return poses
end

-- keyframes: { { time, { [partName] = CFrame } } }. A part keyed anywhere gets a pose in every keyframe
-- (missing = rest pose), so the editor shows full tracks; unkeyed parents only hold their children.
local function build(name, keyframes)
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = false
	seq.Priority = Enum.AnimationPriority.Action
	local keyed = {}
	for _, kf in keyframes do
		for part in kf[2] do
			keyed[part] = true
		end
	end
	for _, kf in keyframes do
		local frame = Instance.new("Keyframe")
		frame.Time = kf[1]
		local poses = {}
		local function poseFor(part)
			if not poses[part] then
				local pose = Instance.new("Pose")
				pose.Name = part
				pose.CFrame = kf[2][part] or CFrame.new()
				pose.Weight = if keyed[part] then 1 else 0 -- 0: not animated, only holds child poses
				pose.EasingStyle = Enum.PoseEasingStyle.Cubic
				pose.Parent = if part == "HumanoidRootPart" then frame else poseFor(PARENT[part])
				poses[part] = pose
			end
			return poses[part]
		end
		for part in keyed do
			poseFor(part)
		end
		frame.Parent = seq
	end

	local path = `assets/animations/{name}.rbxmx`
	fs.writeFile(path, roblox.serializeModel({ seq }, true))
	-- self-check: the file reads back with every keyframe and every keyed pose
	local back = roblox.deserializeModel(fs.readFile(path))[1]
	assert(#back:GetChildren() == #keyframes, `{name}: keyframes lost`)
	for _, frame in back:GetChildren() do
		local count = 0
		for _, pose in frame:GetDescendants() do
			count += if pose.Weight == 1 then 1 else 0
		end
		local expected = 0
		for _ in keyed do
			expected += 1
		end
		assert(count == expected, `{name}: poses lost at {frame.Time}s`)
	end
	print(`wrote {path}`)
end

fs.writeDir("assets/animations")

build("JumpShot", {
	{ 0, {} },
	{ 0.2, crouch(0.5, { -- dip, ball set by the forehead
		RightUpperArm = rot(110),
		RightLowerArm = rot(100),
		LeftUpperArm = rot(100),
		LeftLowerArm = rot(80),
	}) },
	{ 0.45, { -- rise and release: shooting arm up, wrist flicks, guide hand off
		RightUpperArm = rot(170),
		RightLowerArm = rot(10),
		RightHand = rot(60),
		LeftUpperArm = rot(140),
		LeftLowerArm = rot(40),
	} },
	{ 0.9, {} },
})

build("Block", {
	{ 0, {} },
	{ 0.1, crouch(0.4, { RightUpperArm = rot(60), LeftUpperArm = rot(60) }) }, -- load up
	{ 0.25, { -- arms straight up, slight lean back
		UpperTorso = rot(10),
		RightUpperArm = rot(172),
		LeftUpperArm = rot(172),
	} },
	{ 0.5, {} },
})

build("StealSwipe", { -- arms and torso only, so the legs keep their walk/run
	{ 0, {} },
	{ 0.12, { -- lean in and reach with the right hand
		UpperTorso = rot(-20, 15),
		RightUpperArm = rot(85),
		RightLowerArm = rot(15),
		LeftUpperArm = rot(-25),
	} },
	{ 0.35, {} },
})

-- Spin: the body turns a full circle in four 90° steps (so each step blends the short way round).
-- The game would also turn the character itself during the move.
local function spinStep(degrees)
	return crouch(0.3, {
		LowerTorso = rot(0, -degrees),
		RightUpperArm = rot(40),
		RightLowerArm = rot(90), -- ball tucked in
		LeftUpperArm = rot(20, 0, -45), -- off arm out for balance
	})
end
build("SpinMove", {
	{ 0, {} },
	{ 0.15, spinStep(90) },
	{ 0.3, spinStep(180) },
	{ 0.45, spinStep(270) },
	{ 0.6, {} },
})
