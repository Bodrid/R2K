-- Client: input, the shot meter, and drawing the ball in the holder's hand every frame.
-- Every client draws the ball itself from the server's "Holder"/"Hand" attributes, so it always
-- sits in the hand you see. Your own crossovers apply instantly and the server hears about them after.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hoops = require(ReplicatedStorage:WaitForChild("Hoops"))
local action = ReplicatedStorage:WaitForChild("Action")
local ball = workspace:WaitForChild("Basketball"):WaitForChild("Ball")
local me = Players.LocalPlayer

local METER_MAX = Hoops.PERFECT_HOLD + Hoops.SHOT_WINDOW

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

local myHand = "Right" -- my predicted hand while I hold the ball
local shootStart = nil
local lastHolder, lastHand, fromHand, crossAt = nil, "Right", "Right", 0

local function iHaveBall()
	return ball:GetAttribute("Holder") == me.UserId
end

local function handPart(char, side)
	return char:FindFirstChild(side .. "Hand") or char:FindFirstChild(side .. " Arm") -- R15 or R6
end

local function belowHand(part)
	return part.Position - Vector3.yAxis * (part.Size.Y / 2 + Hoops.BALL_RADIUS)
end

ball:GetAttributeChangedSignal("Holder"):Connect(function()
	myHand = "Right" -- the server starts every possession in the right hand
end)

-- shortcut: the bounce is code, not animation; once there's a dribble animation, keyframe the ball in it (Motor6D to the hand)
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if shootStart then
		fill.Size = UDim2.fromScale(1, math.min((now - shootStart) / METER_MAX, 1))
	end

	local id = ball:GetAttribute("Holder")
	local holder = id and Players:GetPlayerByUserId(id)
	local char = holder and holder.Character
	if not char then
		lastHolder = nil
		return
	end
	if holder ~= lastHolder then -- new possession: start dribbling from the right hand
		lastHolder, lastHand, crossAt = holder, "Right", now - Hoops.CROSS_TIME
	end
	local hand = holder == me and myHand or ball:GetAttribute("Hand") or "Right"
	if hand ~= lastHand then -- crossover: mine starts instantly, others' when the server says so
		fromHand, lastHand, crossAt = lastHand, hand, now
	end

	local to = handPart(char, hand)
	if not to then
		return
	end
	local a = (now - crossAt) / Hoops.CROSS_TIME
	local top, s -- s: 0 = in the hand, 1 = on the floor
	if a < 1 then -- ball crosses to the other hand with one bounce
		top = belowHand(handPart(char, fromHand) or to):Lerp(belowHand(to), a)
		s = math.sin(math.pi * a)
	else -- |cos| snaps the ball off the floor and lets it float near the hand
		top = belowHand(to)
		s = 1 - math.abs(math.cos(math.pi * Hoops.DRIBBLE_HZ * (now - crossAt - Hoops.CROSS_TIME)))
	end
	ball.CFrame = CFrame.new(top:Lerp(Vector3.new(top.X, Hoops.FLOOR_Y + Hoops.BALL_RADIUS, top.Z), s))
end)

-- Same button shoots on offense and steals on defense, like 2K.
ContextActionService:BindAction("ShootOrSteal", function(_, state)
	if state == Enum.UserInputState.Begin then
		if iHaveBall() then
			shootStart = os.clock()
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
