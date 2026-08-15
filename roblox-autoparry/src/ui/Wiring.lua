--[[
	ui/Wiring.lua
	Connects the Builder tab controls to the store, the windows and the hooks.

	Everything here is a callback, so it runs long after load and can capture
	ctx.Toggles / ctx.Options directly.
]]

return function(ctx)
	local Toggles, Options = ctx.Toggles, ctx.Options
	local Store, Log, Util, FS, Hooks = ctx.Store, ctx.Log, ctx.Util, ctx.FS, ctx.Hooks
	local LoggerGui, Visualizer, notify = ctx.LoggerGui, ctx.Visualizer, ctx.notify
	local BuilderBox, StoreBox = ctx.BuilderBox, ctx.StoreBox
	local timingList, configList, StoreLabel = ctx.timingList, ctx.configList, ctx.StoreLabel

	---Push the selected timing into the builder fields.
	local function loadTimingIntoBuilder(timing)
		if not timing then
			return
		end
		Options.T_Name:SetValue(timing.name or "")
		Options.T_Delay:SetValue(timing.delay or 0)
		Options.T_HoldTime:SetValue(timing.holdTime or 120)
		Options.T_MinDistance:SetValue(timing.minDistance or 0)
		Options.T_MaxDistance:SetValue(timing.maxDistance or 60)
		Toggles.T_Enabled:SetValue(timing.enabled == true)
	end

	---Refresh the timing dropdown, keeping the current selection where possible.
	local function refreshTimingList()
		timingList:SetValues(Store.display())
		timingList:Display()
		StoreLabel:SetText(string.format("Timings: %d | Config: %s", Store.count(), Store.configName))
	end

	-- Boot.lua calls this once the database is on disk.
	ctx.refreshTimingList = refreshTimingList
	ctx.loadTimingIntoBuilder = loadTimingIntoBuilder

	Options.TimingList:OnChanged(function()
		local timing = Store.fromDisplay(Options.TimingList.Value)
		loadTimingIntoBuilder(timing)
	end)

	BuilderBox:AddButton({
		Text = "Save Timing",
		Tooltip = "Write the builder fields back to the selected timing",
		Func = function()
			local timing = Store.fromDisplay(Options.TimingList.Value)
			if not timing then
				return notify("Select a timing first", 2)
			end

			timing.name = Options.T_Name.Value ~= "" and Options.T_Name.Value or timing.name
			timing.delay = Options.T_Delay.Value
			timing.holdTime = Options.T_HoldTime.Value
			timing.minDistance = Options.T_MinDistance.Value
			timing.maxDistance = Options.T_MaxDistance.Value
			timing.enabled = Toggles.T_Enabled.Value

			Store.save(Store.configName)
			refreshTimingList()
			notify("Saved " .. timing.name, 2)
		end,
	}):AddButton({
		Text = "Delete Timing",
		DoubleClick = true,
		Func = function()
			local timing = Store.fromDisplay(Options.TimingList.Value)
			if not timing then
				return notify("Select a timing first", 2)
			end
			Store.remove(timing.id)
			Store.save(Store.configName)
			Options.TimingList:SetValue(nil)
			refreshTimingList()
			notify("Deleted " .. timing.name, 2)
		end,
	})

	BuilderBox:AddButton("Create From Selected Log", function()
		if not Log.selected then
			return notify("Click a row in the logger window first", 2)
		end

		local existing = Store.get(Log.selected)
		if existing then
			Options.TimingList:SetValue(
				string.format(
					"%s [%s]%s",
					existing.name,
					Util.shortId(existing.id),
					existing.enabled and "" or " (off)"
				)
			)
			return notify("That animation already has a timing", 2)
		end

		local length = Log.playback[Log.selected] and Log.playback[Log.selected].length or 1
		local entityName = "Unnamed"

		for _, entry in ipairs(Log.entries) do
			if entry.id == Log.selected then
				entityName = entry.entity
				length = entry.length
				break
			end
		end

		local timing = Store.template(Log.selected, length, entityName)
		Store.create(timing, true)
		refreshTimingList()
		loadTimingIntoBuilder(timing)
		notify("Created timing for " .. entityName, 2)
	end)

	StoreBox:AddButton({
		Text = "Save Config",
		Func = function()
			local name = Options.ConfigName.Value
			if name == "" then
				return notify("Give the config a name", 2)
			end
			Store.configName = name
			local ok = Store.save(name)
			configList:SetValues(Store.list())
			configList:Display()
			refreshTimingList()
			notify(ok and ("Saved config " .. name) or "Save failed", 2)
		end,
	}):AddButton({
		Text = "Load Config",
		DoubleClick = true,
		Func = function()
			local name = Options.ConfigList.Value
			if not name then
				return notify("Pick a config", 2)
			end
			local ok, err = Store.load(name)
			Options.TimingList:SetValue(nil)
			refreshTimingList()
			notify(ok and ("Loaded " .. name) or ("Load failed: " .. tostring(err)), 2)
		end,
	})

	StoreBox:AddButton("Refresh Lists", function()
		configList:SetValues(Store.list())
		configList:Display()
		refreshTimingList()
	end)

	StoreBox:AddButton({
		Text = "Delete Config",
		DoubleClick = true,
		Func = function()
			local name = Options.ConfigList.Value
			if not name then
				return notify("Pick a config", 2)
			end
			FS.delete(Store.path(name))
			configList:SetValues(Store.list())
			configList:SetValue(nil)
			configList:Display()
			notify("Deleted config " .. name, 2)
		end,
	})

	Toggles.ShowLoggerWindow:OnChanged(function()
		LoggerGui.visible(Toggles.ShowLoggerWindow.Value)
	end)

	Toggles.ShowAnimationVisualizer:OnChanged(function()
		Visualizer.visible(Toggles.ShowAnimationVisualizer.Value)
	end)

	Options.EntitySource:OnChanged(function()
		Hooks.detach()
		task.defer(Hooks.sweep)
	end)

	Options.EntityFolder:OnChanged(function()
		Hooks.detach()
		task.defer(Hooks.sweep)
	end)

	return refreshTimingList
end
