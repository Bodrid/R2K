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

-- Legs, measured from the real rig (tools/preview/r15-rig.json, dumped from Studio): thigh and shin as
-- 2D vectors in the side view (forward, down), with their rest angles, so knees are solved exactly.
local serde = require("@lune/serde")
local RIG = serde.decode("json", fs.readFile("tools/preview/r15-rig.json"))
local JOINT = {}
for _, j in RIG.joints do
	JOINT[j.name] = j
end
local function segment(from, to) -- attachment offsets {x,y,z,...} -> length, rest angle (+ forward of straight down)
	local fwd, down = -(to[3] - from[3]), -(to[2] - from[2])
	return math.sqrt(fwd * fwd + down * down), math.atan2(fwd, down)
end
local THIGH, THIGH_REST = segment(JOINT.LeftUpperLeg.c1, JOINT.LeftLowerLeg.c0)
local SHIN, SHIN_REST = segment(JOINT.LeftLowerLeg.c1, JOINT.LeftFoot.c0)
local HIP_TO_ANKLE = THIGH * math.cos(THIGH_REST) + SHIN * math.cos(SHIN_REST) -- standing
local REST_FOOT = THIGH * math.sin(THIGH_REST) + SHIN * math.sin(SHIN_REST) -- ankle ahead of the hip, standing
-- Poses below were authored for a 2.4-stud leg; drops, foot spacing and hops scale with the real leg.
local LEG_SCALE = HIP_TO_ANKLE / 2.4

-- One leg with its foot flat on the floor, ankle `foot` studs ahead of the hip (- behind), hips `drop`
-- below standing (both already scaled). Two-bone IK with the knee bending forward.
local function plantedLeg(p, side, foot, drop, out)
	local f, h = foot, HIP_TO_ANKLE - drop
	local reach = math.clamp(math.sqrt(f * f + h * h), math.abs(THIGH - SHIN) + 1e-4, THIGH + SHIN) -- full reach = straight leg
	local thigh = math.atan2(f, h) + math.acos(math.clamp((THIGH * THIGH + reach * reach - SHIN * SHIN) / (2 * THIGH * reach), -1, 1))
	local shin = math.atan2(f - THIGH * math.sin(thigh), h - THIGH * math.cos(thigh))
	local hipTurn, kneeTurn = thigh - THIGH_REST, (shin - SHIN_REST) - (thigh - THIGH_REST)
	if math.sqrt(f * f + h * h) < THIGH + SHIN - 1e-3 then -- self-check: the ankle lands where it was placed
		local endF, endH = THIGH * math.sin(thigh) + SHIN * math.sin(shin), THIGH * math.cos(thigh) + SHIN * math.cos(shin)
		assert(math.abs(endF - f) < 1e-6 and math.abs(endH - h) < 1e-6, "leg IK missed the foot")
	end
	p[side .. "UpperLeg"] = CFrame.Angles(hipTurn, 0, math.rad(out or 0))
	p[side .. "LowerLeg"] = CFrame.Angles(kneeTurn, 0, 0)
	p[side .. "Foot"] = CFrame.Angles(-(hipTurn + kneeTurn), 0, 0) -- foot stays flat
end
do -- standing still must be the rest pose exactly
	local p = {}
	plantedLeg(p, "Left", REST_FOOT, 0)
	for _, part in { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" } do
		assert(select(1, p[part]:ToEulerAnglesXYZ()) ^ 2 < 1e-10, "rest pose isn't identity: " .. part)
	end
end

-- Lower the hips by `drop` (authored studs, scaled to the real leg) with both feet planted under the hips.
local function crouch(drop, poses)
	drop *= LEG_SCALE
	poses.LowerTorso = (poses.LowerTorso or CFrame.new()) * CFrame.new(0, -drop, 0)
	for _, side in { "Right", "Left" } do
		plantedLeg(poses, side, REST_FOOT, drop)
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
	{ 0.25, { -- arms up and slightly forward, toward the shooter
		UpperTorso = rot(-5),
		RightUpperArm = rot(160),
		LeftUpperArm = rot(160),
	} },
	{ 0.5, {} },
})

build("StealSwipe", { -- arms and torso only, so the legs keep their walk/run
	{ 0, {} },
	{ 0.12, { -- lean in and swipe down at the ball (it's dribbled at hip height)
		UpperTorso = rot(-35, 15),
		RightUpperArm = rot(50),
		RightLowerArm = rot(10),
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

----------------------------------------------------------------------------------------------------
-- 2K dribble moves: tweens, crossovers, hesitations, stepbacks and escapes.
-- Authored from the right hand (ball in the right, left foot forward); each also gets a mirrored
-- "_L" version for the left hand. They play in place: the game moves the character (e.g. back on a
-- stepback), and the ball follows the hand in code.
----------------------------------------------------------------------------------------------------

-- One leg tucked up in the air (hops): `foot` is where it would land (studs, as above) turned into a
-- thigh swing; knee bent by `tuck`, foot roughly level.
local function airLeg(p, side, foot, tuck, out)
	local thigh = foot * 30
	p[side .. "UpperLeg"] = rot(thigh, 0, out or 0)
	p[side .. "LowerLeg"] = rot(-tuck)
	p[side .. "Foot"] = rot(tuck - thigh)
end

local function armPose(p, side, a)
	if a then -- { shoulder X, shoulder Y, shoulder Z, elbow, wrist }
		p[side .. "UpperArm"] = rot(a[1], a[2], a[3])
		p[side .. "LowerArm"] = rot(a[4] or 0)
		p[side .. "Hand"] = rot(a[5] or 0)
	end
end

-- A full-body pose from a few readable numbers (degrees, studs):
--   drop: how far the hips sink (feet stay planted), or air = lift for a hop
--   left/right: where each foot sits, studs ahead of the hips (- behind)
--   leftOut/rightOut: legs out to the side in degrees (right +, left -)
--   tuck (or leftTuck/rightTuck): knee bend in the air
--   lean (- forward), twist (+ chest turns left), tilt (+ leans left), hipTurn: whole body yaw
--   R/L: arm poses. The head counters the torso so the eyes stay on the defender.
local function body(o)
	local p = {}
	local drop = (o.drop or 0) * LEG_SCALE
	p.LowerTorso = CFrame.new(0, if o.air then o.air * LEG_SCALE else -drop, 0) * rot(0, o.hipTurn or 0, 0)
	for _, side in { "Left", "Right" } do
		local foot, out = o[side:lower()] or 0, o[side:lower() .. "Out"]
		if o.air then
			airLeg(p, side, foot, o[side:lower() .. "Tuck"] or o.tuck or 30, out)
		else
			plantedLeg(p, side, foot * LEG_SCALE, drop, out)
		end
	end
	local lean, twist, tilt = o.lean or 0, o.twist or 0, o.tilt or 0
	p.UpperTorso = rot(lean, twist, tilt)
	p.Head = rot(-lean * 0.6, -twist * 0.8, -tilt * 0.6)
	armPose(p, "Right", o.R)
	armPose(p, "Left", o.L)
	return p
end

local function with(base, changes)
	local o = table.clone(base)
	for k, v in changes do
		o[k] = v
	end
	return o
end

-- Mirror a whole animation to the other hand: swap Right/Left parts and reflect across the body's center.
local function mirrorCFrame(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end
local function mirror(keyframes)
	local out = {}
	for i, kf in keyframes do
		local poses = {}
		for part, cf in kf[2] do
			local other = if part:sub(1, 5) == "Right" then "Left" .. part:sub(6) elseif part:sub(1, 4) == "Left" then "Right" .. part:sub(5) else part
			poses[other] = mirrorCFrame(cf)
		end
		out[i] = { kf[1], poses }
	end
	return out
end
assert((mirrorCFrame(rot(10, 20, 30)).LookVector - rot(10, -20, -30).LookVector).Magnitude < 1e-6, "mirror flips yaw and roll")

local function both(name, keyframes)
	build(name, keyframes)
	build(name .. "_L", mirror(keyframes))
end

local function frames(list) -- { time, bodyOptions } -> keyframes
	local out = {}
	for i, f in list do
		out[i] = { f[1], body(f[2]) }
	end
	return out
end

-- Shared stances and arm poses (right hand has the ball)
local BALL_R, BALL_L = { 15, 0, 15, 45, -15 }, { 15, 0, -15, 45, -15 } -- dribbling low at the side
local GUARD_R, GUARD_L = { 35, 0, 25, 55 }, { 35, 0, -25, 55 } -- off arm up, protecting the ball
local GATHER_R, GATHER_L = { 45, 0, -20, 100 }, { 45, 0, 20, 100 } -- both hands on the ball at the chest
local READY = { drop = 0.45, left = 0.5, right = -0.4, lean = -15, R = BALL_R, L = GUARD_L }
local READY_LEFT_HAND = with(READY, { R = GUARD_R, L = BALL_L })
local TRIPLE_THREAT = { drop = 0.45, left = 0.17, right = -0.17, lean = -4, R = GATHER_R, L = GATHER_L }

both("Crossover", frames({
	{ 0, READY },
	{ 0.12, { drop = 0.5, left = 0.5, right = -0.4, lean = -16, twist = -6, tilt = -8, R = { 25, 0, -5, 60, -20 }, L = GUARD_L } }, -- sell right
	{ 0.25, { drop = 0.55, left = 0.6, right = -0.33, lean = -18, twist = 14, tilt = 6, R = { 30, 20, -35, 70, -10 }, L = { 20, 0, -12, 40, -10 } } }, -- ball across
	{ 0.38, { drop = 0.52, left = 0.5, right = -0.47, lean = -20, twist = 10, tilt = 4, R = { 40, -10, 20, 60 }, L = BALL_L } }, -- catch left, attack
	{ 0.5, READY_LEFT_HAND },
}))

local TWEEN_DOWN = { drop = 0.7, left = 1.17, right = -0.73, lean = -22, R = { 5, 0, -12, 30, -10 }, L = GUARD_L } -- lunge, push ball down
local TWEEN_THROUGH = { drop = 0.72, left = 1.2, right = -0.73, lean = -26, twist = -8, R = { -12, 0, -16, 20 }, L = { -15, 0, -18, 25 } } -- under the front leg
local TWEEN_CATCH = { drop = 0.58, left = 0.83, right = -0.53, lean = -18, twist = 6, R = { 40, 0, 15, 60 }, L = BALL_L }
both("BetweenLegs", frames({
	{ 0, READY },
	{ 0.12, TWEEN_DOWN },
	{ 0.26, TWEEN_THROUGH },
	{ 0.4, TWEEN_CATCH },
	{ 0.55, READY_LEFT_HAND },
}))

both("DoubleTween", frames({ -- between the legs and straight back
	{ 0, READY },
	{ 0.12, TWEEN_DOWN },
	{ 0.26, TWEEN_THROUGH },
	{ 0.4, TWEEN_CATCH },
	{ 0.52, { drop = 0.7, left = 1.17, right = -0.73, lean = -24, R = { 30, 0, 20, 55 }, L = { 5, 0, 12, 30, -10 } } },
	{ 0.64, { drop = 0.72, left = 1.2, right = -0.73, lean = -26, twist = 8, R = { -15, 0, 18, 25 }, L = { -12, 0, 16, 20 } } },
	{ 0.85, READY },
}))

both("BehindBack", frames({
	{ 0, READY },
	{ 0.12, { drop = 0.5, left = 0.5, right = -0.4, lean = -14, twist = -15, R = { -30, 0, 15, 40 }, L = GUARD_L } }, -- pull the ball back
	{ 0.26, { drop = 0.55, left = 0.53, right = -0.4, lean = -16, twist = 10, R = { -50, 0, -35, 20 }, L = { -25, 0, -25, 30 } } }, -- wrap behind the hips (elbow nearly straight so the hand really goes behind)
	{ 0.4, { drop = 0.52, left = 0.5, right = -0.4, lean = -18, twist = 12, R = GUARD_R, L = BALL_L } },
	{ 0.55, READY_LEFT_HAND },
}))

both("InAndOut", frames({ -- fake crossover
	{ 0, READY },
	{ 0.14, { drop = 0.55, left = 0.83, right = -0.4, lean = -16, twist = 18, tilt = 8, R = { 25, 15, -25, 60 }, L = GUARD_L } }, -- sell it: ball in, shoulders left
	{ 0.28, { drop = 0.5, left = 0.5, right = -0.4, lean = -16, twist = -12, tilt = -6, R = { 20, -10, 25, 45 }, L = GUARD_L } }, -- snap it back out
	{ 0.4, { drop = 0.55, left = 0.33, right = -0.83, lean = -22, twist = -6, R = { 10, 0, 15, 40 }, L = { 45, 0, -15, 65 } } }, -- go right
	{ 0.5, READY },
}))

both("Hesitation", frames({
	{ 0, READY },
	{ 0.15, { drop = 0.25, left = 0.4, right = -0.33, lean = 2, R = { 30, 0, 15, 70 }, L = { 15, 0, -10, 30 } } }, -- rise up, eyes up: "I'm stopping"
	{ 0.32, { drop = 0.27, left = 0.4, right = -0.33, lean = 0, R = { 28, 0, 15, 68 }, L = { 15, 0, -10, 30 } } }, -- hold
	{ 0.45, { drop = 0.6, left = 0.33, right = -1, lean = -28, R = { 35, 0, 10, 30 }, L = { 45, 0, -15, 70 } } }, -- explode
	{ 0.6, READY },
}))

-- Stepbacks: sell the drive, hop back, land square into triple threat. `depth` scales how big, `speed` how fast.
local function stepback(depth, speed, hops)
	local t, list = 0, { { 0, READY } }
	local function at(dt, o)
		t += dt / speed
		table.insert(list, { t, o })
	end
	at(0.12, { drop = 0.65 * depth, left = 1.17, right = -0.5, lean = -20, R = { 30, 0, 10, 40 }, L = GUARD_L }) -- plant: sell the drive
	for hop = 1, hops do
		at(0.16, { air = 0.35 * depth, left = 0.5, right = 0.17, tuck = 35, lean = -5, R = { 40, 0, 0, 80 }, L = { 35, 0, -10, 70 } }) -- hop back
		local last = hop == hops
		at(0.14, { drop = 0.7 * depth, left = if last then 0.3 else 0.65, right = if last then -0.3 else -0.6, lean = if last then -6 else -14, R = if last then GATHER_R else BALL_R, L = if last then GATHER_L else GUARD_L })
	end
	at(0.13, with(TRIPLE_THREAT, { drop = 0.55 }))
	at(0.15, TRIPLE_THREAT)
	return frames(list)
end
both("Stepback", stepback(1, 1, 1))
both("StepbackEscape", stepback(1.15, 1.25, 2)) -- two quick, deep hops

-- Side-steps: push off the left leg, hop right, land wide into triple threat.
local function sidestep(depth, speed)
	return frames({
		{ 0, READY },
		{ 0.12 / speed, { drop = 0.6 * depth, left = 0.5, right = -0.27, leftOut = -15, rightOut = 5, lean = -14, tilt = -10, R = BALL_R, L = GUARD_L } }, -- load and lean right
		{ 0.26 / speed, { air = 0.3 * depth, left = 0.17, right = 0.17, leftOut = -5, rightOut = 10, tuck = 30, lean = -6, tilt = -8, R = { 40, 0, 0, 80 }, L = { 35, 0, -10, 70 } } }, -- in the air
		{ 0.42 / speed, { drop = 0.6 * depth, left = 0.17, right = -0.17, leftOut = -12, rightOut = 14, lean = -6, tilt = -4, R = GATHER_R, L = GATHER_L } }, -- land wide
		{ 0.6 / speed, TRIPLE_THREAT },
	})
end
both("SideStep", sidestep(1, 1))
both("SideStepEscape", sidestep(1.2, 1.3))

-- Spin escape: low, ball pulled tight to the chest, off arm out; the body turns in 90° steps.
local function spinFrame(degrees)
	return { drop = 0.55, left = 0.33, right = -0.33, hipTurn = -degrees, lean = -15, R = { 40, 0, -10, 100 }, L = { 25, 0, -55, 20 } }
end
both("SpinEscape", frames({
	{ 0, READY },
	{ 0.1, spinFrame(60) },
	{ 0.22, spinFrame(150) },
	{ 0.34, spinFrame(240) },
	{ 0.44, spinFrame(330) },
	{ 0.55, READY },
}))

-- Finishes at the rim. In the air, `air` lifts the body; the game also makes the character jump.
local HIP_GATHER_R, HIP_GATHER_L = { 35, 0, -20, 90 }, { 35, 0, 20, 90 } -- both hands on the ball at the hip

both("Layup", frames({ -- right-hand layup: right-left steps, jump off the left foot, right knee drives
	{ 0, READY },
	{ 0.15, { drop = 0.55, right = 0.8, left = -0.5, lean = -20, R = HIP_GATHER_R, L = HIP_GATHER_L } }, -- gather step, right foot
	{ 0.32, { drop = 0.65, left = 0.9, right = -0.4, lean = -12, R = GATHER_R, L = GATHER_L } }, -- left foot plants to jump, ball rising
	{ 0.5, { air = 0.5, right = 2.4, left = -0.4, rightTuck = 95, tuck = 25, lean = 0, R = { 150, 0, 10, 30, 30 }, L = { 70, 0, -20, 60 } } }, -- take off, knee drive
	{ 0.68, { air = 0.7, right = 2.6, left = -0.5, rightTuck = 100, tuck = 30, lean = 4, R = { 170, 0, 5, 5, 60 }, L = { 60, 0, -25, 50 } } }, -- full stretch, finger roll
	{ 0.86, { air = 0.3, right = 0.5, left = 0.2, rightTuck = 40, tuck = 30, lean = -2, R = { 120, 0, 10, 30 }, L = { 40, 0, -20, 40 } } }, -- coming down
	{ 1.0, { drop = 0.6, left = 0.4, right = -0.2, lean = -10, R = { 30, 0, 15, 30 }, L = { 30, 0, -15, 30 } } }, -- soft landing
	{ 1.15, { drop = 0.3, left = 0.2, right = -0.1, lean = -5, R = { 10, 0, 5, 20 }, L = { 10, 0, -5, 20 } } },
}))

both("Dunk", frames({ -- right-hand dunk off two steps
	{ 0, READY },
	{ 0.15, { drop = 0.55, right = 0.8, left = -0.5, lean = -20, R = HIP_GATHER_R, L = HIP_GATHER_L } }, -- gather step
	{ 0.32, { drop = 0.8, left = 0.9, right = -0.4, lean = -18, R = { -20, 0, 10, 30 }, L = { -20, 0, -10, 30 } } }, -- deep load, arms swing back
	{ 0.5, { air = 0.6, right = 1.5, left = -0.3, rightTuck = 80, tuck = 40, lean = -5, R = { 150, 0, -10, 60 }, L = { 150, 0, 10, 60 } } }, -- explode up, ball overhead
	{ 0.66, { air = 1.0, right = 1.8, left = -0.6, rightTuck = 100, tuck = 60, lean = 8, R = { 175, 0, 10, 110, -30 }, L = { 110, 0, -30, 20 } } }, -- cock it back, legs kick
	{ 0.8, { air = 0.9, right = 1.2, left = 0, rightTuck = 70, tuck = 50, lean = -15, R = { 120, 0, 10, 10, 70 }, L = { 80, 0, -30, 20 } } }, -- slam through the rim
	{ 0.92, { air = 0.4, right = 0.5, left = 0, rightTuck = 30, tuck = 30, lean = -8, R = { 140, 0, 5, 15 }, L = { 60, 0, -25, 20 } } }, -- drop
	{ 1.05, { drop = 0.75, left = 0.5, right = -0.3, lean = -18, R = { 40, 0, 20, 40 }, L = { 40, 0, -20, 40 } } }, -- heavy landing
	{ 1.25, { drop = 0.35, left = 0.2, right = -0.15, lean = -6, R = { 15, 0, 10, 25 }, L = { 15, 0, -10, 25 } } },
}))

build("DunkTwoHand", frames({ -- two-foot jump, both hands
	{ 0, READY },
	{ 0.15, { drop = 0.55, right = 0.7, left = -0.4, lean = -20, R = HIP_GATHER_R, L = HIP_GATHER_L } }, -- last step
	{ 0.3, { drop = 0.85, left = 0.3, right = 0.3, lean = -25, R = { -30, 0, 15, 20 }, L = { -30, 0, -15, 20 } } }, -- feet together, load, arms back
	{ 0.48, { air = 0.6, left = 0.1, right = 0.1, tuck = 20, lean = -5, R = { 150, 0, -5, 40 }, L = { 150, 0, 5, 40 } } }, -- take off
	{ 0.64, { air = 1.0, left = -0.6, right = -0.6, tuck = 80, lean = 10, R = { 178, 0, -5, 100, -20 }, L = { 178, 0, 5, 100, -20 } } }, -- arch, ball behind the head
	{ 0.78, { air = 0.9, left = 0.4, right = 0.4, tuck = 50, lean = -18, R = { 115, 0, -5, 10, 60 }, L = { 115, 0, 5, 10, 60 } } }, -- slam
	{ 0.92, { air = 0.4, left = 0.2, right = 0.2, tuck = 30, lean = -8, R = { 130, 0, -8, 20 }, L = { 130, 0, 8, 20 } } },
	{ 1.05, { drop = 0.8, left = 0.3, right = 0.2, lean = -20, R = { 45, 0, 20, 40 }, L = { 45, 0, -20, 40 } } }, -- land
	{ 1.25, { drop = 0.35, left = 0.15, right = -0.1, lean = -6, R = { 15, 0, 10, 25 }, L = { 15, 0, -10, 25 } } },
}))
