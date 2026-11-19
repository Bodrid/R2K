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
local UserInputService = game:GetService("UserInputService")
local Hoops = require(ReplicatedStorage:WaitForChild("Hoops"))
local action = ReplicatedStorage:WaitForChild("Action")
local ball = workspace:WaitForChild("Basketball"):WaitForChild("Ball")
local me = Players.LocalPlayer

local METER_MAX = Hoops.PERFECT_HOLD + Hoops.SHOT_WINDOW
local SIDE = { Right = 1, Left = -1 }
local RIM = Vector3.new(0, Hoops.RIM_Y, Hoops.RIM_Z)
local GREEN = Color3.fromRGB(70, 230, 110)
local YELLOW, RED, ORANGE = Color3.fromRGB(250, 210, 60), Color3.fromRGB(235, 70, 60), Color3.fromRGB(255, 170, 60)

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

-- 2K-style bars that ride beside your player (sizes in studs; offsets are on screen: + is right of you).
local function sideBar(name, offsetX, width, height, barWidth)
	local board = new("BillboardGui", { Name = name, Size = UDim2.fromScale(width, height), StudsOffset = Vector3.new(offsetX, 0.6, 0), AlwaysOnTop = true, LightInfluence = 0, ResetOnSpawn = false, Enabled = false, Parent = me:WaitForChild("PlayerGui") })
	local bar = new("Frame", { Size = UDim2.fromScale(barWidth, 1), BackgroundColor3 = Color3.fromRGB(20, 20, 26), BackgroundTransparency = 0.2, Parent = board })
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bar })
	new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.5, Thickness = 1.5, Parent = bar })
	local barFill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BorderSizePixel = 0, Parent = bar })
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = barFill })
	return board, bar, barFill
end

-- Shot meter: fills while you hold shoot. Let go with the fill in the green band (it narrows when you're tired).
-- After the release it freezes a moment with your timing: Excellent, Slightly Early, Very Late...
local shotBar, meter, fill = sideBar("ShotMeter", 2.3, 3, 3.2, 0.14)
local band = new("Frame", { Position = UDim2.fromScale(-0.35, 0), Size = UDim2.fromScale(1.7, 0), BackgroundColor3 = GREEN, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 2, Parent = meter })
local feedback = new("TextLabel", { Position = UDim2.fromScale(0.22, 0.02), Size = UDim2.fromScale(0.78, 0.17), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, TextScaled = true, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, Visible = false, Parent = shotBar })
local shotGreen, meterUntil = Hoops.GREEN, 0 -- this shot's green threshold; when the frozen meter hides

-- Stamina: a thin bar on your other side, only while you're not fresh. Green, then yellow, then red when gassed.
local staminaBar, _, staminaFill = sideBar("Stamina", -1.9, 0.3, 2.6, 1)

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
-- The net swishes when a shot drops: every strand snaps down and springs back (just on this screen).
local strands = nil -- { part, its resting CFrame }
local function swish()
	if not strands then
		strands = {}
		for _, strand in workspace:WaitForChild("Hoop"):GetChildren() do
			if strand.Name == "Net" then
				table.insert(strands, { strand, strand.CFrame })
			end
		end
	end
	for _, s in strands do
		local strand, rest = s[1], s[2]
		strand.CFrame = rest + Vector3.new(0, -0.2 - 0.25 * math.max(Hoops.RIM_Y - rest.Position.Y, 0), 0) -- lower strands drop further
		TweenService:Create(strand, TweenInfo.new(0.7, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = rest }):Play()
	end
end
ReplicatedStorage:WaitForChild("Scored").OnClientEvent:Connect(function(scorerId, scorerName, points)
	if points == 0 then -- it went in, but the ball hadn't been taken back past the arc
		flash(popup, if scorerId == me.UserId then "NO BASKET: take it back!" else `{scorerName}: no basket`, Color3.fromRGB(255, 120, 90), 1.8)
	else
		flash(popup, if scorerId == me.UserId then `+{points}  BUCKET!` else `{scorerName} +{points}`, Color3.fromRGB(255, 205, 50), 1.5)
	end
	swish()
end)

-- Callouts: BLOCKED!, STOLEN! for everyone.
local calloutLabel = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(460, 46), Position = UDim2.fromScale(0.5, 0.36), BackgroundTransparency = 1, TextStrokeTransparency = 0.1, TextScaled = true, Font = Enum.Font.GothamBlack, Visible = false, Parent = gui })
ReplicatedStorage:WaitForChild("Callout").OnClientEvent:Connect(function(text)
	flash(calloutLabel, text, Color3.fromRGB(110, 200, 255), 1.4)
end)

-- Hint while the practice bot is around: how to practise defense.
local hint = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(520, 20), Position = UDim2.new(0.5, 0, 1, -16), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.25, TextStrokeTransparency = 0.6, TextScaled = true, Font = Enum.Font.GothamMedium, Text = "", Visible = false, Parent = gui })
-- After a steal or defensive rebound you have to take it back past the arc before you can score.
local takeBack = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(240, 26), Position = UDim2.new(0.5, 0, 0, 52), BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(255, 160, 60), TextStrokeTransparency = 0.3, TextScaled = true, Font = Enum.Font.GothamBlack, Text = "TAKE IT BACK", Visible = false, Parent = gui })
gui.Parent = me:WaitForChild("PlayerGui")
-- Touch controls (built at the bottom of this script), shown while playing by touch.
local touchGui = new("ScreenGui", { Name = "R2KTouch", ResetOnSpawn = false, DisplayOrder = 5, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, Enabled = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled, Parent = me.PlayerGui })

-- Ball shadow: a soft disc on the floor under the ball (reads the dribble's height and loose balls at a glance).
local shadow = new("Part", { Name = "BallShadow", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = Color3.new(0, 0, 0), Size = Vector3.new(0.02, 1.2, 1.2), Parent = workspace })

-- Player indicator: a ring on the floor under my player, orange with the ball, blue without (only I see it).
local indicator = new("Model", { Name = "Indicator" })
for i = 1, 24 do
	local a = i / 24 * math.pi * 2
	new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon, Transparency = 0.25, Size = Vector3.new(0.18, 0.04, 0.55), CFrame = CFrame.new(math.cos(a) * 2, 0, math.sin(a) * 2) * CFrame.Angles(0, -a, 0), Parent = indicator })
end
indicator.PrimaryPart = indicator:GetChildren()[1]
indicator.WorldPivot = CFrame.new()
indicator.Parent = workspace

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

local bots = workspace:WaitForChild("Bots")
local function bodyOf(id) -- the character of whoever has this id: a player, or the practice bot
	local player = id and Players:GetPlayerByUserId(id)
	if player then
		return player.Character
	end
	for _, model in bots:GetChildren() do
		if id and model:GetAttribute("Id") == id then
			return model
		end
	end
	return nil
end

local function iHaveBall()
	return ball:GetAttribute("Holder") == me.UserId
end

local function myStamina() -- 0..1, published by the server on my character
	return me.Character and me.Character:GetAttribute("Stamina") or 1
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
-- Hoops.animationId picks the id: the uploaded one, or in Studio the copy saved in the place (the server plays
-- them on the practice bot too). Roblox shows animations I play on my own character to everyone.

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
		local id = Hoops.animationId(name)
		if not animator or not id then
			return nil
		end
		tracks[name] = animator:LoadAnimation(new("Animation", { AnimationId = id }))
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
	local height = math.max(ball.Position.Y - Hoops.FLOOR_Y - Hoops.BALL_RADIUS, 0)
	shadow.Size = Vector3.new(0.02, 1.1 + height * 0.12, 1.1 + height * 0.12)
	shadow.Transparency = math.clamp(0.45 + height * 0.06, 0.45, 0.95)
	shadow.CFrame = CFrame.new(ball.Position.X, Hoops.FLOOR_Y + 0.16, ball.Position.Z) * CFrame.Angles(0, 0, math.rad(90)) -- lie flat, above the floor lines
	local myRootPart = myRoot()
	shotBar.Adornee, staminaBar.Adornee = myRootPart, myRootPart
	if shootStart then
		local held = os.clock() - shootStart
		fill.Size = UDim2.fromScale(1, math.min(held / METER_MAX, 1))
		fill.BackgroundColor3 = if Hoops.shotQuality(held) >= shotGreen then GREEN else Color3.new(1, 1, 1)
	end
	shotBar.Enabled = myRootPart ~= nil and (shootStart ~= nil or os.clock() < meterUntil)
	local stamina = myStamina()
	staminaBar.Enabled = myRootPart ~= nil and stamina < 1
	staminaFill.Size = UDim2.fromScale(1, stamina)
	staminaFill.BackgroundColor3 = if stamina > 0.5 then YELLOW:Lerp(GREEN, (stamina - 0.5) * 2) else RED:Lerp(YELLOW, stamina * 2)

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

	local holderId = ball:GetAttribute("Holder")
	local holderBody = bodyOf(holderId)
	local holderRoot = holderBody and holderBody:FindFirstChild("HumanoidRootPart")
	local bodies = {} -- every character on the court with its id: players and the practice bot
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(bodies, { player.Character, player.UserId })
		end
	end
	for _, model in bots:GetChildren() do
		table.insert(bodies, { model, model:GetAttribute("Id") })
	end
	for _, body in bodies do
		local char, id = body[1], body[2]
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local cf = root.CFrame

		-- Ball: the same function the server judges steals and blocks with, on the shared server clock.
		local pos, ballSide, hold
		if id == holderId then
			local mine = id == me.UserId
			local hand = (if mine then myHand else ball:GetAttribute("Hand")) or "Right"
			local move = if mine then myMove else ball:GetAttribute("Move")
			local moveHand = if mine then myMoveHand else ball:GetAttribute("MoveHand")
			local moveAt = (if mine then myMoveAt else ball:GetAttribute("MoveAt")) or 0
			pos, ballSide, hold = Hoops.ballSpot(cf, hand, move, moveHand, moveAt, now)
			ball.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(cf.RightVector, -os.clock() * 7) -- rolls as it's dribbled
		end

		-- Block: arms snap straight up, hold, and come down over BLOCK_TIME (the jump does the rest).
		local blockAt = (if id == me.UserId then myBlockAt else char:GetAttribute("BlockAt")) or 0
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
	hint.Visible = #bots:GetChildren() > 0 and not touchGui.Enabled -- touch has its own bot buttons
	hint.Text = `P / D-pad up: defense drill   ·   O / D-pad down: bot level ({bots:GetAttribute("Level") or "Medium"})`
	takeBack.Visible = iHaveBall() and ball:GetAttribute("MustClear") == true
	if not hum then
		return
	end
	indicator:PivotTo(CFrame.new(root.Position.X, Hoops.FLOOR_Y + 0.22, root.Position.Z)) -- above the lines and the ball shadow
	local ringColor = if iHaveBall() then Color3.fromRGB(255, 150, 40) else Color3.fromRGB(70, 160, 255)
	for _, piece in indicator:GetChildren() do
		piece.Color = ringColor
	end
	local stance = l2Held and not iHaveBall() and holderRoot ~= nil
	if stance ~= inStance then
		inStance = stance
		action:FireServer("stance", stance) -- intense D contests shots from further away
	end
	hum.WalkSpeed = if stance then Hoops.STANCE_SPEED elseif sprinting then Hoops.sprintSpeed(myStamina()) else Hoops.WALK_SPEED
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
local fovKick = 0 -- a quick zoom on dunks, easing back
RunService:BindToRenderStep("ParkCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	fovKick *= math.exp(-4 * dt)
	camera.FieldOfView = Hoops.CAMERA_FOV + fovKick
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
	play(Hoops.animationFor(name, hand))
	local d = Hoops.DASHES[name]
	if d then
		task.delay(d[1], function()
			local root = myRoot()
			if root then
				dash(Hoops.dashDirection(root.CFrame, d[2], hand), d[3], d[4])
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
-- (defense), X = shoot/steal, A = pass, Y = block. Keyboard: Shift sprint, Ctrl L2, moves on Y U I / H J K / N M ,.
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
local function shootOrSteal(_, state)
	if state == Enum.UserInputState.Begin then
		if iHaveBall() then
			local now = workspace:GetServerTimeNow()
			queued = nil -- the shot replaces any buffered move
			shootStart = os.clock()
			fill.Size = UDim2.fromScale(1, 0)
			shotGreen = Hoops.greenAt(myStamina()) -- the band: releases this close to perfect always go in
			local half = (1 - shotGreen) * Hoops.SHOT_WINDOW
			band.Position = UDim2.fromScale(-0.35, 1 - (Hoops.PERFECT_HOLD + half) / METER_MAX)
			band.Size = UDim2.fromScale(1.7, 2 * half / METER_MAX)
			feedback.Visible = false
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
				if finish ~= "Layup" then
					task.delay(startAt - now + Hoops.MOVES[finish].jumpAt + 0.25, function()
						fovKick = -7 -- the slam
					end)
				end
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
		meterUntil = os.clock() + 0.9 -- the fill stays where you let go, so you see how close you were
		if jumpShot then
			jumpShot:AdjustSpeed(1)
			jumpShot = nil
		end
		local quality = Hoops.shotQuality(held)
		local timing = if held < Hoops.PERFECT_HOLD then "Early" else "Late"
		local excellent = quality >= shotGreen
		fill.BackgroundColor3 = if excellent then GREEN else ORANGE
		flash(feedback, if excellent then "Excellent" else `{if quality >= 0.5 then "Slightly" else "Very"} {timing}`, if excellent then GREEN else ORANGE, 0.9)
	end
end
ContextActionService:BindActionAtPriority("ShootOrSteal", shootOrSteal, false, HIGH, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

local function pass(_, state)
	if state == Enum.UserInputState.Begin and iHaveBall() then
		queued = nil
		action:FireServer("pass")
	end
end
ContextActionService:BindActionAtPriority("Pass", pass, false, HIGH, Enum.KeyCode.R, Enum.KeyCode.ButtonA)

-- Block: jump with both arms up. Anyone can do it anywhere; it only matters near the ball handler.
local function block(_, state)
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
end
ContextActionService:BindActionAtPriority("Block", block, false, HIGH, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

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

-- The dribble pad: every move in one 3x3 block, laid out like the pro stick for the right hand (up = hesi, toward
-- the other hand = cross, down = stepback, center = spin). The keyboard has it under the right hand (Y U I / H J K /
-- N M ,) and touch draws it as buttons. { label, key, move, escape version (with Ctrl / L2) }, rows top to bottom.
local DRIBBLE_PAD = {
	{ "TWEEN", Enum.KeyCode.Y, "DoubleTween" }, { "HESI", Enum.KeyCode.U, "Hesitation" }, { "SIDE", Enum.KeyCode.I, "SideStep", "SideStepEscape" },
	{ "CROSS", Enum.KeyCode.H, "Crossover" }, { "SPIN", Enum.KeyCode.J, "SpinMove", "SpinEscape" }, { "IN-OUT", Enum.KeyCode.K, "InAndOut" },
	{ "BTL", Enum.KeyCode.N, "BetweenLegs" }, { "STEP", Enum.KeyCode.M, "Stepback", "StepbackEscape" }, { "BEHIND", Enum.KeyCode.Comma, "BehindBack" },
}
for _, m in DRIBBLE_PAD do
	ContextActionService:BindAction("Key" .. m[3], function(_, state)
		if state == Enum.UserInputState.Begin then
			tryMove(if l2Held and m[4] then m[4] else m[3])
		end
	end, false, m[2])
end

-- Defense drill: the practice bot gets the ball at the top of the key (P, or D-pad up).
ContextActionService:BindAction("Drill", function(_, state)
	if state == Enum.UserInputState.Begin then
		action:FireServer("drill")
	end
end, false, Enum.KeyCode.P, Enum.KeyCode.DPadUp)

ContextActionService:BindAction("Level", function(_, state)
	if state == Enum.UserInputState.Begin then
		action:FireServer("level")
	end
end, false, Enum.KeyCode.O, Enum.KeyCode.DPadDown)


-- Touch (iPhone and iPad) -------------------------------------------------------------------------
-- Roblox's thumbstick moves you (left side). Everything else is on the right, 2K style: the big button shoots
-- (steals on defense), the one beside it passes (blocks on defense), TURBO and L2 are toggles, and every dribble
-- move sits together in one pad. The pad is laid out like the pro stick for the right hand: up = hesi, toward the
-- other hand = cross, down = stepback, center = spin. With L2 on, the escape moves light up orange.
local DARK, LIT = Color3.fromRGB(20, 20, 26), Color3.fromRGB(255, 150, 40)
local controls = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(400, 200), BackgroundTransparency = 1, Parent = touchGui })
local controlScale = new("UIScale", { Parent = controls })
local function fitToScreen() -- laid out for an iPhone's short side (~360px usable); bigger on an iPad
	local size = touchGui.AbsoluteSize
	controlScale.Scale = math.clamp(math.min(size.X, size.Y) / 360, 0.9, 1.4)
end
touchGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)
fitToScreen()

local lifts = {} -- [touch] = what to do when that finger lifts (even if it slid off the button)
UserInputService.InputEnded:Connect(function(input)
	local lift = lifts[input]
	if lift then
		lifts[input] = nil
		lift()
	end
end)

-- A touch button, placed by its center from the bottom-right of its parent. down() runs the moment a finger lands.
local function touchButton(parent, text, w, h, x, y, down, up)
	local b = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, x, 1, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = DARK, BackgroundTransparency = 0.3, AutoButtonColor = false, Text = text, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.GothamBlack, Parent = parent })
	new("UICorner", { CornerRadius = UDim.new(if w == h then 0.5 else 0.3, 0), Parent = b })
	new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.new(1, 1, 1), Transparency = 0.55, Thickness = 2, Parent = b })
	new("UIPadding", { PaddingLeft = UDim.new(0.1, 0), PaddingRight = UDim.new(0.1, 0), PaddingTop = UDim.new(0.28, 0), PaddingBottom = UDim.new(0.28, 0), Parent = b })
	local pressed = new("UIScale", { Parent = b })
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and input.UserInputState == Enum.UserInputState.Begin then
			pressed.Scale = 0.9
			down()
			lifts[input] = function()
				pressed.Scale = 1
				if up then
					up()
				end
			end
		end
	end)
	return b
end

local shootButton = touchButton(controls, "SHOOT", 92, 92, -62, -62, function()
	shootOrSteal(nil, Enum.UserInputState.Begin)
end, function()
	shootOrSteal(nil, Enum.UserInputState.End)
end)
local passButton = touchButton(controls, "PASS", 64, 64, -160, -44, function()
	pass(nil, Enum.UserInputState.Begin) -- each one only acts on its side of the ball
	block(nil, Enum.UserInputState.Begin)
end)
local turboButton = touchButton(controls, "TURBO", 58, 58, -52, -160, function()
	sprinting = not sprinting
end)
local l2Button = touchButton(controls, "L2", 58, 58, -140, -138, function()
	l2Held = not l2Held
end)

local dribblePad = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = controls })
local escapeButtons = {}
for i, m in DRIBBLE_PAD do
	local col, row = (i - 1) % 3, (i - 1) // 3
	local b = touchButton(dribblePad, m[1], 58, 46, -363 + 64 * col, -143 + 52 * row, function()
		tryMove(if l2Held and m[4] then m[4] else m[3])
	end)
	if m[4] then
		table.insert(escapeButtons, b)
	end
end

-- Practice bot buttons (the hint's P and O keys), top left.
local botButtons = new("Frame", { Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(240, 36), BackgroundTransparency = 1, Parent = touchGui })
touchButton(botButtons, "DRILL", 96, 36, -192, -18, function()
	action:FireServer("drill")
end)
local levelButton = touchButton(botButtons, "BOT: MEDIUM", 132, 36, -66, -18, function()
	action:FireServer("level")
end)

-- Buttons follow the play: offense or defense labels, toggles lit, the dribble pad only with the ball.
local touchHadBall = false
RunService.RenderStepped:Connect(function()
	if not touchGui.Enabled then
		return
	end
	local hasBall = iHaveBall()
	if hasBall ~= touchHadBall then -- possession changed: turbo and L2 start off
		touchHadBall = hasBall
		sprinting, l2Held = false, false
	end
	shootButton.Text = if hasBall then "SHOOT" else "STEAL"
	passButton.Text = if hasBall then "PASS" else "BLOCK"
	l2Button.Text = if hasBall then "ESCAPE" else "LOCK D"
	turboButton.BackgroundColor3 = if sprinting then LIT else DARK
	l2Button.BackgroundColor3 = if l2Held then LIT else DARK
	for _, b in escapeButtons do
		b.BackgroundColor3 = if l2Held then LIT else DARK
	end
	dribblePad.Visible = hasBall
	botButtons.Visible = #bots:GetChildren() > 0
	levelButton.Text = `BOT: {string.upper(bots:GetAttribute("Level") or "Medium")}`
end)

-- Show touch controls while playing by touch; a keyboard or controller hides them (an iPad with a keyboard, say).
UserInputService.LastInputTypeChanged:Connect(function(kind)
	if kind == Enum.UserInputType.Touch then
		touchGui.Enabled = true
	elseif kind == Enum.UserInputType.Keyboard or kind.Name:find("Gamepad") then
		touchGui.Enabled = false
	end
end)

-- Roblox's jump button sits where these buttons go, and jumping is Block's job here.
-- shortcut: reaches into Roblox's TouchGui by name; if Roblox renames it the jump button just shows again
if UserInputService.TouchEnabled then
	task.spawn(function()
		local touchControls = me.PlayerGui:WaitForChild("TouchGui", 30)
		local jump = touchControls and touchControls:WaitForChild("TouchControlFrame", 5)
		jump = jump and jump:WaitForChild("JumpButton", 5)
		if jump then
			jump.Visible = false
			jump:GetPropertyChangedSignal("Visible"):Connect(function()
				jump.Visible = false
			end)
		end
	end)
end
