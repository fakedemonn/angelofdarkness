--[[
	Boot.lua
	Last module in the chain. Creates the timing folder, loads the default
	config, hooks every animator currently in the world, and says hello.
]]

return function(ctx)
	local Store, FS, Input, Hooks = ctx.Store, ctx.FS, ctx.Input, ctx.Hooks
	local notify, LocalPlayer = ctx.notify, ctx.LocalPlayer
	local configList, refreshTimingList = ctx.configList, ctx.refreshTimingList

	Store.init()

	if not FS.available then
		notify("No filesystem access - timings will not persist", 6)
	end

	if not Input.available then
		notify("No input backend found - parry cannot fire", 6)
	end

	-- Load the autoload config if one exists, otherwise start on "default".
	if FS.isFile(Store.path("default")) then
		Store.load("default")
	end

	configList:SetValues(Store.list())
	configList:Display()
	refreshTimingList()

	Hooks.sweep()

	-- Re-sweep on respawn, since a new character means a new animator tree.
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		Hooks.sweep()
	end)

	ctx.SaveManager:LoadAutoloadConfig()

	notify(string.format("AutoParry v%s loaded for place %d", ctx.VERSION, game.PlaceId), 4)

	return true
end
