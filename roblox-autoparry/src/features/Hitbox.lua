--[[
	features/Hitbox.lua
	Draws the parry hitbox and the max-distance ring in the world.

	The gate in Engine.inHitbox is a box measured in the ATTACKER's local space -
	X is their right, Y up, Z forward - so the preview is welded to the attacker's
	root CFrame, not to yours. Drawing it any other way would show you a box that
	does not match the check.

	Colour is driven by Engine.inHitbox itself rather than a reimplementation of
	the maths, so the picture cannot drift out of agreement with what the parry
	will actually do: green means you are inside the gate right now, red means the
	parry would be skipped.

	Parts live under Workspace.CurrentCamera. Anything parented there renders but
	is never replicated, so the preview does not become something the game's own
	code can see.
]]

return function(ctx)
	local Workspace, LocalPlayer = ctx.Workspace, ctx.LocalPlayer
	local Entities, Util = ctx.Entities, ctx.Util

	local Hitbox = {}

	-- Used until the sliders exist, and whenever one is missing.
	local FALLBACK = { X = 11, Y = 10, Z = 30.5, hso = 3, maxDistance = 85 }

	local INSIDE = Color3.fromRGB(90, 230, 120)
	local OUTSIDE = Color3.fromRGB(255, 90, 90)
	local RING = Color3.fromRGB(120, 170, 255)

	local folder, boxPart, boxOutline, ringPart

	Hitbox.distance = nil
	Hitbox.inside = false

	---Create the preview parts once, and re-create them if something wiped them.
	---@return boolean
	local function ensureParts()
		if folder and folder.Parent then
			return true
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return false
		end

		folder = Instance.new("Folder")
		folder.Name = "AP_HitboxPreview"

		boxPart = Instance.new("Part")
		boxPart.Name = "Box"
		boxPart.Anchored = true
		boxPart.CanCollide = false
		boxPart.CanQuery = false
		boxPart.CanTouch = false
		boxPart.CastShadow = false
		boxPart.Material = Enum.Material.ForceField
		boxPart.Color = OUTSIDE
		boxPart.Transparency = 1
		boxPart.Size = Vector3.new(1, 1, 1)
		boxPart.Parent = folder

		-- The fill alone reads as mush at a distance; the wireframe is what makes
		-- the shape legible while you drag a slider.
		boxOutline = Instance.new("SelectionBox")
		boxOutline.Adornee = boxPart
		boxOutline.LineThickness = 0.04
		boxOutline.SurfaceTransparency = 1
		boxOutline.Color3 = OUTSIDE
		boxOutline.Visible = false
		boxOutline.Parent = boxPart

		ringPart = Instance.new("Part")
		ringPart.Name = "MaxDistance"
		ringPart.Shape = Enum.PartType.Cylinder
		ringPart.Anchored = true
		ringPart.CanCollide = false
		ringPart.CanQuery = false
		ringPart.CanTouch = false
		ringPart.CastShadow = false
		ringPart.Material = Enum.Material.Neon
		ringPart.Color = RING
		ringPart.Transparency = 1
		ringPart.Size = Vector3.new(1, 1, 1)
		ringPart.Parent = folder

		folder.Parent = camera
		return true
	end

	---Live values straight off the sliders, so the preview moves on the frame you
	---drag one instead of waiting on a change callback.
	---@return table
	function Hitbox.values()
		local Options = ctx.Options

		local function get(name, fallback)
			local option = Options and Options[name]
			if option and type(option.Value) == "number" then
				return option.Value
			end
			return fallback
		end

		return {
			X = get("HB_X", FALLBACK.X),
			Y = get("HB_Y", FALLBACK.Y),
			Z = get("HB_Z", FALLBACK.Z),
			hso = get("HB_HSO", FALLBACK.hso),
			maxDistance = get("HB_MaxDistance", FALLBACK.maxDistance),
		}
	end

	---Which rig the box is drawn on.
	---@return Model?
	function Hitbox.anchor()
		local Options = ctx.Options
		local mode = Options and Options.HitboxAnchor and Options.HitboxAnchor.Value or "Nearest Enemy"
		local character = LocalPlayer.Character

		if mode == "Self" then
			return character
		end

		local best, bestDistance = nil, math.huge

		for _, entity in ipairs(Entities.list()) do
			if entity ~= character and Util.alive(entity) then
				local distance = Util.distance(entity, character)
				if distance and distance < bestDistance then
					best, bestDistance = entity, distance
				end
			end
		end

		-- Nothing alive nearby: fall back to your own rig so there is still a box
		-- to size against, rather than the preview silently vanishing.
		return best or character
	end

	-- Reused every frame instead of allocating a table per RenderStepped.
	local probe = { hitbox = { X = 0, Y = 0, Z = 0 }, hso = 0 }

	local function hideAll()
		if not boxPart then
			return
		end
		boxPart.Transparency = 1
		boxOutline.Visible = false
		ringPart.Transparency = 1
	end

	---Per-frame redraw. Cheap enough to run unconditionally; bails immediately
	---when the toggle is off.
	function Hitbox.step()
		local Toggles = ctx.Toggles
		local on = Toggles and Toggles.ShowHitbox and Toggles.ShowHitbox.Value or false

		if not ensureParts() then
			return
		end

		if not on then
			Hitbox.distance = nil
			Hitbox.inside = false
			return hideAll()
		end

		local anchor = Hitbox.anchor()
		local root = anchor
			and (
				anchor.PrimaryPart
				or anchor:FindFirstChild("HumanoidRootPart")
				or anchor:FindFirstChildWhichIsA("BasePart")
			)

		if not root then
			Hitbox.distance = nil
			Hitbox.inside = false
			return hideAll()
		end

		local values = Hitbox.values()

		-- hso is studs added to each SIDE of the check, so the drawn box grows by
		-- twice that on each axis.
		local pad = values.hso * 2
		boxPart.Size = Vector3.new(values.X + pad, values.Y + pad, values.Z + pad)
		boxPart.CFrame = root.CFrame

		local inside = false
		local Engine = ctx.Engine

		if Engine then
			probe.hitbox.X, probe.hitbox.Y, probe.hitbox.Z = values.X, values.Y, values.Z
			probe.hso = values.hso
			inside = Engine.inHitbox(probe, anchor) == true
		end

		local colour = inside and INSIDE or OUTSIDE
		boxPart.Color = colour
		boxPart.Transparency = 0.8
		boxOutline.Color3 = colour
		boxOutline.Visible = true

		Hitbox.inside = inside
		Hitbox.distance = Util.distance(anchor, LocalPlayer.Character)
		Hitbox.anchorName = anchor.Name

		local ringOn = Toggles and Toggles.ShowMaxDistance and Toggles.ShowMaxDistance.Value or false

		if ringOn and values.maxDistance > 0 then
			-- A cylinder's own axis is local X, so rotate it upright to get a flat
			-- disc on the ground instead of a barrel on its side.
			--
			-- The real max-distance check is a 3D root-to-root magnitude, so this
			-- disc is its ground-plane projection: accurate on level ground, and
			-- slightly generous when the attacker is above or below you.
			ringPart.Size = Vector3.new(0.15, values.maxDistance * 2, values.maxDistance * 2)
			ringPart.CFrame = CFrame.new(root.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ringPart.Transparency = 0.88
		else
			ringPart.Transparency = 1
		end
	end

	---One line for the Builder tab label.
	---@return string
	function Hitbox.status()
		local Toggles = ctx.Toggles

		if not (Toggles and Toggles.ShowHitbox and Toggles.ShowHitbox.Value) then
			return "Preview off"
		end

		if not Hitbox.distance then
			return "No rig to draw on"
		end

		local values = Hitbox.values()

		return string.format(
			"%s | %.1fm | %s | max %dm",
			Hitbox.anchorName or "?",
			Hitbox.distance,
			Hitbox.inside and "INSIDE" or "outside",
			math.floor(values.maxDistance)
		)
	end

	---Push a timing's hitbox into the preview sliders.
	---Called whenever the visualizer paints a new timing, so clicking a logger
	---row draws that animation's box in the world without a second click.
	---@param timing table?
	function Hitbox.adopt(timing)
		local Options = ctx.Options
		if not timing or not Options or not Options.HB_X then
			return
		end

		local hitbox = timing.hitbox
		if type(hitbox) ~= "table" then
			return
		end

		Options.HB_X:SetValue(hitbox.X or FALLBACK.X)
		Options.HB_Y:SetValue(hitbox.Y or FALLBACK.Y)
		Options.HB_Z:SetValue(hitbox.Z or FALLBACK.Z)
		Options.HB_HSO:SetValue(timing.hso or FALLBACK.hso)
		Options.HB_MaxDistance:SetValue(timing.maxDistance or FALLBACK.maxDistance)
	end

	---Tear the preview down. Called from Runtime's unload handler.
	function Hitbox.destroy()
		if folder then
			pcall(function()
				folder:Destroy()
			end)
		end
		folder, boxPart, boxOutline, ringPart = nil, nil, nil, nil
	end

	ctx.Hitbox = Hitbox
	return Hitbox
end
