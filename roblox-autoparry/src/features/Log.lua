--[[
	features/Log.lua
	Animation info logger, data half.

	A ring buffer of every animation seen, plus a recorded speed curve per
	animation so the visualizer can replay a move at the speed it was actually
	played at you rather than at 1x. Attackers with haste effects are the whole
	reason that distinction matters: the delay you measure at 1.4x is wrong at 1x.

	The window that renders this lives in ui/LoggerWindow.lua.
]]

return function(ctx)
	local RunService = ctx.RunService

	local Log = {
		entries = {},
		playback = {},
		selected = nil,
		max = 150,
	}

	---Record one animation event.
	---@param entry table
	function Log.push(entry)
		table.insert(Log.entries, 1, entry)
		while #Log.entries > Log.max do
			table.remove(Log.entries)
		end
	end

	function Log.clear()
		Log.entries = {}
		Log.selected = nil
	end

	---Begin recording the speed curve of a track.
	---@param animationId string
	---@param entity Model
	---@param track AnimationTrack
	function Log.record(animationId, entity, track)
		local samples = { { t = 0, speed = track.Speed } }
		local started = os.clock()

		Log.playback[animationId] = {
			entity = entity,
			samples = samples,
			length = track.Length,
		}

		task.spawn(function()
			while track.IsPlaying do
				local elapsed = os.clock() - started
				local last = samples[#samples]
				if math.abs(last.speed - track.Speed) > 0.001 then
					table.insert(samples, { t = elapsed, speed = track.Speed })
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	---Speed at a given elapsed time from the recorded curve.
	---@param animationId string
	---@param elapsed number
	---@return number
	function Log.speedAt(animationId, elapsed)
		local data = Log.playback[animationId]
		if not data then
			return 1
		end

		local speed = data.samples[1] and data.samples[1].speed or 1
		for _, sample in ipairs(data.samples) do
			if sample.t > elapsed then
				break
			end
			speed = sample.speed
		end
		return speed
	end

	ctx.Log = Log
	return Log
end
