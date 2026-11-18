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
gui.Parent = me:WaitForChild("PlayerGui")

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
local myHand, myFromHand, myCrossAt, myGatherAt = "Right", "Right", 0, nil
local myBlockAt = 0
local shootStart = nil -- os.clock() when I started holding shoot (for the meter)

local function iHaveBall()
	return ball:GetAttribute("Holder") == me.UserId
end

ball:GetAttributeChangedSignal("Holder"):Connect(function()
	-- The server sets these before Holder, so a new possession starts in sync with it.
	-- Clearing myGatherAt here also holds a released shot's gather until the server takes the ball.
	myHand, myFromHand = ball:GetAttribute("Hand") or "Right", ball:GetAttribute("FromHand") or "Right"
	myCrossAt, myGatherAt = ball:GetAttribute("CrossAt") or 0, nil
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
		local pos, a, g, hand
		if player == holder then
			local mine = player == me
			hand = (if mine then myHand else ball:GetAttribute("Hand")) or "Right"
			local fromHand = (if mine then myFromHand else ball:GetAttribute("FromHand")) or hand
			local crossAt = (if mine then myCrossAt else ball:GetAttribute("CrossAt")) or 0
			local gatherAt = if mine then myGatherAt else ball:GetAttribute("GatherAt")
			pos, a, g = Hoops.ballSpot(cf, hand, fromHand, crossAt, gatherAt, now)
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
				else -- the dribble hand rides the top of each bounce; both hold the ball on a gather
					local dribble = if a < 1 then (if side == hand then a else 1 - a) else (if side == hand then 1 else 0)
					local onTop = Vector3.new(pos.X, math.max(pos.Y + Hoops.BALL_RADIUS, handLow), pos.Z)
					arm.target.WorldPosition = onTop:Lerp(pos + cf.RightVector * x * (Hoops.BALL_RADIUS + 0.2), g)
					arm.pole.WorldPosition = cf * Vector3.new(x * 3, -1, 1.5) -- elbows bend out and back
					weight = math.max(dribble, g)
				end
				if arm.ik then
					arm.ik.Weight = weight
				end
			end
		end
	end
end)

-- Same button shoots on offense and steals on defense, like 2K.
ContextActionService:BindAction("ShootOrSteal", function(_, state)
	if state == Enum.UserInputState.Begin then
		if iHaveBall() then
			shootStart, myGatherAt = os.clock(), workspace:GetServerTimeNow()
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
	local now = workspace:GetServerTimeNow()
	if state == Enum.UserInputState.Begin and iHaveBall() and now - myCrossAt >= Hoops.CROSS_TIME then
		myFromHand, myHand, myCrossAt = myHand, (if myHand == "Right" then "Left" else "Right"), now
		action:FireServer("cross", myHand, now) -- send the start time so the server's ball matches mine
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
		action:FireServer("block")
	end
end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

ContextActionService:SetTitle("ShootOrSteal", "Shoot")
ContextActionService:SetTitle("Crossover", "Cross")
ContextActionService:SetTitle("Pass", "Pass")
ContextActionService:SetTitle("Block", "Block")
