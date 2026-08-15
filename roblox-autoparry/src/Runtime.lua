--[[
	Runtime.lua
	Watermark, the per-frame visualizer step, the stats loop, and unload.

	Two loops on purpose: the visualizer needs RenderStepped so scrubbing and
	playback stay smooth, but redrawing the logger 240 times a second is pure
	waste, so text updates run on their own 0.15s timer.
]]

return function(ctx)
	local Library, RunService = ctx.Library, ctx.RunService
	local Latency, State, Store, Hooks = ctx.Latency, ctx.State, ctx.Store, ctx.Hooks
	local LoggerGui, Visualizer, StatsLabel = ctx.LoggerGui, ctx.Visualizer, ctx.StatsLabel

	Library:SetWatermarkVisibility(true)

	local frameTimer = os.clock()
	local frameCount = 0
	local fps = 60

	local renderConnection = RunService.RenderStepped:Connect(function(delta)
		frameCount = frameCount + 1
		if os.clock() - frameTimer >= 1 then
			fps = frameCount
			frameTimer = os.clock()
			frameCount = 0
		end

		Library:SetWatermark(
			string.format(
				"AutoParry v%s | %d fps | %d ms | %d parries",
				ctx.VERSION,
				fps,
				math.floor(Latency.rtt() * 1000),
				State.parries
			)
		)

		Visualizer.step(delta)
	end)

	task.spawn(function()
		while not Library.Unloaded do
			LoggerGui.refresh()

			StatsLabel:SetText(
				string.format(
					"Parries: %d | Pending: %d | Missed: %d | Ping: %dms",
					State.parries,
					State.pending,
					State.misses,
					math.floor(Latency.rtt() * 1000)
				)
			)

			task.wait(0.15)
		end
	end)

	Library:OnUnload(function()
		renderConnection:Disconnect()
		Hooks.detach()

		if Store.dirty then
			Store.save(Store.configName)
		end

		Library.Unloaded = true
		print("[AutoParry] Unloaded.")
	end)

	return renderConnection
end
