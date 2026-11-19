-- Client: input, camera, UI, and animating players every frame (the ball handler, blockers, defenders).
-- Every client draws the ball and bends arms itself, from the server's attributes and the shared
-- server clock, so nothing animated waits on the network and everyone (server included) agrees where
-- the ball is. Your own moves, shots and blocks start instantly; the server hears after.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Hoops = require(ReplicatedStorage:WaitForChild("Hoops"))
local action = ReplicatedStorage:WaitForChild("Action")
local ball = workspace:WaitForChild("Basketball"):WaitForChild("Ball")
local me = Players.LocalPlayer

local METER_MAX = Hoops.PERFECT_HOLD + Hoops.SHOT_WINDOW
local SIDE = { Right = 1, Left = -1 }
local RIM = Vector3.new(0, Hoops.RIM_Y, Hoops.RIM_Z)
local GREEN = Color3.fromRGB(70, 230, 110)

local function new(className, props)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	return inst
end

local function rounded(frame, radius) -- a soft corner and a thin outline, for a cleaner look
	new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = frame })
	new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.7, Thickness = 1.5, Parent = frame })
	return frame
end

pcall(function() -- no Roblox health bar on the court
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- UI ------------------------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "R2K", ResetOnSpawn = false })

-- Shot meter: fills while you hold shoot and turns green inside the green window; release on the line.
local meter = rounded(new("Frame", { Size = UDim2.fromOffset(14, 130), Position = UDim2.new(0.5, 70, 0.5, -95), BackgroundColor3 = Color3.fromRGB(20, 20, 26), BackgroundTransparency = 0.25, Visible = false, Parent = gui }), 7)
local fill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = meter })
new("UICorner", { CornerRadius = UDim.new(0, 7), Parent = fill })
new("Frame", { Size = UDim2.new(1, 10, 0, 3), Position = UDim2.new(0, -5, 1 - Hoops.PERFECT_HOLD / METER_MAX, -1), BackgroundColor3 = GREEN, BorderSizePixel = 0, Parent = meter })
-- What your release was: GREEN!, Slightly Early, Very Late...
local feedback = new("TextLabel", { Size = UDim2.fromOffset(220, 30), Position = UDim2.new(0.5, 95, 0.5, -60), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, TextScaled = true, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, Visible = false, Parent = gui })

-- Game status from the server: waiting, first to 21, who won.
local status = ReplicatedStorage:WaitForChild("Status")
local banner = rounded(new("TextLabel", { Size = UDim2.fromOffset(300, 34), Position = UDim2.new(0.5, -150, 0, 10), BackgroundColor3 = Color3.fromRGB(16, 16, 22), BackgroundTransparency = 0.2, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.GothamBold, Text = status.Value, Parent = gui }), 10)
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = banner })
status.Changed:Connect(function(text)
	banner.Text = text
end)

-- Score popup: pops in big whenever anyone scores.
local popup = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(420, 70), Position = UDim2.fromScale(0.5, 0.27), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(255, 205, 50), TextStrokeTransparency = 0, TextScaled = true, Font = Enum.Font.GothamBlack, Visible = false, Parent = gui })
local function flash(label, text, color, seconds) -- show a label briefly with a little pop; a newer flash wins
	label.Text, label.TextColor3, label.Visible = text, color, true
	local scale = label:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = label })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local stamp = os.clock()
	label:SetAttribute("Stamp", stamp)
	task.delay(seconds, function()
		if label:GetAttribute("Stamp") == stamp then
			label.Visible = false
		end
	end)
end
ReplicatedStorage:WaitForChild("Scored").OnClientEvent:Connect(function(scorer, points)
	flash(popup, if scorer == me then `+{points}  BUCKET!` else `{scorer.DisplayName} +{points}`, popup.TextColor3, 1.5)
end)
gui.Parent = me:WaitForChild("PlayerGui")

-- Arms --------------------------------------------------------------------------------------------
-- Roblox's IK solver pulls each hand to a target (a local world-space attachment). One rig per character
-- that needs one, made on first use.
local rigs = {} -- [character] = { [side] = { target, pole, ik } }

local function rigFor(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not rigs[char] and hum then
		local rig = {}
		for side in SIDE do
			local arm = { target = new("Attachment", { Parent = workspace.Terrain }), pole = new("Attachment", { Parent = workspace.Terrain }) }
			local upperArm, hand = char:FindFirstChild(side .. "UpperArm"), char:FindFirstChild(side .. "Hand")
			if upperArm and hand then -- R15 only
				arm.ik = new("IKControl", { Type = Enum.IKControlType.Position, ChainRoot = upperArm, EndEffector = hand, Target = arm.target, Pole = arm.pole, Weight = 0, Parent = hum })
			end
			rig[side] = arm
		end
		rigs[char] = rig
	end
	return rigs[char]
end

-- My state ----------------------------------------------------------------------------------------
-- While I hold the ball I predict my own state (server-clock times) so my moves start instantly;
-- for everyone else I read the server's attributes.
local myHand, myMove, myMoveHand, myMoveAt = "Right", nil, nil, 0
local myBlockAt = 0
local shootStart = nil -- os.clock() when I started holding shoot (for the meter)
local sprinting, l2Held, inStance = false, false, false

local function iHaveBall()
	return ball:GetAttribute("Holder") == me.UserId
end

local function myRoot()
	return me.Character and me.Character:FindFirstChild("HumanoidRootPart")
end

ball:GetAttributeChangedSignal("Holder"):Connect(function()
	-- The server sets these before Holder, so a new possession starts in sync with it.
	myHand, myMove, myMoveHand = ball:GetAttribute("Hand") or "Right", ball:GetAttribute("Move"), ball:GetAttribute("MoveHand")
	myMoveAt = ball:GetAttribute("MoveAt") or 0
end)

-- Animations --------------------------------------------------------------------------------------
-- Published by the game's owner; Roblox shows animations I play on my own character to everyone.
-- Dribble moves, stances, Layup and Dunk are authored from the right hand; "_L" is the left-hand mirror.
local ANIMATIONS = {
	BehindBack = 97720416461332, BehindBack_L = 110947973652762,
	BetweenLegs = 119329621765672, BetweenLegs_L = 84879209746710,
	Block = 122226333881077,
	Crossover = 95030049810426, Crossover_L = 89350225332049,
	DefenseStance = nil, -- shortcut: new animations, no IDs until they're published; they just don't play until then
	DoubleTween = 90668950670519, DoubleTween_L = 109728765164717,
	DribbleStance = nil, DribbleStance_L = nil,
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
local stanceTrack = nil -- the looping stance overlay playing now (DribbleStance / DefenseStance)
me.CharacterAdded:Connect(function()
	table.clear(tracks)
	stanceTrack = nil
end)

-- Play one of my animations; returns the track (nil if my character isn't ready or it has no ID yet).
local function play(name, fade)
	if not tracks[name] then
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator or not ANIMATIONS[name] then
			return nil
		end
		tracks[name] = animator:LoadAnimation(new("Animation", { AnimationId = `rbxassetid://{ANIMATIONS[name]}` }))
	end
	tracks[name]:Play(fade or 0.1)
	return tracks[name]
end

local function sided(name) -- the version for the hand the ball is in
	return if myHand == "Left" then name .. "_L" else name
end

-- Every frame: ball, arms, my movement, my stance -------------------------------------------------
RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	if shootStart then
		local held = os.clock() - shootStart
		fill.Size = UDim2.fromScale(1, math.min(held / METER_MAX, 1))
		fill.BackgroundColor3 = if Hoops.shotQuality(held) >= Hoops.GREEN then GREEN else Color3.new(1, 1, 1)
	end

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
	local holderRoot = holder and holder.Character and holder.Character:FindFirstChild("HumanoidRootPart")
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local cf = root.CFrame

		-- Ball: the same function the server judges steals and blocks with, on the shared server clock.
		local pos, ballSide, hold
		if player == holder then
			local mine = player == me
			local hand = (if mine then myHand else ball:GetAttribute("Hand")) or "Right"
			local move = if mine then myMove else ball:GetAttribute("Move")
			local moveHand = if mine then myMoveHand else ball:GetAttribute("MoveHand")
			local moveAt = (if mine then myMoveAt else ball:GetAttribute("MoveAt")) or 0
			pos, ballSide, hold = Hoops.ballSpot(cf, hand, move, moveHand, moveAt, now)
			ball.CFrame = CFrame.new(pos)
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
				else -- the hand that has the ball rides the top of each bounce; both hold it in gathers and shots
					local dribble = math.clamp(0.5 + 0.5 * x * ballSide, 0, 1)
					local palmUp = pos.Y - cf.Position.Y > Hoops.SHOULDER_UP -- carried overhead: hand under the ball
					local onTop = if palmUp then pos - Vector3.new(0, Hoops.BALL_RADIUS, 0) else Vector3.new(pos.X, math.max(pos.Y + Hoops.BALL_RADIUS, handLow), pos.Z)
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

	-- My movement, like 2K: the ball handler faces the basket (unless sprinting), intense D (L2 on
	-- defense) slides facing the ball handler, everyone else turns where they run.
	local root = myRoot()
	local hum = root and me.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local stance = l2Held and not iHaveBall() and holderRoot ~= nil and holder ~= me
	if stance ~= inStance then
		inStance = stance
		action:FireServer("stance", stance) -- intense D contests shots from further away
	end
	hum.WalkSpeed = if stance then Hoops.STANCE_SPEED elseif sprinting then Hoops.SPRINT_SPEED else Hoops.WALK_SPEED
	local face = if iHaveBall() and not sprinting then RIM elseif stance then holderRoot.Position else nil
	local flat = face and Vector3.new(face.X - root.Position.X, 0, face.Z - root.Position.Z)
	local align = root:FindFirstChild("FaceAlign")
	if not align then
		local attachment = root:FindFirstChild("RootAttachment") or new("Attachment", { Parent = root })
		align = new("AlignOrientation", { Name = "FaceAlign", Mode = Enum.OrientationAlignmentMode.OneAttachment, Attachment0 = attachment, Responsiveness = 25, MaxTorque = 1e6, Enabled = false, Parent = root })
	end
	local facing = flat ~= nil and flat.Magnitude > 0.5
	hum.AutoRotate = not facing
	align.Enabled = facing
	if facing then
		align.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end

	-- Stance overlay under everything else: low dribble stance with the ball, defensive stance on L2.
	local wanted = if iHaveBall() then sided("DribbleStance") elseif stance then "DefenseStance" else nil
	local current = stanceTrack and stanceTrack.Name
	if wanted ~= current then
		if stanceTrack then
			stanceTrack:Stop(0.2)
		end
		stanceTrack = wanted and play(wanted, 0.2)
		if stanceTrack then
			stanceTrack.Name = wanted
		end
	end
end)

-- Camera ------------------------------------------------------------------------------------------
-- 2K park cam: behind your player on the line from the rim, looking past them at the hoop, easing after
-- them as they move. Movement keys and the right stick are relative to it (up = toward the basket).
local camera = workspace.CurrentCamera
local cameraCF = nil
RunService:BindToRenderStep("ParkCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Hoops.CAMERA_FOV
	local root = myRoot()
	if not root then
		return
	end
	local p = root.Position
	local away = Vector3.new(p.X - RIM.X, 0, p.Z - RIM.Z)
	local close = math.clamp(away.Magnitude / 8, 0, 1) -- right under the rim, settle to looking straight down court
	away = (if away.Magnitude > 0.01 then away.Unit * close else Vector3.zero) + Vector3.zAxis * (1 - close)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.zAxis
	local eye = p + away * Hoops.CAMERA_DISTANCE + Vector3.new(0, Hoops.CAMERA_HEIGHT, 0)
	local goal = CFrame.lookAt(eye, (p + Vector3.new(0, 1.5, 0)):Lerp(RIM, Hoops.CAMERA_LOOK))
	cameraCF = if cameraCF then cameraCF:Lerp(goal, 1 - math.exp(-Hoops.CAMERA_SMOOTH * dt)) else goal
	camera.CFrame = cameraCF
end)

-- Moves -------------------------------------------------------------------------------------------
-- Bursts of movement for stepbacks, side-steps and spins: { delay, direction, speed, seconds }.
local DASHES = {
	Stepback = { 0.12, "back", 18, 0.3 },
	StepbackEscape = { 0.1, "back", 20, 0.55 },
	SideStep = { 0.12, "side", 18, 0.3 },
	SideStepEscape = { 0.1, "side", 24, 0.35 },
	SpinMove = { 0.05, "forward", 16, 0.45 },
	SpinEscape = { 0.05, "forward", 20, 0.45 },
}

local function dash(direction, speed, duration) -- my character's physics are mine, so it's instant
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

-- Begin a move now: predict it so the ball moves instantly, tell the server, animate, dash.
-- The move's path (Hoops.MOVES) decides where the ball goes and which hand it ends in.
local function begin(name, at)
	local hand = myHand
	if name == "SpinMove" and hand == "Left" then
		name = "SpinEscape" -- SpinMove only has a right-hand animation
	end
	myMove, myMoveHand, myMoveAt = name, hand, at
	myHand = if Hoops.MOVES[name].switch then (if hand == "Right" then "Left" else "Right") else hand
	action:FireServer("move", name, at) -- send the start time so the server's ball matches mine
	play(if name == "SpinMove" then name elseif hand == "Left" then name .. "_L" else name)
	local d = DASHES[name]
	if d then
		task.delay(d[1], function()
			local root = myRoot()
			if root then
				local cf = root.CFrame
				dash(if d[2] == "back" then -cf.LookVector elseif d[2] == "side" then cf.RightVector * SIDE[hand] else cf.LookVector, d[3], d[4])
			end
		end)
	end
end

-- Chain like 2K: a move pressed during a move is buffered (the latest press wins) and starts the
-- moment the current one ends. Every path starts and ends at the dribble spot, so chains are seamless.
local queued = nil
local function tryMove(name)
	if not iHaveBall() or shootStart then
		return
	end
	local now = workspace:GetServerTimeNow()
	local last = Hoops.MOVES[myMove or ""]
	local endsAt = if last then myMoveAt + last.duration else now
	if now >= endsAt then
		begin(name, now)
		return
	end
	if not queued then
		task.delay(endsAt - now, function()
			local nextMove = queued
			queued = nil
			if nextMove and iHaveBall() and not shootStart then
				begin(nextMove, endsAt)
			end
		end)
	end
	queued = name
end

-- Input -------------------------------------------------------------------------------------------
-- Controller follows 2K: right stick = dribble moves, R2 = sprint, L2 = escape (offense) / intense D
-- (defense), X = shoot/steal, A = pass, Y = block. Keyboard: Shift sprint, Ctrl L2, letters for moves.
local HIGH = Enum.ContextActionPriority.High.Value -- above Roblox's own bindings (A is normally jump)

-- Triggers are analog and also send Change events while held: only Begin and End/Cancel count.
local function isHeld(state, was)
	return if state == Enum.UserInputState.Begin then true elseif state == Enum.UserInputState.Change then was else false
end

ContextActionService:BindActionAtPriority("Sprint", function(_, state)
	sprinting = isHeld(state, sprinting)
	return Enum.ContextActionResult.Pass
end, false, HIGH, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)

ContextActionService:BindActionAtPriority("L2", function(_, state)
	l2Held = isHeld(state, l2Held)
	return Enum.ContextActionResult.Pass
end, false, HIGH, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonL2)

-- Same button shoots on offense and steals on defense, like 2K. Near the rim, a shot is a layup or dunk.
local jumpShot = nil
ContextActionService:BindActionAtPriority("ShootOrSteal", function(_, state)
	if state == Enum.UserInputState.Begin then
		if iHaveBall() then
			local now = workspace:GetServerTimeNow()
			queued = nil -- the shot replaces any buffered move
			shootStart = os.clock()
			fill.Size = UDim2.fromScale(1, 0)
			meter.Visible = true
			local root = myRoot()
			local rimDist = root and Vector3.new(root.Position.X, 0, root.Position.Z - Hoops.RIM_Z).Magnitude or math.huge
			-- Every shot is a path (Hoops.MOVES), predicted here and checked by the server: a jump shot, or near the
			-- rim a layup or dunk. Like any move, it starts once the last one ends.
			local finish = if rimDist > Hoops.LAYUP_RANGE then "JumpShot" elseif rimDist > Hoops.DUNK_RANGE then "Layup" elseif math.random() < 0.3 then "DunkTwoHand" else "Dunk"
			local last = Hoops.MOVES[myMove or ""]
			local startAt = math.max(now, if last then myMoveAt + last.duration else now)
			myMove, myMoveHand, myMoveAt = finish, myHand, startAt
			action:FireServer("shootStart", finish, startAt)
			if finish == "JumpShot" then
				-- rise to the set point, hold it while the meter fills, release when you let go
				jumpShot = play("JumpShot")
				local started = shootStart
				task.delay(startAt - now + Hoops.MOVES.JumpShot.duration, function()
					if jumpShot and shootStart == started then
						jumpShot:AdjustSpeed(0)
					end
				end)
			else
				play(if finish == "DunkTwoHand" then finish else sided(finish))
				task.delay(startAt - now + Hoops.MOVES[finish].jumpAt, function() -- jump at the animation's takeoff
					local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
					if hum and iHaveBall() and myMove == finish then -- still holding it: not released, stolen or blocked
						hum.Jump = true
					end
				end)
			end
		else
			play("StealSwipe")
			action:FireServer("steal")
		end
	elseif shootStart and (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) then
		local held = os.clock() - shootStart
		action:FireServer("shoot", held)
		shootStart = nil
		meter.Visible = false
		if jumpShot then
			jumpShot:AdjustSpeed(1)
			jumpShot = nil
		end
		local quality = Hoops.shotQuality(held)
		local timing = if held < Hoops.PERFECT_HOLD then "Early" else "Late"
		flash(feedback, if quality >= Hoops.GREEN then "GREEN!" else `{if quality >= 0.5 then "Slightly" else "Very"} {timing}`, if quality >= Hoops.GREEN then GREEN else Color3.fromRGB(255, 170, 60), 1)
	end
end, true, HIGH, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

ContextActionService:BindActionAtPriority("Pass", function(_, state)
	if state == Enum.UserInputState.Begin and iHaveBall() then
		queued = nil
		action:FireServer("pass")
	end
end, true, HIGH, Enum.KeyCode.R, Enum.KeyCode.ButtonA)

-- Block: jump with both arms up. Anyone can do it anywhere; it only matters near the ball handler.
ContextActionService:BindActionAtPriority("Block", function(_, state)
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
end, true, HIGH, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

-- Pro stick: flick the right stick and let go; Hoops.proStick turns the flick into a move (tested there).
-- The flick's direction is where it reached furthest; spins are a half circle.
local flick = nil
ContextActionService:BindActionAtPriority("ProStick", function(_, state, input)
	local p = Vector2.new(input.Position.X, input.Position.Y)
	if not flick then
		if p.Magnitude > 0.6 then
			flick = { peak = p, angle = math.atan2(p.Y, p.X), turned = 0, at = os.clock() }
		end
	elseif p.Magnitude > 0.3 and state ~= Enum.UserInputState.End then
		local a = math.atan2(p.Y, p.X)
		flick.turned += math.deg((a - flick.angle + math.pi) % (2 * math.pi) - math.pi)
		flick.angle = a
		if p.Magnitude > flick.peak.Magnitude then
			flick.peak = p
		end
	else -- back to center: read the gesture
		local f = flick
		flick = nil
		if iHaveBall() then
			tryMove(Hoops.proStick(f.peak.X, f.peak.Y, f.turned, os.clock() - f.at, SIDE[myHand], l2Held))
		end
	end
	return Enum.ContextActionResult.Sink
end, false, HIGH, Enum.KeyCode.Thumbstick2)

-- Keyboard moves (Ctrl for the escape versions).
local KEYS = {
	{ Enum.KeyCode.Q, "Crossover" },
	{ Enum.KeyCode.Z, "BetweenLegs" },
	{ Enum.KeyCode.X, "BehindBack" },
	{ Enum.KeyCode.C, "InAndOut" },
	{ Enum.KeyCode.V, "Hesitation" },
	{ Enum.KeyCode.T, "DoubleTween" },
	{ Enum.KeyCode.G, "Stepback", "StepbackEscape" },
	{ Enum.KeyCode.H, "SideStep", "SideStepEscape" },
	{ Enum.KeyCode.B, "SpinMove", "SpinEscape" },
}
for _, key in KEYS do
	ContextActionService:BindAction("Key" .. key[2], function(_, state)
		if state == Enum.UserInputState.Begin then
			tryMove(if l2Held and key[3] then key[3] else key[2])
		end
	end, key[2] == "Crossover", key[1]) -- mobile gets a Cross button
end

ContextActionService:SetTitle("ShootOrSteal", "Shoot")
ContextActionService:SetTitle("KeyCrossover", "Cross")
ContextActionService:SetTitle("Pass", "Pass")
ContextActionService:SetTitle("Block", "Block")
