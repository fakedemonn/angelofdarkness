--[[
	features/Hooks.lua
	Animator.AnimationPlayed listeners.

	sweep() is safe to call repeatedly. The per-container DescendantAdded
	listener is stored separately and replaced rather than appended, because it
	gets re-run on respawn and on every entity-source change; stacking it was
	quietly multiplying every animation event.
]]

return function(ctx)
	local Entities = ctx.Entities

	local Hooks = {
		connections = {},
		hooked = {},
		containerConnection = nil,
	}

	---Hook a single animator.
	---@param animator Animator
	function Hooks.attach(animator)
		if Hooks.hooked[animator] then
			return
		end

		local entity = animator:FindFirstAncestorWhichIsA("Model")
		if not entity then
			return
		end

		Hooks.hooked[animator] = true

		local connection = animator.AnimationPlayed:Connect(function(track)
			local ok, err = pcall(ctx.Engine.onAnimation, entity, track)
			if not ok and ctx.Toggles.ShowDebug and ctx.Toggles.ShowDebug.Value then
				warn("[AutoParry] " .. tostring(err))
			end
		end)

		table.insert(Hooks.connections, connection)

		table.insert(
			Hooks.connections,
			animator.AncestryChanged:Connect(function(_, parent)
				if not parent then
					Hooks.hooked[animator] = nil
					connection:Disconnect()
				end
			end)
		)
	end

	---Sweep a container and hook every animator in it.
	function Hooks.sweep()
		local container = Entities.container()

		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant:IsA("Animator") then
				Hooks.attach(descendant)
			end
		end

		if Hooks.containerConnection then
			pcall(function()
				Hooks.containerConnection:Disconnect()
			end)
		end

		Hooks.containerConnection = container.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Animator") then
				Hooks.attach(descendant)
			end
		end)
	end

	function Hooks.detach()
		for _, connection in ipairs(Hooks.connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		if Hooks.containerConnection then
			pcall(function()
				Hooks.containerConnection:Disconnect()
			end)
			Hooks.containerConnection = nil
		end

		Hooks.connections = {}
		Hooks.hooked = {}
	end

	ctx.Hooks = Hooks
	return Hooks
end
