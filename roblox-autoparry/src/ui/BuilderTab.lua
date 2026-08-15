--[[
	ui/BuilderTab.lua
	Tab 2: logger controls, visualizer toggle, timing editor, save management.

	The dropdowns here are populated once at build time and refreshed by
	ui/Wiring.lua whenever the store changes.
]]

return function(ctx)
	local Tabs, Store, Log = ctx.Tabs, ctx.Store, ctx.Log

	local LoggerBox = Tabs.Builder:AddLeftGroupbox("Info Logger")

	LoggerBox:AddToggle("ShowLoggerWindow", {
		Text = "Show Logger Window",
		Default = false,
	}):AddKeyPicker("LoggerKey", {
		Default = "N/A",
		SyncToggleState = true,
		Mode = "Toggle",
		Text = "Logger Window",
	})

	LoggerBox:AddToggle("LogOnlyUnknown", {
		Text = "Only Log Unknown",
		Default = false,
		Tooltip = "Hide animations that already have a timing",
	})

	LoggerBox:AddSlider("LogMinDistance", {
		Text = "Min Distance",
		Default = 0,
		Min = 0,
		Max = 200,
		Rounding = 0,
		Suffix = "m",
	})

	LoggerBox:AddSlider("LogMaxDistance", {
		Text = "Max Distance",
		Default = 80,
		Min = 0,
		Max = 500,
		Rounding = 0,
		Suffix = "m",
		Tooltip = "0 disables the upper bound",
	})

	LoggerBox:AddButton("Clear Log", function()
		Log.clear()
	end)

	local VisualBox = Tabs.Builder:AddLeftGroupbox("Animation Visualizer")

	VisualBox:AddToggle("ShowAnimationVisualizer", {
		Text = "Show Visualizer",
		Default = false,
	}):AddKeyPicker("VisualizerKey", {
		Default = "N/A",
		SyncToggleState = true,
		Mode = "Toggle",
		Text = "Visualizer",
	})

	local BuilderBox = Tabs.Builder:AddRightGroupbox("Timing Builder")

	local timingList = BuilderBox:AddDropdown("TimingList", {
		Values = Store.display(),
		Default = nil,
		AllowNull = true,
		Text = "Timing",
	})

	BuilderBox:AddInput("T_Name", { Default = "", Text = "Name", Finished = true })

	BuilderBox:AddSlider("T_Delay", {
		Text = "Parry Delay",
		Default = 400,
		Min = 0,
		Max = 4000,
		Rounding = 0,
		Suffix = "ms",
		Tooltip = "How far into the animation the hit lands",
	})

	BuilderBox:AddSlider("T_HoldTime", {
		Text = "Hold Time",
		Default = 120,
		Min = 10,
		Max = 600,
		Rounding = 0,
		Suffix = "ms",
	})

	BuilderBox:AddSlider("T_MinDistance", {
		Text = "Min Distance",
		Default = 0,
		Min = 0,
		Max = 200,
		Rounding = 0,
		Suffix = "m",
	})

	BuilderBox:AddSlider("T_MaxDistance", {
		Text = "Max Distance",
		Default = 60,
		Min = 0,
		Max = 500,
		Rounding = 0,
		Suffix = "m",
	})

	BuilderBox:AddToggle("T_Enabled", { Text = "Enabled", Default = false })

	local StoreBox = Tabs.Builder:AddRightGroupbox("Timing Saves")

	StoreBox:AddToggle("AutoCreateTimings", {
		Text = "Auto Create Timings",
		Default = true,
		Tooltip = "Make a stub for every unseen animation",
	})

	StoreBox:AddToggle("AutoSaveOnCreate", {
		Text = "Save On Create",
		Default = true,
		Tooltip = "Write the database to disk the moment a timing is created",
	})

	StoreBox:AddToggle("AutoEnableNewTimings", {
		Text = "Auto Enable New",
		Default = false,
		Tooltip = "Off by default so fresh guesses do not parry at random",
	})

	StoreBox:AddInput("ConfigName", { Default = "default", Text = "Config Name", Finished = true })

	local configList = StoreBox:AddDropdown("ConfigList", {
		Values = Store.list(),
		Default = nil,
		AllowNull = true,
		Text = "Config",
	})

	local StoreLabel = StoreBox:AddLabel("Timings: 0", true)

	ctx.BuilderBox = BuilderBox
	ctx.StoreBox = StoreBox
	ctx.timingList = timingList
	ctx.configList = configList
	ctx.StoreLabel = StoreLabel

	return BuilderBox
end
