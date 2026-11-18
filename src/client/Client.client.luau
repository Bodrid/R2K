-- Client: input, the shot meter, and animating players every frame (the ball handler and blockers).
-- Every client draws the ball and bends arms itself, from the server's attributes and the shared
-- server clock, so nothing animated waits on the network and everyone (server included) agrees where
-- the ball is. Your own crossovers, gathers and blocks start instantly; the server hears after.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hoops = require(ReplicatedStorage:WaitForChild("Hoops"))
local action = ReplicatedStorage:WaitForChild("Action")
local ball = workspace:WaitForChild("Basketball"):WaitForChild("Ball")
local me = Players.LocalPlayer

local METER_MAX = Hoops.PERFECT_HOLD + Hoops.SHOT_WINDOW
local SIDE = { Right = 1, Left = -1 }

local function new(className, props)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	return inst
end

-- Shot meter: fills while you hold shoot; release on the green line.
local gui = new("ScreenGui", { Name = "ShotMeter", ResetOnSpawn = false })
local meter = new("Frame", { Size = UDim2.fromOffset(16, 120), Position = UDim2.new(0.5, 60, 0.5, -60), BackgroundColor3 = Color3.new(0.1, 0.1, 0.1), Visible = false, Parent = gui })
local fill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = meter })
new("Frame", { Size = UDim2.new(1, 8, 0, 3), Position = UDim2.new(0, -4, 1 - Hoops.PERFECT_HOLD / METER_MAX, -1), BackgroundColor3 = Color3.fromRGB(60, 220, 90), BorderSizePixel = 0, Parent = meter })
-- Game status from the server: waiting, first to 21, who won.
local status = ReplicatedStorage:WaitForChild("Status")
local banner = new("TextLabel", { Size = UDim2.fromOffset(320, 36), Position = UDim2.new(0.5, -160, 0, 8), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.GothamBold, Text = status.Value, Parent = gui })
status.Changed:Connect(function(text)
	banner.Text = text
end)
-- Score popup: big text in the middle of the screen whenever anyone scores.
local popup = new("TextLabel", { Size = UDim2.fromOffset(400, 70), Position = UDim2.new(0.5, -200, 0.25, 0), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(255, 200, 40), TextStrokeTransparency = 0, TextScaled = true, Font = Enum.Font.GothamBlack, Visible = false, Parent = gui })
local popupId = 0
ReplicatedStorage:WaitForChild("Scored").OnClientEvent:Connect(function(scorer, points)
	popup.Text = if scorer == me then `+{points}  BUCKET!` else `{scorer.DisplayName} +{points}`
	popup.Visible = true
	popupId += 1
	local id = popupId
	task.delay(1.5, function()
		if popupId == id then -- a newer score keeps its own popup up
			popup.Visible = false
		end
	end)
end)
gui.Parent = me:WaitForChild("PlayerGui")

-- Fixed 2K-style camera: one spot behind the arc looking at the hoop. Re-applied every frame because
-- Roblox's camera scripts reset it on respawn. Movement keys stay relative to it (W = toward the hoop).
local camera = workspace.CurrentCamera
local CAMERA = CFrame.lookAt(Vector3.new(0, Hoops.FLOOR_Y + Hoops.CAMERA_HEIGHT, Hoops.RIM_Z + Hoops.CAMERA_BACK), Vector3.new(0, Hoops.FLOOR_Y + 2, Hoops.RIM_Z + 10))
RunService:BindToRenderStep("FixedCamera", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Hoops.CAMERA_FOV
	camera.CFrame = CAMERA
end)

-- Arms: Roblox's IK solver pulls each hand to a target (a local world-space attachment).
-- One rig per character that needs one, made on first use.
-- shortcut: procedural arms look stiff for flashy moves; play keyframed animations for spins/step-backs later
local rigs = {} -- [character] = { [side] = { target, pole, ik } }

local function rigFor(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not rigs[char] and hum then
		local rig = {}
		for side in SIDE do
			local arm = { target = new("Attachment", { Parent = workspace.Terrain }), pole = new("Attachment", { Parent = workspace.Terrain }) }
			local upperArm, hand = char:FindFirstChild(side .. "UpperArm"), char:FindFirstChild(side .. "Hand")
			if upperArm and hand then -- R15 only; R6 characters play without arm motion
				arm.ik = new("IKControl", { Type = Enum.IKControlType.Position, ChainRoot = upperArm, EndEffector = hand, Target = arm.target, Pole = arm.pole, Weight = 0, Parent = hum })
			end
			rig[side] = arm
		end
		rigs[char] = rig
	end
	return rigs[char]
end

-- While I hold the ball I predict my own state (server-clock times) so my moves start instantly;
-- for everyone else I read the server's attributes.
local myHand, myMove, myMoveHand, myMoveAt, myGatherAt = "Right", nil, nil, 0, nil
local myBlockAt = 0
local shootStart = nil -- os.clock() when I started holding shoot (for the meter)

local function iHaveBall()
	return ball:GetAttribute("Holder") == me.UserId
end

ball:GetAttributeChangedSignal("Holder"):Connect(function()
	-- The server sets these before Holder, so a new possession starts in sync with it.
	-- Clearing myGatherAt here also holds a released shot's gather until the server takes the ball.
	myHand, myMove, myMoveHand = ball:GetAttribute("Hand") or "Right", ball:GetAttribute("Move"), ball:GetAttribute("MoveHand")
	myMoveAt, myGatherAt = ball:GetAttribute("MoveAt") or 0, nil
end)

RunService.RenderStepped:Connect(function()
	if shootStart then
		fill.Size = UDim2.fromScale(1, math.min((os.clock() - shootStart) / METER_MAX, 1))
	end
	local now = workspace:GetServerTimeNow()

	for char, rig in rigs do -- drop rigs of characters that left or respawned
		if not char:IsDescendantOf(workspace) then
			for _, arm in rig do
				arm.target:Destroy()
				arm.pole:Destroy()
				if arm.ik then
					arm.ik:Destroy()
				end
			end
			rigs[char] = nil
		end
	end

	local id = ball:GetAttribute("Holder")
	local holder = id and Players:GetPlayerByUserId(id)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local cf = root.CFrame

		-- Ball: the same function the server judges steals and blocks with, on the shared server clock.
		local pos, ballRight, hold
		if player == holder then
			local mine = player == me
			local hand = (if mine then myHand else ball:GetAttribute("Hand")) or "Right"
			local move = if mine then myMove else ball:GetAttribute("Move")
			local moveHand = if mine then myMoveHand else ball:GetAttribute("MoveHand")
			local moveAt = (if mine then myMoveAt else ball:GetAttribute("MoveAt")) or 0
			local gatherAt = if mine then myGatherAt else ball:GetAttribute("GatherAt")
			local g
			pos, ballRight, g = Hoops.ballSpot(cf, hand, move, moveHand, moveAt, gatherAt, now)
			ball.CFrame = CFrame.new(pos)
			-- Both hands take the ball once it's up at the chest (stepback gathers) or in a shot windup.
			hold = math.max(g, math.clamp((pos.Y - cf.Position.Y) / 0.5, 0, 1))
		end

		-- Block: arms snap straight up, hold, and come down over BLOCK_TIME (the jump does the rest).
		local blockAt = (if player == me then myBlockAt else char:GetAttribute("BlockAt")) or 0
		local b = (now - blockAt) / Hoops.BLOCK_TIME
		local up = if b >= 0 and b < 1 then math.min(1, 4 * b, 4 * (1 - b)) else 0

		local rig = (up > 0 or pos or rigs[char]) and rigFor(char)
		if rig then
			local handLow = cf.Position.Y + Hoops.HAND_LOW
			for side, x in SIDE do
				local arm = rig[side]
				local weight = up
				if up > 0 or not pos then
					arm.target.WorldPosition = Hoops.blockHands(cf) + cf.RightVector * x * 0.6
					arm.pole.WorldPosition = cf * Vector3.new(x * 3, 1.5, 0) -- elbows out to the sides
				else -- the hand on the ball's side rides the top of each bounce wherever the move takes it
					local dribble = math.clamp(0.5 + x * ballRight / (2 * Hoops.DRIBBLE_SIDE), 0, 1)
					local onTop = Vector3.new(pos.X, math.max(pos.Y + Hoops.BALL_RADIUS, handLow), pos.Z)
					arm.target.WorldPosition = onTop:Lerp(pos + cf.RightVector * x * (Hoops.BALL_RADIUS + 0.2), hold)
					arm.pole.WorldPosition = cf * Vector3.new(x * 3, -1, 1.5) -- elbows bend out and back
					weight = math.max(dribble, hold)
				end
				if arm.ik then
					arm.ik.Weight = weight
				end
			end
		end
	end
end)

-- Animations (published by the game's owner; Roblox shows animations I play on my own character to
-- everyone). Dribble moves, Layup and Dunk are authored from the right hand; "_L" is the left-hand mirror.
local ANIMATIONS = {
	BehindBack = 97720416461332, BehindBack_L = 110947973652762,
	BetweenLegs = 119329621765672, BetweenLegs_L = 84879209746710,
	Block = 122226333881077,
	Crossover = 95030049810426, Crossover_L = 89350225332049,
	DoubleTween = 90668950670519, DoubleTween_L = 109728765164717,
	Dunk = 116371417778801, Dunk_L = 93055928232785, DunkTwoHand = 86215529812622,
	Hesitation = 115297373334157, Hesitation_L = 127581419750676,
	InAndOut = 125228112161422, InAndOut_L = 82658335277698,
	JumpShot = 84279351689285,
	Layup = 93244724633892, Layup_L = 79293506735548,
	SideStep = 88825168648212, SideStep_L = 134410382844275,
	SideStepEscape = 123156882174859, SideStepEscape_L = 90507189105160,
	SpinEscape = 134644387886968, SpinEscape_L = 71163240371728,
	SpinMove = 128724466317154,
	StealSwipe = 140227535096778,
	Stepback = 106350331428838, Stepback_L = 100781301809205,
	StepbackEscape = 113030727017982, StepbackEscape_L = 130891165327063,
}

local tracks = {} -- [name] = AnimationTrack on my current character
me.CharacterAdded:Connect(function()
	table.clear(tracks)
end)

-- Play one of my animations; returns the track (nil if my character isn't ready).
local function play(name)
	if not tracks[name] then
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then
			return nil
		end
		tracks[name] = animator:LoadAnimation(new("Animation", { AnimationId = `rbxassetid://{ANIMATIONS[name]}` }))
	end
	tracks[name]:Play(0.1)
	return tracks[name]
end

local function sided(name) -- the version for the hand the ball is in
	return if myHand == "Left" then name .. "_L" else name
end

local function myRoot()
	return me.Character and me.Character:FindFirstChild("HumanoidRootPart")
end

-- A short burst of speed for stepbacks, side-steps and spins (my character's physics are mine, so it's instant).
local function dash(direction, speed, duration)
	local root = myRoot()
	if not root then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z).Unit * speed
	local attachment = new("Attachment", { Parent = root })
	new("LinearVelocity", {
		Attachment0 = attachment,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Plane, -- horizontal only, gravity still works
		PrimaryTangentAxis = Vector3.xAxis,
		SecondaryTangentAxis = Vector3.zAxis,
		PlaneVelocity = Vector2.new(flat.X, flat.Z),
		MaxForce = 50000,
		Parent = root,
	})
	task.delay(duration, function()
		attachment:Destroy() -- takes the LinearVelocity with it
	end)
end

-- Start a dribble move: predict it here so the ball moves instantly, tell the server, play the animation.
-- The move's path (Hoops.MOVES) decides where the ball goes and which hand it ends in.
local function startMove(name, animation)
	local now = workspace:GetServerTimeNow()
	local last = Hoops.MOVES[myMove or ""]
	if not iHaveBall() or shootStart or (last and now < myMoveAt + last.duration) then
		return false
	end
	local switch = Hoops.MOVES[name].switch
	myMove, myMoveHand, myMoveAt = name, myHand, now
	myHand = if switch then (if myHand == "Right" then "Left" else "Right") else myHand
	action:FireServer("move", name, now) -- send the start time so the server's ball matches mine
	play(animation)
	return true
end

-- Same button shoots on offense and steals on defense, like 2K. Near the rim, a shot is a layup or dunk.
local jumpShot = nil
ContextActionService:BindAction("ShootOrSteal", function(_, state)
	if state == Enum.UserInputState.Begin then
		if iHaveBall() then
			shootStart, myGatherAt = os.clock(), workspace:GetServerTimeNow()
			fill.Size = UDim2.fromScale(1, 0)
			meter.Visible = true
			action:FireServer("shootStart")
			local root = myRoot()
			local rimDist = root and Vector3.new(root.Position.X, 0, root.Position.Z - Hoops.RIM_Z).Magnitude or math.huge
			if rimDist <= Hoops.LAYUP_RANGE then
				local hum = me.Character:FindFirstChildOfClass("Humanoid")
				hum.Jump = true
				play(if rimDist > Hoops.DUNK_RANGE then sided("Layup") elseif math.random() < 0.3 then "DunkTwoHand" else sided("Dunk"))
			else
				-- Jump shot: rise to the set point, hold it while the meter fills, release when you let go.
				jumpShot = play("JumpShot")
				local started = shootStart
				task.delay(0.35, function()
					if jumpShot and shootStart == started then
						jumpShot:AdjustSpeed(0)
					end
				end)
			end
		else
			play("StealSwipe")
			action:FireServer("steal")
		end
	elseif shootStart and (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) then
		action:FireServer("shoot", os.clock() - shootStart)
		shootStart = nil
		meter.Visible = false
		if jumpShot then
			jumpShot:AdjustSpeed(1)
			jumpShot = nil
		end
	end
end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

ContextActionService:BindAction("Crossover", function(_, state)
	if state == Enum.UserInputState.Begin then
		startMove("Crossover", sided("Crossover"))
	end
end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)

ContextActionService:BindAction("Pass", function(_, state)
	if state == Enum.UserInputState.Begin and iHaveBall() then
		action:FireServer("pass")
	end
end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonB)

-- Block: jump with both arms up. Anyone can do it anywhere; it only matters near the ball handler.
ContextActionService:BindAction("Block", function(_, state)
	local now = workspace:GetServerTimeNow()
	if state == Enum.UserInputState.Begin and not iHaveBall() and now - myBlockAt >= Hoops.BLOCK_COOLDOWN then
		myBlockAt = now
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Jump = true
		end
		play("Block")
		action:FireServer("block")
	end
end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

-- Dribble moves (keyboard and gamepad). The ball's path for each is in Hoops.MOVES.
-- dash: burst of movement { delay, direction, speed, time }. Hold Shift / L2 for the escape version.
local escapeHeld = false
ContextActionService:BindAction("Escape", function(_, state)
	escapeHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

local MOVES = {
	{ name = "BetweenLegs", keys = { Enum.KeyCode.Z, Enum.KeyCode.DPadLeft } },
	{ name = "BehindBack", keys = { Enum.KeyCode.X, Enum.KeyCode.DPadRight } },
	{ name = "InAndOut", keys = { Enum.KeyCode.C, Enum.KeyCode.DPadUp } },
	{ name = "Hesitation", keys = { Enum.KeyCode.V, Enum.KeyCode.DPadDown } },
	{ name = "DoubleTween", keys = { Enum.KeyCode.T } },
	{ name = "Stepback", escape = "StepbackEscape", keys = { Enum.KeyCode.G, Enum.KeyCode.ButtonR1 }, dash = { 0.12, "back", 18, 0.3 }, escapeDash = { 0.1, "back", 20, 0.55 } },
	{ name = "SideStep", escape = "SideStepEscape", keys = { Enum.KeyCode.H, Enum.KeyCode.ButtonR2 }, dash = { 0.12, "side", 18, 0.3 }, escapeDash = { 0.1, "side", 24, 0.35 } },
	{ name = "SpinMove", escape = "SpinEscape", keys = { Enum.KeyCode.B, Enum.KeyCode.ButtonR3 }, dash = { 0.05, "forward", 16, 0.45 }, escapeDash = { 0.05, "forward", 20, 0.45 } },
}
for _, move in MOVES do
	ContextActionService:BindAction(move.name, function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return
		end
		-- SpinMove has no left-hand animation, so from the left hand a spin is always the spin escape.
		local escape = (escapeHeld or (move.name == "SpinMove" and myHand == "Left")) and move.escape
		local name = escape or move.name
		local hand = myHand
		if not startMove(name, if name == "SpinMove" then name else sided(name)) then
			return
		end
		local d = if escape then move.escapeDash else move.dash
		if d then
			task.delay(d[1], function()
				local root = myRoot()
				if root then
					local cf = root.CFrame
					local dir = if d[2] == "back" then -cf.LookVector elseif d[2] == "side" then cf.RightVector * (if hand == "Left" then -1 else 1) else cf.LookVector
					dash(dir, d[3], d[4])
				end
			end)
		end
	end, false, table.unpack(move.keys))
end

ContextActionService:SetTitle("ShootOrSteal", "Shoot")
ContextActionService:SetTitle("Crossover", "Cross")
ContextActionService:SetTitle("Pass", "Pass")
ContextActionService:SetTitle("Block", "Block")
