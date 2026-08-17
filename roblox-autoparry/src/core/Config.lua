--[[
	core/Config.lua
	Constants, services and the folder layout every other module reads from.
]]

return function(ctx)
	ctx.VERSION = "1.0.0"
	ctx.LIB_REPO = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

	-- Where the bundled timing databases are fetched from when a place has no
	-- local one yet. Must end in a slash.
	ctx.DATA_REPO = "https://raw.githubusercontent.com/fakedemonn/angelofdarkness/main/roblox-autoparry/"

	-- Folder layout inside the executor workspace:
	--   AutoParry/
	--     timings/<PlaceId>/<config>.json   the timing databases
	--     effects/<PlaceId>/default.json    the effect / projectile profiles
	--     settings/                         LinoriaLib UI config
	--     themes/                           LinoriaLib themes
	ctx.ROOT_FOLDER = "AutoParry"
	ctx.TIMINGS_FOLDER = "AutoParry/timings"
	ctx.SETTINGS_FOLDER = "AutoParry/settings"
	ctx.EFFECTS_FOLDER = "AutoParry/effects"

	ctx.Players = game:GetService("Players")
	ctx.RunService = game:GetService("RunService")
	ctx.HttpService = game:GetService("HttpService")
	ctx.UserInputService = game:GetService("UserInputService")
	ctx.Stats = game:GetService("Stats")
	ctx.Workspace = game:GetService("Workspace")

	ctx.LocalPlayer = ctx.Players.LocalPlayer
end
