--[[
	features/Entities.lua
	Where the combat characters live, and whether one is worth parrying.

	This module is what makes the script game-agnostic. Nothing above it knows a
	game's folder names; Auto mode probes the handful of names most Roblox combat
	games use and falls back to workspace, and Custom lets you name the folder
	outright when a game does something unusual.
]]

return function(ctx)
	local Util, Workspace, Players, LocalPlayer = ctx.Util, ctx.Workspace, ctx.Players, ctx.LocalPlayer

	local Entities = {}

	-- Probed in order by Auto mode.
	Entities.CANDIDATES = { "Live", "Characters", "Enemies", "Mobs", "NPCs" }

	---Resolve the container that holds combat characters.
	function Entities.container()
		local Options = ctx.Options
		local mode = Options and Options.EntitySource and Options.EntitySource.Value or "Auto"

		if mode == "Workspace" then
			return Workspace
		end

		if mode == "Custom" then
			local name = Options and Options.EntityFolder and Options.EntityFolder.Value or ""
			local found = name ~= "" and Workspace:FindFirstChild(name)
			return found or Workspace
		end

		for _, candidate in ipairs(Entities.CANDIDATES) do
			local found = Workspace:FindFirstChild(candidate)
			if found then
				return found
			end
		end

		return Workspace
	end

	---Every rig in the container, humanoid only.
	---@return table
	function Entities.list()
		local out = {}
		local container = Entities.container()

		if not container then
			return out
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChildWhichIsA("Humanoid") then
				table.insert(out, child)
			end
		end

		return out
	end

	---Is this entity a valid parry target right now?
	---@param entity Model
	---@return boolean, string
	function Entities.valid(entity)
		local Toggles, Options = ctx.Toggles, ctx.Options
		local character = LocalPlayer.Character

		if not character then
			return false, "no local character"
		end

		if entity == character then
			return false, "self"
		end

		if not Util.alive(entity) then
			return false, "dead"
		end

		local isPlayer = Players:GetPlayerFromCharacter(entity) ~= nil

		if isPlayer and Toggles.IgnorePlayers and Toggles.IgnorePlayers.Value then
			return false, "players ignored"
		end

		if not isPlayer and Toggles.IgnoreNPCs and Toggles.IgnoreNPCs.Value then
			return false, "npcs ignored"
		end

		if Toggles.OnlyWhenTargeted and Toggles.OnlyWhenTargeted.Value then
			local target = entity:FindFirstChild("Target")
			if target and target:IsA("ObjectValue") and target.Value ~= character then
				return false, "not targeting us"
			end
		end

		if Toggles.RequireFacing and Toggles.RequireFacing.Value then
			local dot = Util.facing(entity, character)
			local minimum = (Options.FacingDot and Options.FacingDot.Value or 0.4)
			if not dot or dot < minimum then
				return false, "not facing us"
			end
		end

		return true, "ok"
	end

	ctx.Entities = Entities
	return Entities
end
