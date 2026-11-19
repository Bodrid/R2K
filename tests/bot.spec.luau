-- Run: lune run tests/bot.spec   (the practice bot's brain: decisions, then simulated possessions)
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local Hoops = require("../src/shared/Hoops")
local Brain = require("../src/server/Bot")(Hoops, Vector3, CFrame)

local Y = Hoops.FLOOR_Y + Hoops.RIG_HIP_HEIGHT + 1 -- standing root height
local RIM = Vector3.new(0, Hoops.RIM_Y, Hoops.RIM_Z)
local RIM_FLOOR = Vector3.new(RIM.X, Y, RIM.Z)
local CHECK = Vector3.new(0, Y, RIM.Z + Hoops.THREE_DIST + 4)
local ZERO = Vector3.new(0, 0, 0)
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function still(pos)
	return { pos = pos, vel = ZERO }
end
local function seeded(seed)
	math.randomseed(seed)
	return math.random
end

-- Decisions --------------------------------------------------------------------------------------
do -- at the rim it finishes
	local out = Brain.offense({ now = 0, me = still(RIM_FLOOR + Vector3.new(0, 0, 3)), opp = still(CHECK), hand = "Right", busy = false, possessionAge = 1, mind = {}, rng = seeded(1) })
	assert(out.act and out.act.kind == "shoot" and (out.act.finish == "Dunk" or out.act.finish == "DunkTwoHand"), "dunks at the rim")
	local close = RIM_FLOOR + Vector3.new(0, 0, 9)
	out = Brain.offense({ now = 0, me = still(close), opp = still(CHECK), hand = "Right", busy = false, possessionAge = 1, mind = {}, rng = seeded(2) })
	assert(not out.act and out.dir:Dot(flat(RIM_FLOOR - close).Unit) > 0.99, "an open lane: keeps attacking the rim")
	out = Brain.offense({ now = 0, me = still(close), opp = still(close + Vector3.new(0, 0, -3.6)), hand = "Right", busy = false, possessionAge = 1, mind = {}, rng = seeded(2) })
	assert(out.act and out.act.finish == "Layup", "lane shut by a sagging defender: lays it up over them")
end
do -- a defender shading the ball hand gets crossed away from
	local switches = 0
	for seed = 1, 200 do
		local me = CHECK + Vector3.new(0, 0, -6)
		local out = Brain.offense({ now = 0, me = still(me), opp = still(me + Vector3.new(1.2, 0, -2.6)), hand = "Right", busy = false, possessionAge = 1, mind = {}, rng = seeded(seed) })
		local name = out.act and out.act.kind == "move" and out.act.name
		if name == "Crossover" or name == "BetweenLegs" or name == "BehindBack" or name == "Stepback" or name == "StepbackEscape" then
			switches += 1
		end
		assert(not name or Hoops.MOVES[name], "only real moves")
	end
	assert(switches > 60, `switches hands or steps back when shaded ({switches}/200)`)
end
do -- open from deep: pulls up within a few thinks
	local mind, shot = {}, false
	for i = 1, 20 do
		local out = Brain.offense({ now = i * 0.1, me = still(CHECK + Vector3.new(0, 0, -3)), opp = still(CHECK + Vector3.new(0, 0, 12)), hand = "Right", busy = false, possessionAge = i * 0.1, mind = mind, rng = seeded(i) })
		shot = shot or (out.act and out.act.kind == "shoot")
	end
	assert(shot, "takes the open three")
end
do -- the shot clock makes it shoot
	local out = Brain.offense({ now = 0, me = still(CHECK), opp = still(CHECK + Vector3.new(0, 0, -2)), hand = "Right", busy = false, possessionAge = 20, mind = {}, rng = seeded(3) })
	assert(out.act and out.act.kind == "shoot", "shoots when its clock runs out")
end
do -- defense: stands between the ball and the rim, never swipes at a ball it can't reach
	local handler = CHECK
	local spot = handler + flat(RIM_FLOOR - handler).Unit * 3.2
	local out = Brain.defense({ now = 0, me = still(spot), opp = still(handler), canReach = false, shooting = false, mind = {}, rng = seeded(4) })
	assert(out.dir.Magnitude < 1e-6 and not out.act, "already in position: holds")
	out = Brain.defense({ now = 0, me = still(handler + Vector3.new(6, 0, 0)), opp = still(handler), canReach = false, shooting = false, mind = {}, rng = seeded(5) })
	assert(out.dir:Dot(flat(spot - (handler + Vector3.new(6, 0, 0))).Unit) > 0.99, "out of position: goes straight to the spot")
	for seed = 1, 100 do
		local o = Brain.defense({ now = seed, me = still(spot), opp = still(handler), canReach = false, shooting = false, mind = {}, rng = seeded(seed) })
		assert(not o.act, "no swipes at a ball out of reach")
	end
end
do -- defense: jumps at a layup's takeoff, not before
	local mind = {}
	local me = RIM_FLOOR + Vector3.new(0, 0, 6)
	local opp = me + Vector3.new(0, 0, 2.5)
	local early = Brain.defense({ now = 0, me = still(me), opp = still(opp), shooting = true, shotKind = "Layup", shotAge = 0.2, mind = mind, rng = seeded(6) })
	assert(not early.act, "doesn't jump before the takeoff")
	local blocks = 0
	for seed = 1, 100 do
		local m = {}
		local out = Brain.defense({ now = 0, me = still(me), opp = still(opp), shooting = true, shotKind = "Layup", shotAge = 0.55, mind = m, rng = seeded(seed) })
		blocks += if out.act and out.act.kind == "block" then 1 else 0
	end
	assert(blocks > 50, `jumps at the takeoff most of the time ({blocks}/100)`)
end

-- Simulations ------------------------------------------------------------------------------------
local DT, THINK = 1 / 30, 0.1
local SIDE = { Right = 1, Left = -1 }
local DASH = { Stepback = { 0.12, -1, 18, 0.3 }, StepbackEscape = { 0.1, -1, 20, 0.55 }, SpinMove = { 0.05, 1, 16, 0.45 }, SpinEscape = { 0.05, 1, 20, 0.45 } }
local function inFloor(p)
	return math.abs(p.X) <= 45 and p.Z >= -45 and p.Z <= 35
end
local function towardRim(p)
	return flat(RIM_FLOOR - p).Unit
end
local function step(pos, dir, speed)
	return pos + dir * speed * DT
end
local function separate(a, b) -- bodies can't overlap: push `a` out of `b`
	local d = flat(a - b)
	return if d.Magnitude < 1.6 and d.Magnitude > 1e-6 then b + d.Unit * 1.6 else a
end

-- Bot on offense vs a scripted defender who reacts 0.25s late and sometimes bites on a move.
local function offenseTrial(seed)
	local rng = seeded(seed)
	local bot, def = CHECK, CHECK + Vector3.new(0, 0, -4)
	local hand, mind = "Right", {}
	local busyUntil, dash, frozenUntil = 0, nil, 0
	local queue = {}
	local history = {}
	local used = {}
	local inBounds = true
	local t, nextThink = 0, 0
	while t < 14 do
		if t >= nextThink then
			nextThink += THINK
			local out = Brain.offense({ now = t, me = still(bot), opp = still(def), hand = hand, busy = t < busyUntil, possessionAge = t, mind = mind, rng = rng })
			mind.dir = out.dir
			mind.speed = if out.sprint then Hoops.SPRINT_SPEED else Hoops.WALK_SPEED
			if out.act and out.act.kind == "shoot" then
				local gap = flat(def - bot).Magnitude
				return { t = t, dist = flat(RIM_FLOOR - bot).Magnitude, gap = gap, finish = out.act.finish, hold = out.act.hold, used = used, inBounds = inBounds, clock = t > Brain.SKILL.shotClock }
			elseif out.act and out.act.kind == "move" then
				queue = { out.act.name, out.act.chain }
			end
		end
		if #queue > 0 and t >= busyUntil then
			local name = table.remove(queue, 1)
			if name == "SpinMove" and hand == "Left" then
				name = "SpinEscape"
			end
			used[name] = true
			local move = Hoops.MOVES[name]
			busyUntil = t + move.duration
			if move.switch then
				hand = if hand == "Right" then "Left" else "Right"
			end
			local d = DASH[name]
			if d then
				dash = { at = t + d[1], dir = towardRim(bot) * d[2], speed = d[3], untilT = t + d[1] + d[4] }
			end
			if rng() < 0.35 then -- the defender bites
				frozenUntil = t + 0.3
			end
		end
		-- move the bot
		if dash and t >= dash.at and t < dash.untilT then
			bot = step(bot, dash.dir, dash.speed)
		elseif t >= busyUntil or not dash then
			bot = step(bot, mind.dir or ZERO, mind.speed or 0)
		end
		bot = separate(bot, def)
		inBounds = inBounds and inFloor(bot)
		-- the defender: between the bot (as it saw it 0.25s ago) and the rim
		table.insert(history, { t = t, pos = bot })
		while #history > 1 and history[2].t <= t - 0.25 do
			table.remove(history, 1)
		end
		if t >= frozenUntil then
			local seen = history[1].pos
			local spot = seen + towardRim(seen) * 3.2
			local toSpot = flat(spot - def)
			if toSpot.Magnitude > 0.3 then
				def = step(def, toSpot.Unit, if toSpot.Magnitude > 6 then Hoops.SPRINT_SPEED else Hoops.WALK_SPEED)
			end
		end
		def = separate(def, bot)
		t += DT
	end
	return { t = math.huge, used = used, inBounds = inBounds }
end

do
	local trials, shots, good, deep, clock, total = 300, 0, 0, 0, 0, 0
	local used = {}
	for seed = 1, trials do
		local r = offenseTrial(seed)
		assert(r.inBounds, `seed {seed}: the bot left the floor`)
		for name in r.used do
			used[name] = true
		end
		if r.t < math.huge then
			shots += 1
			total += r.t
			clock += if r.clock then 1 else 0
			if r.dist <= Hoops.LAYUP_RANGE or r.gap >= 4 then
				good += 1
			end
			if r.dist > Hoops.THREE_DIST + 4 and not r.clock then
				deep += 1
			end
			assert(r.hold >= 0.3 and r.hold <= Hoops.PERFECT_HOLD + Hoops.SHOT_WINDOW, "release timing in range")
		end
	end
	local kinds = {}
	for seed = 1, trials do
		local r = offenseTrial(seed)
		local key = r.finish .. (if r.gap < Hoops.CONTEST_RANGE then " contested" else " open")
		kinds[key] = (kinds[key] or 0) + 1
	end
	local parts = {}
	for k, n in kinds do
		table.insert(parts, `{k} {n}`)
	end
	table.sort(parts)
	print("offense shot mix: " .. table.concat(parts, ", "))
	local variety = 0
	for _ in used do
		variety += 1
	end
	print(string.format("offense: %d/%d possessions shot, avg %.1fs, %d%% good looks, %d deep heaves, %d shot-clock shots, %d different moves",
		shots, trials, total / shots, math.floor(100 * good / shots), deep, clock, variety))
	assert(shots == trials, "every possession ends in a shot")
	assert(total / shots < 8, "it doesn't dawdle")
	assert(good / shots >= 0.85, "good looks: at the rim or open")
	assert(deep == 0, "no heaves from way out unless the clock runs out")
	assert(clock / shots < 0.15, "rarely bails out on the shot clock")
	assert(variety >= 6, "uses a range of moves")
end

-- Bot on defense vs a scripted driver who jukes toward the rim and pulls up or finishes.
local function defenseTrial(seed, speed)
	local rng = seeded(seed)
	local driver, bot = CHECK, CHECK + Vector3.new(0, 0, -4)
	local mind, history = {}, {}
	local jukeAt, side = 0, 1
	local between, counted = 0, 0
	local badSwipes, swipes = 0, 0
	local t, nextThink = 0, 0
	local out = { dir = ZERO }
	while t < 8 do
		local toRim = flat(RIM_FLOOR - driver)
		if toRim.Magnitude < 9 then
			break
		end
		if t >= jukeAt then
			jukeAt = t + 0.5 + rng() * 0.6
			side = if rng() < 0.5 then -1 else 1
		end
		local dir = (toRim.Unit + Brain.rightOf(toRim.Unit) * side * 0.9).Unit
		driver = step(driver, dir, speed)
		driver = Brain.inCourt(driver, 1)
		table.insert(history, { t = t, pos = driver, vel = dir * speed })
		while #history > 1 and history[2].t <= t - Brain.SKILL.reaction do
			table.remove(history, 1)
		end
		if t >= nextThink then
			nextThink += THINK
			local driverCF = CFrame.lookAt(driver, driver + toRim)
			local ballAt = Hoops.ballSpot(driverCF, "Right", nil, nil, 0, t)
			local botCF = CFrame.lookAt(bot, bot + flat(driver - bot) + Vector3.new(0, 0, 1e-3))
			local canReach = flat(driver - bot).Magnitude <= Hoops.STEAL_RANGE and Hoops.reaches(botCF, ballAt)
			out = Brain.defense({ now = t, me = still(bot), opp = { pos = history[1].pos, vel = history[1].vel }, canReach = canReach, shooting = false, mind = mind, rng = rng })
			if out.act and out.act.kind == "steal" then
				swipes += 1
				badSwipes += if canReach then 0 else 1
			end
		end
		local botSpeed = if out.stance then Hoops.STANCE_SPEED elseif out.sprint then Hoops.SPRINT_SPEED else Hoops.WALK_SPEED
		bot = separate(step(bot, out.dir, botSpeed), driver)
		-- in position: between the driver and the rim, within a few studs
		local toBot = flat(bot - driver)
		counted += 1
		if toBot.Magnitude < 7 and toBot.Magnitude > 0 and toBot.Unit:Dot(toRim.Unit) > math.cos(math.rad(50)) then
			between += 1
		end
		t += DT
	end
	return between / math.max(counted, 1), swipes, badSwipes
end

do
	for _, case in { { Hoops.WALK_SPEED, 0.75, "jogging" }, { Hoops.SPRINT_SPEED, 0.45, "sprinting" } } do
		local sum, swipes, bad = 0, 0, 0
		for seed = 1, 200 do
			local frac, s, b = defenseTrial(seed, case[1])
			sum += frac
			swipes += s
			bad += b
		end
		print(string.format("defense vs a %s driver: in position %d%% of the time, %d swipes (%d at a ball out of reach)", case[3], math.floor(100 * sum / 200), swipes, bad))
		assert(sum / 200 >= case[2], `stays in front of a {case[3]} driver`)
		assert(bad == 0, "never swipes at a ball out of reach")
	end
end

-- Loose ball: it runs the ball down.
do
	local bot = CHECK
	local ball, vel = RIM_FLOOR + Vector3.new(8, 0, 6), Vector3.new(4, 0, 3)
	local t = 0
	while flat(ball - bot).Magnitude > Hoops.PICKUP_RANGE and t < 5 do
		local out = Brain.chase({ me = still(bot), ballPos = ball, ballVel = vel })
		bot = step(bot, out.dir, if out.sprint then Hoops.SPRINT_SPEED else Hoops.WALK_SPEED)
		ball += vel * DT
		vel *= 0.98
		t += DT
	end
	assert(t < 3, "runs a loose ball down quickly")
end

print("bot.spec: all passed")
