--[[
	ui/MainTab.lua
	Tab 1: the auto parry itself, targeting rules, humanisation, notifications.
]]

return function(ctx)
	local Tabs, Input = ctx.Tabs, ctx.Input

	local ParryBox = Tabs.Main:AddLeftGroupbox("Auto Parry")

	ParryBox:AddToggle("AutoParry", {
		Text = "Enable Auto Parry",
		Default = false,
		Tooltip = "Schedules a parry keypress for every enabled timing that fires",
	}):AddKeyPicker("AutoParryKey", {
		Default = "N/A",
		SyncToggleState = true,
		Mode = "Toggle",
		Text = "Auto Parry",
	})

	ParryBox:AddDropdown("ParryKey", {
		Values = Input.keys,
		Default = "F",
		Text = "Parry Key",
		Tooltip = "The key pressed to parry or block",
	})

	ParryBox:AddSlider("HoldTime", {
		Text = "Hold Time",
		Default = 120,
		Min = 10,
		Max = 600,
		Rounding = 0,
		Suffix = "ms",
		Tooltip = "How long the key is held down",
	})

	ParryBox:AddDivider()

	ParryBox:AddSlider("PingCompensation", {
		Text = "Ping Compensation",
		Default = 100,
		Min = 0,
		Max = 150,
		Rounding = 0,
		Suffix = "%",
		Tooltip = "How much of your round trip time to subtract from the parry delay",
	})

	ParryBox:AddSlider("ParryOffset", {
		Text = "Manual Offset",
		Default = 0,
		Min = -300,
		Max = 300,
		Rounding = 0,
		Suffix = "ms",
		Tooltip = "Positive parries earlier, negative parries later",
	})

	ParryBox:AddSlider("ParryCooldown", {
		Text = "Cooldown",
		Default = 60,
		Min = 0,
		Max = 1000,
		Rounding = 0,
		Suffix = "ms",
		Tooltip = "Minimum gap between two parries",
	})

	local TargetBox = Tabs.Main:AddLeftGroupbox("Targeting")

	TargetBox:AddDropdown("EntitySource", {
		Values = { "Auto", "Workspace", "Custom" },
		Default = "Auto",
		Text = "Entity Source",
		Tooltip = "Auto checks Live, Characters, Enemies, Mobs, NPCs then falls back to workspace",
	})

	-- Not wrapped in a dependency box on purpose: Linoria's Depbox:Update only
	-- evaluates dependencies whose element Type is 'Toggle', so a dropdown
	-- dependency would never actually hide anything.
	TargetBox:AddInput("EntityFolder", {
		Default = "",
		Text = "Folder Name",
		Placeholder = "only used when source is Custom",
		Finished = true,
		Tooltip = "Name of a direct child of workspace holding the characters",
	})

	TargetBox:AddToggle("IgnorePlayers", { Text = "Ignore Players", Default = false })
	TargetBox:AddToggle("IgnoreNPCs", { Text = "Ignore NPCs", Default = false })
	TargetBox:AddToggle("OnlyWhenTargeted", {
		Text = "Only When Targeted",
		Default = false,
		Tooltip = "Requires an ObjectValue named Target on the entity pointing at you",
	})

	local facingToggle = TargetBox:AddToggle("RequireFacing", {
		Text = "Require Facing",
		Default = false,
		Tooltip = "Only parry attackers that are looking at you",
	})

	local facingDep = TargetBox:AddDependencyBox()
	facingDep:AddSlider("FacingDot", {
		Text = "Facing Threshold",
		Default = 0.4,
		Min = -1,
		Max = 1,
		Rounding = 2,
		Tooltip = "1 is dead-on, 0 is perpendicular",
	})

	local SafetyBox = Tabs.Main:AddRightGroupbox("Humanisation")

	SafetyBox:AddToggle("DisableWhileHolding", {
		Text = "Skip If Key Held",
		Default = true,
		Tooltip = "Do not fight your own manual input",
	})

	local randomToggle = SafetyBox:AddToggle("RandomizeOffset", {
		Text = "Randomise Offset",
		Default = true,
		Tooltip = "Adds jitter so every parry is not frame-identical",
	})

	local randomDep = SafetyBox:AddDependencyBox()
	randomDep:AddSlider("RandomRange", {
		Text = "Jitter Range",
		Default = 20,
		Min = 1,
		Max = 120,
		Rounding = 0,
		Suffix = "ms",
	})

	SafetyBox:AddSlider("MissChance", {
		Text = "Miss Chance",
		Default = 0,
		Min = 0,
		Max = 100,
		Rounding = 0,
		Suffix = "%",
		Tooltip = "Chance to intentionally drop a parry",
	})

	local NotifyBox = Tabs.Main:AddRightGroupbox("Notifications")

	NotifyBox:AddToggle("NotifyOnParry", { Text = "Notify On Parry", Default = false })
	NotifyBox:AddToggle("NotifyOnNewTiming", { Text = "Notify On New Timing", Default = true })
	NotifyBox:AddToggle("ShowDebug", { Text = "Debug Messages", Default = false })

	local StatsLabel = NotifyBox:AddLabel("Parries: 0 | Pending: 0 | Ping: 0ms", true)

	facingDep:SetupDependencies({ { facingToggle, true } })
	randomDep:SetupDependencies({ { randomToggle, true } })

	-- Runtime.lua updates this every second.
	ctx.StatsLabel = StatsLabel

	return StatsLabel
end
