-- The practice bot's brain: pure decisions from positions (no instances), so tests/bot.spec.luau can play
-- whole possessions against it. The server feeds it the court ~10 times a second and carries its decisions
-- out through the same rules a player's buttons go through, so it can't cheat, only choose.
-- Usage: local Brain = require(Bot)(Hoops, Vector3, CFrame)
return function(Hoops, Vector3, CFrame)
	local Brain = {}

	-- How good it is, by level. Medium: beatable, but it punishes lazy defense and lazy offense.
	--   reaction: it sees the ball handler this many seconds late (defense)
	--   shotSpread: how far its releases land from perfect, typically (seconds)
	--   stealRate: chance it swipes when the ball's in reach (at most every 0.4s)
	--   blockRate: chance it jumps at a shot it's right on
	--   moveRate / chainRate: chance per think it breaks out a dribble move under pressure / chains a second
	--   openShot: space (studs) it wants before pulling up; shotClock: seconds before it just shoots
	--   biteRate: chance it bites on your dribble move (freezes a moment, like getting your ankles taken)
	Brain.LEVELS = {
		Easy = { reaction = 0.32, shotSpread = 0.11, stealRate = 0.15, blockRate = 0.4, moveRate = 0.35, chainRate = 0.2, openShot = 6, shotClock = 9, biteRate = 0.5 },
		Medium = { reaction = 0.2, shotSpread = 0.07, stealRate = 0.3, blockRate = 0.7, moveRate = 0.55, chainRate = 0.4, openShot = 5, shotClock = 9, biteRate = 0.3 },
		Hard = { reaction = 0.12, shotSpread = 0.045, stealRate = 0.45, blockRate = 0.85, moveRate = 0.7, chainRate = 0.6, openShot = 4, shotClock = 9, biteRate = 0.15 },
	}
	Brain.SKILL = {}
	local SKILL = Brain.SKILL
	function Brain.setLevel(name)
		for k, v in Brain.LEVELS[name] do
			SKILL[k] = v
		end
		Brain.level = name
	end
	Brain.setLevel("Medium")

	local RIM = Vector3.new(0, Hoops.RIM_Y, Hoops.RIM_Z)
	local ZERO = Vector3.new(0, 0, 0)

	local function flat(v)
		return Vector3.new(v.X, 0, v.Z)
	end
	local function unit(v)
		local m = v.Magnitude
		return if m > 1e-6 then v / m else ZERO
	end
	local function rightOf(forward) -- the right-hand side of someone facing `forward` (flat, unit)
		return Vector3.new(-forward.Z, 0, forward.X)
	end
	local function inCourt(p, margin)
		return Vector3.new(math.clamp(p.X, -Hoops.COURT_X + margin, Hoops.COURT_X - margin), p.Y, math.clamp(p.Z, Hoops.BASELINE_Z + margin, Hoops.HALF_Z - margin))
	end
	local function gauss(rng) -- a normally distributed number (mean 0, spread 1)
		return math.sqrt(-2 * math.log(math.max(rng(), 1e-9))) * math.cos(2 * math.pi * rng())
	end
	Brain.inCourt, Brain.rightOf = inCourt, rightOf

	-- Offense. s = { now, me = { pos, vel }, opp = { pos, vel } or nil, hand, busy (a move or shot is under
	-- way), possessionAge, mustClear (take it back past the arc first), mind (its memory, kept by the caller), rng }.
	-- Returns { dir, sprint, face, act } where act is nil, { kind = "move", name, chain } or
	-- { kind = "shoot", finish, hold }.
	function Brain.offense(s)
		local mind, rng, me, opp = s.mind, s.rng, s.me, s.opp
		local toRim = flat(RIM - me.pos)
		local d = toRim.Magnitude
		local forward = unit(toRim)
		local right = rightOf(forward)
		local handSign = if s.hand == "Left" then -1 else 1
		local gap, along, lateral = math.huge, 0, 0
		if opp then
			local rel = flat(opp.pos - me.pos)
			gap, along, lateral = rel.Magnitude, rel:Dot(forward), rel:Dot(right)
		end
		local inLane = opp ~= nil and along > 0 and math.abs(lateral) < 2.5 and gap < 7 -- between it and the rim
		mind.driveSide = mind.driveSide or (if rng() < 0.5 then 1 else -1)
		local out = { face = RIM, dir = ZERO, sprint = false }

		if s.busy then -- mid-move: carry on the way it was going (dashes bring their own motion)
			out.dir = mind.lastDir or ZERO
			return out
		end

		-- Take it back: after a change of possession, dribble out past the arc before anything else.
		if s.mustClear then
			local out1 = flat(me.pos - RIM)
			local clearSpot = Vector3.new(RIM.X, me.pos.Y, RIM.Z) + unit(if out1.Magnitude > 0.5 then out1 else Vector3.new(0, 0, 1)) * (Hoops.THREE_DIST + 2.5)
			out.dir = unit(flat(inCourt(clearSpot, 1.5) - me.pos))
			out.sprint = gap > 5
			out.face = if out.sprint then nil else RIM
			mind.lastDir = out.dir
			return out
		end

		-- Shoot, by what a shot is worth from here under the game's own odds (Hoops.makeChance, its typical
		-- release): finish at the rim, pull up when a clean look beats driving, take a decent look when the
		-- lane's shut, shoot off a stepback, or when its shot clock runs out. An open lane: keep attacking.
		local contested = gap <= Hoops.CONTEST_RANGE
		local pullUp = mind.pendingShot -- set before a stepback: shoot off it only if it made space
		mind.pendingShot = false
		local value = Hoops.makeChance(0.75, d, contested) * (if d >= Hoops.THREE_DIST then 3 else 2)
		local shootNow = d <= Hoops.DUNK_RANGE + 0.5
			or (pullUp and d <= Hoops.THREE_DIST + 4 and (gap >= 3.5 or rng() < 0.3))
			or s.possessionAge > SKILL.shotClock
			or (not inLane and d > Hoops.LAYUP_RANGE and value >= 1.05 and rng() < 0.5)
			or (inLane and value >= 0.9 and rng() < 0.4)
			or (inLane and d <= Hoops.LAYUP_RANGE and (gap > 3 or rng() < 0.15))
		if shootNow then
			local finish = if d <= Hoops.DUNK_RANGE then (if rng() < 0.3 then "DunkTwoHand" else "Dunk") elseif d <= Hoops.LAYUP_RANGE then "Layup" else "JumpShot"
			local hold = math.clamp(Hoops.PERFECT_HOLD + gauss(rng) * SKILL.shotSpread, 0.3, Hoops.PERFECT_HOLD + Hoops.SHOT_WINDOW)
			out.act = { kind = "shoot", finish = finish, hold = hold }
			return out
		end

		-- Dribble moves when the defender's on it.
		if opp and gap < 5.5 and s.now >= (mind.nextMoveAt or 0) and rng() < SKILL.moveRate then
			local name
			local onBallSide = lateral * handSign > 0.4 -- the defender is shading its ball hand
			if gap < 3.5 and d > Hoops.THREE_DIST - 3 and d < Hoops.THREE_DIST + 4 and rng() < 0.45 then
				name, mind.pendingShot = (if rng() < 0.4 then "StepbackEscape" else "Stepback"), true
			elseif onBallSide then
				local r = rng()
				name = if r < 0.45 then "Crossover" elseif r < 0.75 then "BetweenLegs" else "BehindBack"
				mind.driveSide = -handSign -- attack the side the ball is going to
			elseif gap < 2.5 and rng() < 0.4 then
				name = if rng() < 0.5 then "SpinMove" else "SpinEscape"
			else
				local r = rng()
				name = if r < 0.4 then "Hesitation" elseif r < 0.75 then "InAndOut" else "Crossover"
				if name == "Crossover" then
					mind.driveSide = -handSign
				end
			end
			local chain
			if not mind.pendingShot and rng() < SKILL.chainRate then
				local r = rng()
				chain = if r < 0.35 then "BetweenLegs" elseif r < 0.6 then "Crossover" elseif r < 0.8 then "Hesitation" else "Stepback"
				mind.pendingShot = chain == "Stepback"
			end
			mind.nextMoveAt = s.now + 0.9 + rng() * 0.9
			out.act = { kind = "move", name = name, chain = chain }
		end

		-- Attack the rim: straight at it when the lane's clear, around the defender's side when it isn't.
		local target = if inLane then me.pos + forward * 3 + right * mind.driveSide * 3.5 else Vector3.new(RIM.X, me.pos.Y, RIM.Z)
		out.dir = unit(flat(inCourt(target, 1.5) - me.pos))
		out.sprint = not inLane and d > 9 and gap > 4
		if out.sprint then
			out.face = nil -- sprinting turns where it runs, like a player
		end
		mind.lastDir = out.dir
		return out
	end

	-- Defense. s = { now, me = { pos, vel }, opp = { pos, vel } (the ball handler, as it sees them: late by
	-- SKILL.reaction), canReach (its reach would touch the ball right now), shooting, shotKind, shotAge,
	-- newMove (the name of a dribble move the handler just started, if any), mind, rng }.
	-- Returns { dir, sprint, stance, face, act } where act is nil, { kind = "steal" } or { kind = "block" }.
	function Brain.defense(s)
		local mind, rng, me, opp = s.mind, s.rng, s.me, s.opp
		-- A dribble move right in front of it can freeze it for a moment (hesitations most of all).
		if s.newMove and flat(opp.pos - me.pos).Magnitude < 7 then
			local bite = SKILL.biteRate * (if s.newMove == "Hesitation" then 1.5 else 1)
			if rng() < bite then
				mind.bitUntil = s.now + 0.3 + rng() * 0.15
			end
		end
		if s.now < (mind.bitUntil or 0) then
			return { dir = ZERO, face = opp.pos } -- frozen: no steps, no swipes, no jumps
		end
		-- It sees the handler late, so it reads their momentum: it guards where they're heading. A change of
		-- direction (a juke, a crossover) is what beats it, like a real defender.
		local heading = opp.pos + flat(opp.vel) * (SKILL.reaction + 0.1)
		local toRim = flat(RIM - heading)
		local dRim = toRim.Magnitude
		-- Stay between the ball and the rim: sag off way outside, tight on the arc, body up in the paint.
		local gap = if dRim > Hoops.THREE_DIST + 6 then 6 elseif dRim < 7 then math.max(dRim * 0.4, 1.5) else 3.2
		local spot = inCourt(heading + unit(toRim) * math.min(gap, math.max(dRim - 1, 0)), 1.5)
		local toSpot = flat(spot - me.pos)
		local distance = flat(opp.pos - me.pos).Magnitude
		local out = { face = opp.pos, dir = if toSpot.Magnitude > 0.4 then unit(toSpot) else ZERO }
		out.sprint = toSpot.Magnitude > 3.5 or flat(opp.vel).Magnitude > Hoops.WALK_SPEED + 1 -- keep pace with a sprinting handler
		out.stance = toSpot.Magnitude < 1.5 and distance < 9 -- crouch only once in front: stance is slow to recover
		if out.sprint then
			out.face = nil
		end

		-- Block: jump at shots it's close to: at a jump shot's set point, or a layup/dunk's takeoff.
		if not s.shooting then
			mind.jumpedThisShot = false
		elseif not mind.jumpedThisShot and distance <= Hoops.BLOCK_RANGE then
			local move = Hoops.MOVES[s.shotKind]
			local jumpAt = if move and move.jumpAt then move.jumpAt elseif move then move.duration else 0.35
			if s.shotAge >= jumpAt + SKILL.reaction * 0.5 then
				mind.jumpedThisShot = true
				if rng() < (if distance < 4 then SKILL.blockRate else SKILL.blockRate * 0.4) then
					out.act = { kind = "block" }
				end
			end
		end

		-- Steal: only when its reach would really touch the ball (bounce up high, on its side), and not too often.
		if not out.act and s.canReach and not s.shooting and s.now >= (mind.nextStealAt or 0) then
			mind.nextStealAt = s.now + 0.4
			if rng() < SKILL.stealRate then
				out.act = { kind = "steal" }
			end
		end
		return out
	end

	-- Loose ball (rebounds, pokes, passes): run to where it's going. Anywhere on the floor, not just in bounds.
	function Brain.chase(s)
		local ahead = s.ballPos + flat(s.ballVel) * 0.35
		local target = Vector3.new(math.clamp(ahead.X, -43, 43), ahead.Y, math.clamp(ahead.Z, -43, 33))
		local toward = flat(target - s.me.pos)
		return { dir = unit(toward), sprint = toward.Magnitude > 4 }
	end

	return Brain
end
