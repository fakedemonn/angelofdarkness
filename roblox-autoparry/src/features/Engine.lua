--[[
	features/Engine.lua
	The auto parry itself.

	Timing model
	------------
	Stats "Data Ping" is a round trip. The attacker's animation started roughly
	one one-way-delay ago, and our keypress needs another one-way-delay to reach
	the server, so subtracting the FULL rtt puts the input on the server at the
	moment the hit lands:

	    wait = (delay / 1000) - (rtt * compensation) - offset + jitter

	Everything is revalidated inside the delayed callback rather than trusted
	from schedule time, because a wind-up is long enough for the target to die,
	despawn, or walk out of range.
]]

return function(ctx)
	local Util, Input, Latency = ctx.Util, ctx.Input, ctx.Latency
	local Store, Log, Entities, State = ctx.Store, ctx.Log, ctx.Entities, ctx.State
	local LocalPlayer, notify = ctx.LocalPlayer, ctx.notify

	local Engine = {}

	local DODGE_KEYS = { Left = "A", Right = "D", Back = "S", Forward = "W" }

	---Debug notification, only when the toggle is on.
	local function debug(fmt, ...)
		local Toggles = ctx.Toggles
		if Toggles.ShowDebug and Toggles.ShowDebug.Value then
			notify(string.format(fmt, ...), 2)
		end
	end

	---Is the player inside this timing's hitbox?
	---Measured in the attacker's local space, so a wide horizontal sweep and a
	---narrow forward thrust are not forced to share one distance number.
	---@param timing table
	---@param entity Model
	---@return boolean
	function Engine.inHitbox(timing, entity)
		local hitbox = timing.hitbox
		if type(hitbox) ~= "table" then
			return true
		end

		local root = entity.PrimaryPart
			or entity:FindFirstChild("HumanoidRootPart")
			or entity:FindFirstChildWhichIsA("BasePart")

		local character = LocalPlayer.Character
		local ourRoot = character and character:FindFirstChild("HumanoidRootPart")

		if not root or not ourRoot then
			return true
		end

		-- Into the attacker's frame: X is their right, Y up, Z forward/back.
		local localPoint = root.CFrame:PointToObjectSpace(ourRoot.Position)
		local pad = timing.hso or 0

		return math.abs(localPoint.X) <= (hitbox.X / 2) + pad
			and math.abs(localPoint.Y) <= (hitbox.Y / 2) + pad
			and math.abs(localPoint.Z) <= (hitbox.Z / 2) + pad
	end

	---Fire the parry input once.
	---@param timing table
	function Engine.fire(timing)
		local Toggles, Options = ctx.Toggles, ctx.Options

		local ok, reason = State.canParry()
		if not ok then
			debug("[skip] %s - %s", timing.name, reason)
			return
		end

		local key = Options.ParryKey and Options.ParryKey.Value or "F"
		local hold = (timing.holdTime or Options.HoldTime.Value or 120) / 1000

		-- Directional dodge: hold the movement key across the parry so the game
		-- reads a directional roll rather than a neutral block.
		local dodge = DODGE_KEYS[timing.dodgeDir or "None"]
		if dodge then
			Input.down(dodge)
			task.delay(hold + 0.02, function()
				Input.up(dodge)
			end)
		end

		Input.tap(key, hold)

		State.lastParry = os.clock()
		State.parries = State.parries + 1

		if Toggles.NotifyOnParry and Toggles.NotifyOnParry.Value then
			notify(string.format("Parried %s (%dms)", timing.name, timing.delay), 1.5)
		end
	end

	---Fire, then repeat for multi-hit attacks.
	---@param timing table
	function Engine.fireSequence(timing)
		Engine.fire(timing)

		local count = math.max(math.floor(timing.repeatCount or 1), 1)
		if count <= 1 then
			return
		end

		local gap = math.max(timing.repeatDelay or 0.35, 0.05)

		task.spawn(function()
			for _ = 2, count do
				task.wait(gap)
				-- Cooldown would otherwise eat every follow-up hit in the chain.
				State.lastParry = 0
				Engine.fire(timing)
			end
		end)
	end

	---Schedule a parry for a track that just started.
	---@param timing table
	---@param entity Model
	---@param track AnimationTrack
	function Engine.schedule(timing, entity, track)
		local Toggles, Options = ctx.Toggles, ctx.Options

		-- Humanised miss.
		local missChance = Options.MissChance and Options.MissChance.Value or 0
		if missChance > 0 and Random.new():NextNumber(0, 100) <= missChance then
			State.misses = State.misses + 1
			debug("[miss] %s (intentional)", timing.name)
			return
		end

		local compensation = (Options.PingCompensation and Options.PingCompensation.Value or 100) / 100
		local offset = (Options.ParryOffset and Options.ParryOffset.Value or 0) / 1000

		local jitter = 0
		if Toggles.RandomizeOffset and Toggles.RandomizeOffset.Value then
			local range = (Options.RandomRange and Options.RandomRange.Value or 20) / 1000
			jitter = Random.new():NextNumber(-range, range)
		end

		local wait = (timing.delay / 1000) - (Latency.rtt() * compensation) - offset + jitter
		wait = math.max(wait, 0)

		State.pending = State.pending + 1

		task.delay(wait, function()
			State.pending = math.max(State.pending - 1, 0)

			-- Revalidate at fire time; a lot can change during the wind-up.
			if not track.IsPlaying and not (timing.ignoreEnd == true) then
				debug("[skip] %s - animation stopped", timing.name)
				return
			end

			if not Entities.valid(entity) then
				return
			end

			local distance = Util.distance(entity, LocalPlayer.Character)
			if not distance then
				return
			end

			if distance < (timing.minDistance or 0) then
				return
			end

			if timing.maxDistance and timing.maxDistance > 0 and distance > timing.maxDistance then
				return
			end

			if not Engine.inHitbox(timing, entity) then
				debug("[skip] %s - outside hitbox", timing.name)
				return
			end

			Engine.fireSequence(timing)
		end)
	end

	---Handle one animation starting on one entity.
	---@param entity Model
	---@param track AnimationTrack
	function Engine.onAnimation(entity, track)
		local Toggles, Options = ctx.Toggles, ctx.Options

		if not track.Animation then
			return
		end

		local animationId = tostring(track.Animation.AnimationId)
		if animationId == "" then
			return
		end

		local character = LocalPlayer.Character
		if not character or entity == character then
			return
		end

		local distance = Util.distance(entity, character)
		if not distance then
			return
		end

		local timing = Store.get(animationId)

		-- Logging gate.
		local logMin = Options.LogMinDistance and Options.LogMinDistance.Value or 0
		local logMax = Options.LogMaxDistance and Options.LogMaxDistance.Value or 0
		local inLogRange = distance >= logMin and (logMax <= 0 or distance <= logMax)
		local onlyUnknown = Toggles.LogOnlyUnknown and Toggles.LogOnlyUnknown.Value

		if inLogRange and (not onlyUnknown or not timing) then
			Log.push({
				id = animationId,
				-- Track name is what the game's own animator calls it. Usually far
				-- more readable than the asset id when hunting one specific move.
				animName = (track.Name ~= "" and track.Name) or "Animation",
				assetId = animationId:match("(%d+)") or "?",
				time = os.date("%H:%M:%S"),
				entity = entity.Name,
				model = entity,
				distance = Util.round(distance, 1),
				length = Util.round(track.Length, 3),
				speed = Util.round(track.Speed, 2),
				priority = track.Priority.Name,
				known = timing ~= nil,
				ping = math.floor(Latency.rtt() * 1000),
				clock = os.clock(),
			})

			-- Always record. Gating this on the visualizer being open meant you had
			-- to predict which animation you wanted to inspect before it played.
			Log.record(animationId, entity, track)
		end

		-- Auto-create a stub for anything we have never seen.
		if not timing and Toggles.AutoCreateTimings and Toggles.AutoCreateTimings.Value then
			if Entities.valid(entity) and inLogRange then
				timing = Store.template(animationId, track.Length, entity.Name)
				timing.enabled = Toggles.AutoEnableNewTimings and Toggles.AutoEnableNewTimings.Value or false

				-- Written to disk the instant it is created, not on a timer.
				Store.create(timing, Toggles.AutoSaveOnCreate and Toggles.AutoSaveOnCreate.Value or false)

				if Toggles.NotifyOnNewTiming and Toggles.NotifyOnNewTiming.Value then
					notify(string.format("New timing: %s [%s]", timing.name, Util.shortId(animationId)), 3)
				end
			end
		end

		if not timing or not timing.enabled then
			return
		end

		if not Entities.valid(entity) then
			return
		end

		if distance < (timing.minDistance or 0) then
			return
		end

		if timing.maxDistance and timing.maxDistance > 0 and distance > timing.maxDistance then
			return
		end

		Engine.schedule(timing, entity, track)
	end

	ctx.Engine = Engine
	return Engine
end
