-- Client: input, the shot meter, and animating the ball handler every frame.
-- Every client draws the ball and bends the holder's arms itself, from the server's "Holder", "Hand"
-- and "Shooting" attributes, so nothing animated waits on the network. Your own crossovers and
-- shot gathers start instantly; the server hears about them after.
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
gui.Parent = me:WaitForChild("PlayerGui")

-- Arms: Roblox's IK solver pulls each hand to a target. Targets are local world-space attachments.
-- shortcut: procedural arms look stiff for flashy moves; play keyframed animations for spins/step-backs later
local targets, poles, iks = {}, {}, {}
for side in SIDE do
	targets[side] = new("Attachment", { Name = side .. "HandTarget", Parent = workspace.Terrain })
	poles[side] = new("Attachment", { Name = side .. "ElbowPole", Parent = workspace.Terrain })
end

-- Fresh IKControls per possession: the old holder's character may already be destroyed.
local function attachArms(char)
	for _, ik in iks do
		ik:Destroy()
	end
	table.clear(iks)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	for side in SIDE do
		local upperArm, hand = char:FindFirstChild(side .. "UpperArm"), char:FindFirstChild(side .. "Hand")
		if upperArm and hand then -- R15 only; an R6 holder still dribbles, just without arm motion
			iks[side] = new("IKControl", { Type = Enum.IKControlType.Position, ChainRoot = upperArm, EndEffector = hand, Target = targets[side], Pole = poles[side], Weight = 0, Parent = hum })
		end
	end
end

local myHand = "Right" -- my predicted hand while I hold the ball
local myGather = false -- I started a shot; hold the gather until the server takes the ball
local shootStart = nil
local lastHolder, lastHand, fromHand, crossAt, gatherAt = nil, "Right", "Right", 0, nil

local function iHaveBall()
	return ball:GetAttribute("Holder") == me.UserId
end

ball:GetAttributeChangedSignal("Holder"):Connect(function()
	myHand, myGather = "Right", false -- the server starts every possession in the right hand
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if shootStart then
		fill.Size = UDim2.fromScale(1, math.min((now - shootStart) / METER_MAX, 1))
	end

	local id = ball:GetAttribute("Holder")
	local holder = id and Players:GetPlayerByUserId(id)
	local char = holder and holder.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		if lastHolder then
			attachArms(nil)
		end
		lastHolder = nil
		return
	end
	if holder ~= lastHolder then -- new possession: start dribbling from the right hand
		lastHolder, lastHand, crossAt, gatherAt = holder, "Right", now - Hoops.CROSS_TIME, nil
		attachArms(char)
	end
	local hand = holder == me and myHand or ball:GetAttribute("Hand") or "Right"
	if hand ~= lastHand then -- crossover: mine starts instantly, others' when the server says so
		fromHand, lastHand, crossAt = lastHand, hand, now
	end
	local gathering = if holder == me then myGather else ball:GetAttribute("Shooting") == true
	if gathering ~= (gatherAt ~= nil) then
		gatherAt = if gathering then now else nil
	end

	-- Ball: bounce beside the body, cross between sides, rise into the shot.
	local cf = root.CFrame
	local function bounceTop(side)
		return cf * Vector3.new(SIDE[side] * Hoops.DRIBBLE_SIDE, Hoops.DRIBBLE_TOP, -Hoops.DRIBBLE_FORWARD)
	end
	local a = (now - crossAt) / Hoops.CROSS_TIME
	local pos, s -- s: 0 = top of the bounce, 1 = on the floor
	if a < 1 then -- crossover: one low bounce to the other side
		pos, s = bounceTop(fromHand):Lerp(bounceTop(hand), a), math.sin(math.pi * a)
	else -- |cos| snaps the ball off the floor and lets it float near the hand
		pos, s = bounceTop(hand), 1 - math.abs(math.cos(math.pi * Hoops.DRIBBLE_HZ * (now - crossAt - Hoops.CROSS_TIME)))
	end
	pos = pos:Lerp(Vector3.new(pos.X, Hoops.FLOOR_Y + Hoops.BALL_RADIUS, pos.Z), s)
	local g = if gatherAt then math.min((now - gatherAt) / Hoops.GATHER_TIME, 1) else 0
	g = g * g * (3 - 2 * g) -- ease in and out
	pos = pos:Lerp(cf * Vector3.new(0, Hoops.GATHER_HEIGHT, -Hoops.GATHER_FORWARD), g)
	ball.CFrame = CFrame.new(pos)

	-- Hands: the dribble hand rides the top of each bounce; both hold the ball on a gather.
	local handLow = root.Position.Y + Hoops.HAND_LOW
	for side, x in SIDE do
		local dribble = if a < 1 then (if side == hand then a else 1 - a) else (if side == hand then 1 else 0)
		local onTop = Vector3.new(pos.X, math.max(pos.Y + Hoops.BALL_RADIUS, handLow), pos.Z)
		targets[side].WorldPosition = onTop:Lerp(pos + cf.RightVector * x * (Hoops.BALL_RADIUS + 0.2), g)
		poles[side].WorldPosition = cf * Vector3.new(x * 3, -1, 1.5) -- elbows bend out and back
		if iks[side] then
			iks[side].Weight = math.max(dribble, g)
		end
	end
end)

-- Same button shoots on offense and steals on defense, like 2K.
ContextActionService:BindAction("ShootOrSteal", function(_, state)
	if state == Enum.UserInputState.Begin then
		if iHaveBall() then
			shootStart, myGather = os.clock(), true
			fill.Size = UDim2.fromScale(1, 0)
			meter.Visible = true
			action:FireServer("shootStart")
		else
			action:FireServer("steal")
		end
	elseif shootStart and (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) then
		action:FireServer("shoot", os.clock() - shootStart)
		shootStart = nil
		meter.Visible = false
	end
end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

ContextActionService:BindAction("Crossover", function(_, state)
	if state == Enum.UserInputState.Begin and iHaveBall() and os.clock() - crossAt >= Hoops.CROSS_TIME then
		myHand = myHand == "Right" and "Left" or "Right"
		action:FireServer("cross", myHand)
	end
end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)

ContextActionService:SetTitle("ShootOrSteal", "Shoot")
ContextActionService:SetTitle("Crossover", "Cross")
