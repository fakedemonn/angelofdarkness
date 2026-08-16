--[[
	AutoParry - single file build
	Roblox / Luau, executor script.

	GENERATED FILE - do not edit. Edit the modules in src/ and run:
		node build.js

	Run this:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/angelofdarkness/main/roblox-autoparry/AutoParry.lua"))()

	Modules are inlined in dependency order and each is called with one shared
	context table, so ctx.Store, ctx.Engine and friends resolve the same way
	they do under init.lua.
]]

-- Single instance: unload whatever is already running before starting over.
do
	local existing = rawget(getgenv(), "AutoParryContext")
	if existing and existing.Library and not existing.Library.Unloaded then
		pcall(function()
			existing.Library:Unload()
		end)
		task.wait(0.2)
	end
end

local ctx = {}
getgenv().AutoParryContext = ctx


--------------------------------------------------------------------------------
-- src/core/Config.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
			--     settings/                         LinoriaLib UI config
			--     themes/                           LinoriaLib themes
			ctx.ROOT_FOLDER = "AutoParry"
			ctx.TIMINGS_FOLDER = "AutoParry/timings"
			ctx.SETTINGS_FOLDER = "AutoParry/settings"

			ctx.Players = game:GetService("Players")
			ctx.RunService = game:GetService("RunService")
			ctx.HttpService = game:GetService("HttpService")
			ctx.UserInputService = game:GetService("UserInputService")
			ctx.Stats = game:GetService("Stats")
			ctx.Workspace = game:GetService("Workspace")

			ctx.LocalPlayer = ctx.Players.LocalPlayer
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/Config.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/FS.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/FS.lua
			Thin wrapper over the executor filesystem API.

			Every call is pcall'd and every failure is a return value, never a throw, so a
			missing executor function degrades the script instead of killing it. Check
			FS.available before promising the user their timings will persist.
		]]

		return function(ctx)
			local FS = {}

			local w, r, i, mf, isf, lf =
				rawget(getgenv(), "writefile") or writefile,
				rawget(getgenv(), "readfile") or readfile,
				rawget(getgenv(), "isfile") or isfile,
				rawget(getgenv(), "makefolder") or makefolder,
				rawget(getgenv(), "isfolder") or isfolder,
				rawget(getgenv(), "listfiles") or listfiles

			FS.available = (w and r and i and mf and isf and lf) ~= nil

			function FS.write(path, data)
				if not FS.available then
					return false
				end
				return pcall(w, path, data)
			end

			function FS.read(path)
				if not FS.available then
					return nil
				end
				local ok, data = pcall(r, path)
				return ok and data or nil
			end

			function FS.isFile(path)
				if not FS.available then
					return false
				end
				local ok, res = pcall(i, path)
				return ok and res or false
			end

			function FS.isFolder(path)
				if not FS.available then
					return false
				end
				local ok, res = pcall(isf, path)
				return ok and res or false
			end

			function FS.makeFolder(path)
				if not FS.available then
					return false
				end
				if FS.isFolder(path) then
					return true
				end
				return pcall(mf, path)
			end

			---Create a nested path one level at a time.
			---Plenty of executors will not create intermediate folders for you, so
			---writing to "AutoParry/timings/123" fails silently unless we walk it.
			---@param path string
			function FS.makeTree(path)
				local built = nil

				for segment in tostring(path):gmatch("[^/\\]+") do
					built = built and (built .. "/" .. segment) or segment
					FS.makeFolder(built)
				end

				return FS.isFolder(path)
			end

			function FS.list(path)
				if not FS.available or not FS.isFolder(path) then
					return {}
				end
				local ok, res = pcall(lf, path)
				return ok and res or {}
			end

			function FS.delete(path)
				local d = rawget(getgenv(), "delfile") or delfile
				if not d then
					return false
				end
				return pcall(d, path)
			end

			ctx.FS = FS
			return FS
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/FS.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Util.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Util.lua
			Small pure helpers. No state, no dependencies.
		]]

		return function(ctx)
			local Util = {}

			---Round a number to n decimal places.
			function Util.round(n, places)
				local mult = 10 ^ (places or 0)
				return math.floor(n * mult + 0.5) / mult
			end

			---Strip an AnimationId down to its numeric part for display.
			function Util.shortId(animationId)
				return (tostring(animationId):gsub("rbxassetid://", ""):gsub("http://www.roblox.com/asset/%?id=", ""))
			end

			---Safe distance between two models.
			function Util.distance(a, b)
				local ra = a and a:FindFirstChild("HumanoidRootPart")
				local rb = b and b:FindFirstChild("HumanoidRootPart")
				if not ra or not rb then
					return nil
				end
				return (ra.Position - rb.Position).Magnitude
			end

			---Dot product of A's look vector against the direction to B. 1 = facing directly.
			function Util.facing(a, b)
				local ra = a and a:FindFirstChild("HumanoidRootPart")
				local rb = b and b:FindFirstChild("HumanoidRootPart")
				if not ra or not rb then
					return nil
				end
				local dir = (rb.Position - ra.Position)
				if dir.Magnitude < 0.001 then
					return 1
				end
				return ra.CFrame.LookVector:Dot(dir.Unit)
			end

			---Is this model alive?
			function Util.alive(model)
				local hum = model and model:FindFirstChildWhichIsA("Humanoid")
				return hum ~= nil and hum.Health > 0
			end

			ctx.Util = Util
			return Util
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/Util.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Input.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Input.lua
			Keyboard output.

			VirtualInputManager is preferred because it goes through Roblox's own input
			pipeline, so the game sees a normal key event. keypress/keyrelease is the
			fallback for executors that block VIM; it needs Windows virtual key codes,
			which is why the VK table exists.
		]]

		return function(ctx)
			local Input = {}

			-- Windows virtual key codes for the keys we let the user bind.
			local VK = {
				A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
				H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
				O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
				V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,
				One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34, Five = 0x35,
				Space = 0x20, LeftShift = 0xA0, LeftControl = 0xA2, LeftAlt = 0xA4,
			}

			local vim = nil
			pcall(function()
				vim = game:GetService("VirtualInputManager")
			end)

			local kp = rawget(getgenv(), "keypress") or keypress
			local kr = rawget(getgenv(), "keyrelease") or keyrelease

			Input.keys = {}
			for name in pairs(VK) do
				table.insert(Input.keys, name)
			end
			table.sort(Input.keys)

			Input.available = (vim ~= nil) or (kp ~= nil and kr ~= nil)

			---Press a key down.
			---@param keyName string
			function Input.down(keyName)
				local enum = Enum.KeyCode[keyName]
				if vim then
					pcall(function()
						vim:SendKeyEvent(true, enum, false, game)
					end)
					return
				end
				if kp and VK[keyName] then
					pcall(kp, VK[keyName])
				end
			end

			---Release a key.
			---@param keyName string
			function Input.up(keyName)
				local enum = Enum.KeyCode[keyName]
				if vim then
					pcall(function()
						vim:SendKeyEvent(false, enum, false, game)
					end)
					return
				end
				if kr and VK[keyName] then
					pcall(kr, VK[keyName])
				end
			end

			---Press and hold a key for a duration, then release.
			---@param keyName string
			---@param holdSeconds number
			function Input.tap(keyName, holdSeconds)
				Input.down(keyName)
				task.delay(math.max(holdSeconds, 0.01), function()
					Input.up(keyName)
				end)
			end

			ctx.Input = Input
			return Input
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/Input.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Latency.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Latency.lua
			Network timing.

			Stats "Data Ping" is a ROUND TRIP measurement, not one-way. Getting this
			backwards is the single most common way an auto parry ends up firing at
			double the intended offset, so the two functions are named to make the
			distinction impossible to miss at the call site.
		]]

		return function(ctx)
			local Latency = {}

			---Round trip time in seconds.
			function Latency.rtt()
				local network = ctx.Stats:FindFirstChild("Network")
				local item = network and network:FindFirstChild("ServerStatsItem")
				local ping = item and item:FindFirstChild("Data Ping")
				if not ping then
					return 0
				end
				local ok, value = pcall(function()
					return ping:GetValue()
				end)
				return ok and (value / 1000) or 0
			end

			---One-way delay in seconds.
			function Latency.half()
				return math.max(Latency.rtt() / 2, 0)
			end

			ctx.Latency = Latency
			return Latency
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/Latency.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/State.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/State.lua
			Runtime counters and the single gate that decides whether a parry may fire.

			Every reason to refuse lives here rather than being scattered through the
			engine, so "why didn't it parry" has exactly one place to look.
		]]

		return function(ctx)
			local LocalPlayer, UserInputService = ctx.LocalPlayer, ctx.UserInputService

			local State = {
				lastParry = 0,
				parries = 0,
				misses = 0,
				pending = 0,
			}

			---Are we allowed to fire a parry at this instant?
			---@return boolean, string
			function State.canParry()
				local Toggles, Options = ctx.Toggles, ctx.Options

				if not Toggles.AutoParry or not Toggles.AutoParry.Value then
					return false, "disabled"
				end

				local character = LocalPlayer.Character
				if not character then
					return false, "no character"
				end

				local humanoid = character:FindFirstChildWhichIsA("Humanoid")
				if not humanoid or humanoid.Health <= 0 then
					return false, "dead"
				end

				local cooldown = (Options.ParryCooldown and Options.ParryCooldown.Value or 60) / 1000
				if os.clock() - State.lastParry < cooldown then
					return false, "cooldown"
				end

				if Toggles.DisableWhileHolding and Toggles.DisableWhileHolding.Value then
					local key = Options.ParryKey and Options.ParryKey.Value or "F"
					local ok, held = pcall(function()
						return UserInputService:IsKeyDown(Enum.KeyCode[key])
					end)
					if ok and held then
						return false, "key held manually"
					end
				end

				return true, "ok"
			end

			ctx.State = State
			return State
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/State.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/core/Notify.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			core/Notify.lua
			One notification entry point.

			Deliberately safe to call before the UI exists: modules further down load
			before ui/Library.lua, and a notification during boot should be a no-op
			rather than an error.
		]]

		return function(ctx)
			local function notify(text, duration)
				local Library = ctx.Library
				if Library and Library.Notify then
					Library:Notify(text, duration or 2)
				end
			end

			ctx.notify = notify
			return notify
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/core/Notify.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Store.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			features/Store.lua
			The timing database.

			One folder per PlaceId under AutoParry/timings/, so a build for one game can
			never bleed into another. Timings are written the instant they are created
			rather than on a timer, because the whole build-as-you-play workflow falls
			apart if a crash costs you the last twenty minutes of fighting.
		]]

		return function(ctx)
			local FS, Util, HttpService = ctx.FS, ctx.Util, ctx.HttpService

			local Store = {
				timings = {},
				configName = "default",
				dirty = false,
			}

			Store.placeFolder = ctx.TIMINGS_FOLDER .. "/" .. tostring(game.PlaceId)

			---Ensure the folder tree exists.
			function Store.init()
				FS.makeTree(Store.placeFolder)
			end

			---Path of a named config.
			function Store.path(name)
				return Store.placeFolder .. "/" .. tostring(name) .. ".json"
			end

			---Build a fresh timing from an observed animation track.
			---@param animationId string
			---@param trackLength number
			---@param entityName string
			---@return table
			function Store.template(animationId, trackLength, entityName)
				local length = (trackLength and trackLength > 0) and trackLength or 1.0
				return {
					id = animationId,
					name = entityName or "Unnamed",
					-- Where in the animation the hit lands, in milliseconds. 60% of the
					-- animation is a workable first guess for most swing animations; the
					-- editor exists so you can dial it in from there.
					delay = Util.round(length * 1000 * 0.6, 0),
					length = Util.round(length, 3),
					minDistance = 0,
					maxDistance = 85,
					holdTime = 120,
					enabled = false,
					-- Set true for attacks whose animation stops before the hit lands, so
					-- the fire-time "is it still playing" check is skipped.
					ignoreEnd = false,
					note = "",

					-- Hitbox gate, measured in the attacker's local space, so a wide
					-- horizontal sweep and a narrow forward thrust do not have to share
					-- one distance number.
					hitbox = { X = 11, Y = 10, Z = 30.5 },
					-- Hitbox size offset: studs added to every axis before the check.
					hso = 3,

					-- Multi-hit attacks: parry this many times, this far apart, in seconds.
					repeatCount = 1,
					repeatDelay = 0.35,

					-- None / Left / Right / Back / Forward, held alongside the parry key.
					dodgeDir = "None",
				}
			end

			---Fill in fields a config saved by an older build will not have.
			---Runs on every load so upgrading never means rebuilding a database by hand.
			---@param timing table
			---@return table
			function Store.normalise(timing)
				local blank = Store.template(timing.id or "", timing.length or 1, timing.name)

				for key, value in pairs(blank) do
					if timing[key] == nil then
						timing[key] = value
					end
				end

				-- Hitbox is nested, so a shallow fill leaves half of it missing.
				if type(timing.hitbox) ~= "table" then
					timing.hitbox = blank.hitbox
				else
					for _, axis in ipairs({ "X", "Y", "Z" }) do
						if type(timing.hitbox[axis]) ~= "number" then
							timing.hitbox[axis] = blank.hitbox[axis]
						end
					end
				end

				return timing
			end

			---Look up a timing.
			function Store.get(animationId)
				return Store.timings[animationId]
			end

			---Insert a timing and write to disk right away.
			---@param timing table
			---@param autoSave boolean
			function Store.create(timing, autoSave)
				Store.timings[timing.id] = timing
				Store.dirty = true
				if autoSave then
					Store.save(Store.configName)
				end
				return timing
			end

			---Remove a timing.
			function Store.remove(animationId)
				Store.timings[animationId] = nil
				Store.dirty = true
			end

			---Serialize the whole database to a config file.
			function Store.save(name)
				Store.init()

				local payload = {
					version = ctx.VERSION,
					placeId = game.PlaceId,
					timings = {},
				}

				for id, timing in pairs(Store.timings) do
					payload.timings[id] = timing
				end

				local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
				if not ok then
					return false, "encode failed"
				end

				local written = FS.write(Store.path(name), encoded)
				if written then
					Store.dirty = false
				end
				return written
			end

			---Replace the in-memory database from a JSON string.
			---Split out of Store.load so a file on disk and a payload pulled off the repo
			---go through exactly one parsing and normalising path.
			---@param raw string
			---@return boolean, string?
			function Store.adopt(raw)
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
				if not ok or type(decoded) ~= "table" or type(decoded.timings) ~= "table" then
					return false, "corrupt config"
				end

				Store.timings = {}
				for id, timing in pairs(decoded.timings) do
					timing.id = timing.id or id
					Store.timings[id] = Store.normalise(timing)
				end

				return true
			end

			---Load a config file, replacing the in-memory database.
			function Store.load(name)
				local raw = FS.read(Store.path(name))
				if not raw then
					return false, "no such config"
				end

				local ok, err = Store.adopt(raw)
				if not ok then
					return false, err
				end

				Store.configName = name
				Store.dirty = false
				return true
			end

			---Pull the database this script ships with for the current place.
			---Nothing is written to disk here; the caller decides whether to keep it.
			---@return boolean, string?
			function Store.fetch()
				local url = ctx.DATA_REPO .. "timings/" .. tostring(game.PlaceId) .. "/default.json"

				-- A place with no bundled database gets a 404, which executors surface
				-- either as a thrown error or as an HTML body. pcall covers the first,
				-- and Store.adopt failing to decode it covers the second.
				local got, body = pcall(game.HttpGet, game, url)
				if not got or type(body) ~= "string" or body == "" then
					return false, "no bundled timings for this place"
				end

				local ok, err = Store.adopt(body)
				if not ok then
					return false, err
				end

				Store.configName = "default"
				Store.dirty = true
				return true
			end

			---How many timings are loaded.
			function Store.count()
				local n = 0
				for _ in pairs(Store.timings) do
					n = n + 1
				end
				return n
			end

			---List config names for this place.
			function Store.list()
				local out = {}
				for _, file in ipairs(FS.list(Store.placeFolder)) do
					local name = tostring(file):match("([^/\\]+)%.json$")
					if name then
						table.insert(out, name)
					end
				end
				table.sort(out)
				return out
			end

			---Sorted display list of timings for the dropdown.
			function Store.display()
				local out = {}
				for id, timing in pairs(Store.timings) do
					table.insert(
						out,
						string.format("%s [%s]%s", timing.name, Util.shortId(id), timing.enabled and "" or " (off)")
					)
				end
				table.sort(out)
				return out
			end

			---Resolve a display string back to its timing.
			function Store.fromDisplay(display)
				if type(display) ~= "string" then
					return nil
				end

				local short = display:match("%[(%d+)%]")
				if not short then
					return nil
				end

				for id, timing in pairs(Store.timings) do
					if Util.shortId(id) == short then
						return timing
					end
				end
				return nil
			end

			ctx.Store = Store
			return Store
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/features/Store.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Log.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/features/Log.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Entities.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/features/Entities.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Engine.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			features/Engine.lua
			The auto parry itself.

			Timing model
			------------
			Stats "Data Ping" is a round trip. The attacker's animation started roughly
			one one-way-delay ago, and our keypress needs another one-way-delay to reach
			the server, so subtracting the FULL rtt puts the input on the server at the
			moment the hit lands:

			    wait = (delay / 1000) - (rtt * compensation) - offset + jitter

			Everything is revalidated inside the delayed callback rather than trusted
			from schedule time, because a wind-up is long enough for the target to die,
			despawn, or walk out of range.
		]]

		return function(ctx)
			local Util, Input, Latency = ctx.Util, ctx.Input, ctx.Latency
			local Store, Log, Entities, State = ctx.Store, ctx.Log, ctx.Entities, ctx.State
			local LocalPlayer, notify = ctx.LocalPlayer, ctx.notify

			local Engine = {}

			local DODGE_KEYS = { Left = "A", Right = "D", Back = "S", Forward = "W" }

			---Debug notification, only when the toggle is on.
			local function debug(fmt, ...)
				local Toggles = ctx.Toggles
				if Toggles.ShowDebug and Toggles.ShowDebug.Value then
					notify(string.format(fmt, ...), 2)
				end
			end

			---Is the player inside this timing's hitbox?
			---Measured in the attacker's local space, so a wide horizontal sweep and a
			---narrow forward thrust are not forced to share one distance number.
			---@param timing table
			---@param entity Model
			---@return boolean
			function Engine.inHitbox(timing, entity)
				local hitbox = timing.hitbox
				if type(hitbox) ~= "table" then
					return true
				end

				local root = entity.PrimaryPart
					or entity:FindFirstChild("HumanoidRootPart")
					or entity:FindFirstChildWhichIsA("BasePart")

				local character = LocalPlayer.Character
				local ourRoot = character and character:FindFirstChild("HumanoidRootPart")

				if not root or not ourRoot then
					return true
				end

				-- Into the attacker's frame: X is their right, Y up, Z forward/back.
				local localPoint = root.CFrame:PointToObjectSpace(ourRoot.Position)
				local pad = timing.hso or 0

				return math.abs(localPoint.X) <= (hitbox.X / 2) + pad
					and math.abs(localPoint.Y) <= (hitbox.Y / 2) + pad
					and math.abs(localPoint.Z) <= (hitbox.Z / 2) + pad
			end

			---Fire the parry input once.
			---@param timing table
			function Engine.fire(timing)
				local Toggles, Options = ctx.Toggles, ctx.Options

				local ok, reason = State.canParry()
				if not ok then
					debug("[skip] %s - %s", timing.name, reason)
					return
				end

				local key = Options.ParryKey and Options.ParryKey.Value or "F"
				local hold = (timing.holdTime or Options.HoldTime.Value or 120) / 1000

				-- Directional dodge: hold the movement key across the parry so the game
				-- reads a directional roll rather than a neutral block.
				local dodge = DODGE_KEYS[timing.dodgeDir or "None"]
				if dodge then
					Input.down(dodge)
					task.delay(hold + 0.02, function()
						Input.up(dodge)
					end)
				end

				Input.tap(key, hold)

				State.lastParry = os.clock()
				State.parries = State.parries + 1

				if Toggles.NotifyOnParry and Toggles.NotifyOnParry.Value then
					notify(string.format("Parried %s (%dms)", timing.name, timing.delay), 1.5)
				end
			end

			---Fire, then repeat for multi-hit attacks.
			---@param timing table
			function Engine.fireSequence(timing)
				Engine.fire(timing)

				local count = math.max(math.floor(timing.repeatCount or 1), 1)
				if count <= 1 then
					return
				end

				local gap = math.max(timing.repeatDelay or 0.35, 0.05)

				task.spawn(function()
					for _ = 2, count do
						task.wait(gap)
						-- Cooldown would otherwise eat every follow-up hit in the chain.
						State.lastParry = 0
						Engine.fire(timing)
					end
				end)
			end

			---Schedule a parry for a track that just started.
			---@param timing table
			---@param entity Model
			---@param track AnimationTrack
			function Engine.schedule(timing, entity, track)
				local Toggles, Options = ctx.Toggles, ctx.Options

				-- Humanised miss.
				local missChance = Options.MissChance and Options.MissChance.Value or 0
				if missChance > 0 and Random.new():NextNumber(0, 100) <= missChance then
					State.misses = State.misses + 1
					debug("[miss] %s (intentional)", timing.name)
					return
				end

				local compensation = (Options.PingCompensation and Options.PingCompensation.Value or 100) / 100
				local offset = (Options.ParryOffset and Options.ParryOffset.Value or 0) / 1000

				local jitter = 0
				if Toggles.RandomizeOffset and Toggles.RandomizeOffset.Value then
					local range = (Options.RandomRange and Options.RandomRange.Value or 20) / 1000
					jitter = Random.new():NextNumber(-range, range)
				end

				local wait = (timing.delay / 1000) - (Latency.rtt() * compensation) - offset + jitter
				wait = math.max(wait, 0)

				State.pending = State.pending + 1

				task.delay(wait, function()
					State.pending = math.max(State.pending - 1, 0)

					-- Revalidate at fire time; a lot can change during the wind-up.
					if not track.IsPlaying and not (timing.ignoreEnd == true) then
						debug("[skip] %s - animation stopped", timing.name)
						return
					end

					if not Entities.valid(entity) then
						return
					end

					local distance = Util.distance(entity, LocalPlayer.Character)
					if not distance then
						return
					end

					if distance < (timing.minDistance or 0) then
						return
					end

					if timing.maxDistance and timing.maxDistance > 0 and distance > timing.maxDistance then
						return
					end

					if not Engine.inHitbox(timing, entity) then
						debug("[skip] %s - outside hitbox", timing.name)
						return
					end

					Engine.fireSequence(timing)
				end)
			end

			---Handle one animation starting on one entity.
			---@param entity Model
			---@param track AnimationTrack
			function Engine.onAnimation(entity, track)
				local Toggles, Options = ctx.Toggles, ctx.Options

				if not track.Animation then
					return
				end

				local animationId = tostring(track.Animation.AnimationId)
				if animationId == "" then
					return
				end

				local character = LocalPlayer.Character
				if not character or entity == character then
					return
				end

				local distance = Util.distance(entity, character)
				if not distance then
					return
				end

				local timing = Store.get(animationId)

				-- Logging gate.
				local logMin = Options.LogMinDistance and Options.LogMinDistance.Value or 0
				local logMax = Options.LogMaxDistance and Options.LogMaxDistance.Value or 0
				local inLogRange = distance >= logMin and (logMax <= 0 or distance <= logMax)
				local onlyUnknown = Toggles.LogOnlyUnknown and Toggles.LogOnlyUnknown.Value

				if inLogRange and (not onlyUnknown or not timing) then
					Log.push({
						id = animationId,
						-- Track name is what the game's own animator calls it. Usually far
						-- more readable than the asset id when hunting one specific move.
						animName = (track.Name ~= "" and track.Name) or "Animation",
						assetId = animationId:match("(%d+)") or "?",
						time = os.date("%H:%M:%S"),
						entity = entity.Name,
						model = entity,
						distance = Util.round(distance, 1),
						length = Util.round(track.Length, 3),
						speed = Util.round(track.Speed, 2),
						priority = track.Priority.Name,
						known = timing ~= nil,
						ping = math.floor(Latency.rtt() * 1000),
						clock = os.clock(),
					})

					-- Always record. Gating this on the visualizer being open meant you had
					-- to predict which animation you wanted to inspect before it played.
					Log.record(animationId, entity, track)
				end

				-- Auto-create a stub for anything we have never seen.
				if not timing and Toggles.AutoCreateTimings and Toggles.AutoCreateTimings.Value then
					if Entities.valid(entity) and inLogRange then
						timing = Store.template(animationId, track.Length, entity.Name)
						timing.enabled = Toggles.AutoEnableNewTimings and Toggles.AutoEnableNewTimings.Value or false

						-- Written to disk the instant it is created, not on a timer.
						Store.create(timing, Toggles.AutoSaveOnCreate and Toggles.AutoSaveOnCreate.Value or false)

						if Toggles.NotifyOnNewTiming and Toggles.NotifyOnNewTiming.Value then
							notify(string.format("New timing: %s [%s]", timing.name, Util.shortId(animationId)), 3)
						end
					end
				end

				if not timing or not timing.enabled then
					return
				end

				if not Entities.valid(entity) then
					return
				end

				if distance < (timing.minDistance or 0) then
					return
				end

				if timing.maxDistance and timing.maxDistance > 0 and distance > timing.maxDistance then
					return
				end

				Engine.schedule(timing, entity, track)
			end

			ctx.Engine = Engine
			return Engine
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/features/Engine.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Hitbox.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/features/Hitbox.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/features/Hooks.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/features/Hooks.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/Library.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/Library.lua
			Loads LinoriaLib and builds the window + tabs.

			This is the first module that publishes ctx.Toggles / ctx.Options. Every
			module loaded before this one reads those two through ctx at call time
			rather than at load time, which is why none of them capture them locally.
		]]

		return function(ctx)
			local Library = loadstring(game:HttpGet(ctx.LIB_REPO .. "Library.lua"))()
			local ThemeManager = loadstring(game:HttpGet(ctx.LIB_REPO .. "addons/ThemeManager.lua"))()
			local SaveManager = loadstring(game:HttpGet(ctx.LIB_REPO .. "addons/SaveManager.lua"))()

			local Window = Library:CreateWindow({
				Title = string.format("AutoParry v%s", ctx.VERSION),
				Center = true,
				AutoShow = true,
				TabPadding = 8,
				MenuFadeTime = 0.2,
			})

			local Tabs = {
				Main = Window:AddTab("Main"),
				Builder = Window:AddTab("Builder"),
				["UI Settings"] = Window:AddTab("UI Settings"),
			}

			ctx.Library = Library
			ctx.ThemeManager = ThemeManager
			ctx.SaveManager = SaveManager
			ctx.Window = Window
			ctx.Tabs = Tabs

			-- Linoria publishes these as globals when Library.lua runs. Everything below
			-- this module reads ctx.Toggles / ctx.Options, so resolve them once here and
			-- fail loudly rather than letting a nil index surface ten modules later.
			local env = getgenv and getgenv() or {}
			ctx.Toggles = env.Toggles or Toggles
			ctx.Options = env.Options or Options

			if not ctx.Toggles or not ctx.Options then
				error("[AutoParry] LinoriaLib did not publish Toggles/Options", 0)
			end

			return Library
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/Library.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/MainTab.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/MainTab.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/BuilderTab.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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

			-- Its own groupbox on purpose: these sliders drive the drawing only. Nothing
			-- here touches a saved timing until you press Apply, so you can drag them
			-- around mid-fight without corrupting a tuned entry.
			local HitboxBox = Tabs.Builder:AddLeftGroupbox("Hitbox Preview")

			HitboxBox:AddToggle("ShowHitbox", {
				Text = "Show Hitbox",
				Default = false,
				Tooltip = "Green while you are inside the gate, red while you are not",
			}):AddKeyPicker("HitboxKey", {
				Default = "N/A",
				SyncToggleState = true,
				Mode = "Toggle",
				Text = "Hitbox Preview",
			})

			HitboxBox:AddDropdown("HitboxAnchor", {
				Values = { "Nearest Enemy", "Self" },
				Default = "Nearest Enemy",
				Text = "Draw On",
				Tooltip = "The box is measured in the attacker's frame, so it is drawn on them",
			})

			HitboxBox:AddSlider("HB_X", {
				Text = "Hitbox X",
				Default = 11,
				Min = 0,
				Max = 120,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Attacker's left/right width",
			})

			HitboxBox:AddSlider("HB_Y", {
				Text = "Hitbox Y",
				Default = 10,
				Min = 0,
				Max = 120,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Height",
			})

			HitboxBox:AddSlider("HB_Z", {
				Text = "Hitbox Z",
				Default = 30.5,
				Min = 0,
				Max = 250,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Attacker's forward/back reach",
			})

			HitboxBox:AddSlider("HB_HSO", {
				Text = "HSO",
				Default = 3,
				Min = 0,
				Max = 40,
				Rounding = 1,
				Suffix = " studs",
				Tooltip = "Studs added to every side before the check",
			})

			HitboxBox:AddToggle("ShowMaxDistance", {
				Text = "Show Max Distance",
				Default = false,
				Tooltip = "Flat ring at the distance cut-off",
			})

			HitboxBox:AddSlider("HB_MaxDistance", {
				Text = "Max Distance",
				Default = 85,
				Min = 0,
				Max = 400,
				Rounding = 0,
				Suffix = "m",
			})

			local HitboxLabel = HitboxBox:AddLabel("Preview off", true)

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
			ctx.HitboxBox = HitboxBox
			ctx.HitboxLabel = HitboxLabel
			ctx.timingList = timingList
			ctx.configList = configList
			ctx.StoreLabel = StoreLabel

			return BuilderBox
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/BuilderTab.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/LoggerWindow.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/LoggerWindow.lua
			The Info Logger: Time | Animation | ID | Enemy | Dist | Status.

			Status is resolved live from the store on every refresh rather than cached
			on the log entry, so a row that appeared as NEW flips to KNOWN the moment a
			timing exists for it, and to IN AP the moment that timing is enabled.

			Clicking a row is the whole gesture: it selects, opens the visualizer if it
			is closed, and loads the animation. Loads before ui/VisualizerWindow.lua, so
			it reaches the visualizer through ctx at click time.
		]]

		return function(ctx)
			local Library, Store, Log, LocalPlayer = ctx.Library, ctx.Store, ctx.Log, ctx.LocalPlayer

			local LoggerGui = {}

			local screen = Instance.new("ScreenGui")
			screen.Name = "AP_InfoLogger"
			screen.ResetOnSpawn = false
			screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			screen.DisplayOrder = 999
			screen.Enabled = false

			pcall(function()
				if syn and syn.protect_gui then
					syn.protect_gui(screen)
				end
				screen.Parent = gethui and gethui() or game:GetService("CoreGui")
			end)

			if not screen.Parent then
				screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
			end

			local outer = Instance.new("Frame")
			outer.Name = "Outer"
			outer.BackgroundColor3 = Color3.new(0, 0, 0)
			outer.BorderSizePixel = 0
			outer.Position = UDim2.new(0, 20, 0, 200)
			outer.Size = UDim2.new(0, 470, 0, 280)
			outer.Parent = screen

			local inner = Instance.new("Frame")
			inner.Name = "Inner"
			inner.BackgroundColor3 = Library.MainColor
			inner.BorderColor3 = Library.OutlineColor
			inner.BorderMode = Enum.BorderMode.Inset
			inner.Size = UDim2.new(1, -2, 1, -2)
			inner.Position = UDim2.new(0, 1, 0, 1)
			inner.Parent = outer

			local accent = Instance.new("Frame")
			accent.BackgroundColor3 = Library.AccentColor
			accent.BorderSizePixel = 0
			accent.Size = UDim2.new(1, 0, 0, 2)
			accent.Parent = inner

			local title = Instance.new("TextLabel")
			title.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			title.TextColor3 = Library.AccentColor
			title.Text = "Info Logger"
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextSize = 15
			title.Position = UDim2.new(0, 6, 0, 4)
			title.Size = UDim2.new(0, 110, 0, 18)
			title.Parent = inner

			local countLabel = Instance.new("TextLabel")
			countLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			countLabel.TextColor3 = Library.FontColor
			countLabel.Text = "0 entries"
			countLabel.BackgroundTransparency = 1
			countLabel.TextXAlignment = Enum.TextXAlignment.Left
			countLabel.TextSize = 13
			countLabel.Position = UDim2.new(0, 120, 0, 5)
			countLabel.Size = UDim2.new(0, 120, 0, 16)
			countLabel.Parent = inner

			local clearButton = Instance.new("TextButton")
			clearButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			clearButton.TextColor3 = Library.FontColor
			clearButton.BackgroundColor3 = Library.BackgroundColor
			clearButton.BorderColor3 = Library.OutlineColor
			clearButton.AutoButtonColor = false
			clearButton.Text = "Clear"
			clearButton.TextSize = 12
			clearButton.Position = UDim2.new(1, -56, 0, 5)
			clearButton.Size = UDim2.new(0, 50, 0, 16)
			clearButton.Parent = inner
			Library:AddToRegistry(clearButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			-- Column geometry shared by the header and every row, so they cannot drift.
			local COLUMNS = {
				{ key = "time", title = "Time", x = 0, w = 58 },
				{ key = "animName", title = "Animation", x = 60, w = 110 },
				{ key = "assetId", title = "ID", x = 172, w = 96 },
				{ key = "entity", title = "Enemy", x = 270, w = 96 },
				{ key = "dist", title = "Dist", x = 368, w = 40 },
				{ key = "status", title = "Status", x = 410, w = 46 },
			}

			local header = Instance.new("Frame")
			header.BackgroundColor3 = Library.BackgroundColor
			header.BorderSizePixel = 0
			header.Position = UDim2.new(0, 4, 0, 24)
			header.Size = UDim2.new(1, -8, 0, 16)
			header.Parent = inner
			Library:AddToRegistry(header, { BackgroundColor3 = "BackgroundColor" }, true)

			for _, column in ipairs(COLUMNS) do
				local label = Instance.new("TextLabel")
				label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				label.TextColor3 = Library.AccentColor
				label.Text = column.title
				label.BackgroundTransparency = 1
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextSize = 12
				label.Position = UDim2.new(0, column.x + 4, 0, 0)
				label.Size = UDim2.new(0, column.w, 1, 0)
				label.Parent = header
				Library:AddToRegistry(label, { TextColor3 = "AccentColor" }, true)
			end

			local list = Instance.new("ScrollingFrame")
			list.BackgroundTransparency = 1
			list.BorderSizePixel = 0
			list.Position = UDim2.new(0, 4, 0, 42)
			list.Size = UDim2.new(1, -8, 1, -46)
			list.ScrollBarThickness = 3
			list.ScrollBarImageColor3 = Library.AccentColor
			list.CanvasSize = UDim2.new()
			list.Parent = inner

			local layout = Instance.new("UIListLayout")
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 1)
			layout.Parent = list

			layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
			end)

			Library:MakeDraggable(outer)

			Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
			Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
			Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)

			local rows = {}

			local STATUS_NEW = Color3.fromRGB(200, 200, 200)
			local STATUS_KNOWN = Color3.fromRGB(255, 190, 70)
			local STATUS_ACTIVE = Color3.fromRGB(90, 230, 120)

			---Status is read live from the store, never cached on the entry, so a row
			---logged as NEW flips to IN AP the moment you save a timing for it.
			---@param animationId string
			---@return string, Color3
			local function statusOf(animationId)
				local timing = Store.get(animationId)
				if not timing then
					return "NEW", STATUS_NEW
				end
				if timing.enabled then
					return "IN AP", STATUS_ACTIVE
				end
				return "KNOWN", STATUS_KNOWN
			end

			---Set window visibility.
			function LoggerGui.visible(state)
				screen.Enabled = state
			end

			clearButton.MouseButton1Click:Connect(function()
				Log.clear()
				for _, row in ipairs(rows) do
					row.Frame.Visible = false
				end
				countLabel.Text = "0 entries"
			end)

			---Build one row: a click target plus one label per column.
			local function makeRow(index)
				local frame = Instance.new("TextButton")
				frame.BackgroundColor3 = Library.BackgroundColor
				frame.BackgroundTransparency = 1
				frame.BorderSizePixel = 0
				frame.AutoButtonColor = false
				frame.Text = ""
				frame.Size = UDim2.new(1, 0, 0, 16)
				frame.LayoutOrder = index
				frame.Parent = list

				local cells = {}
				for _, column in ipairs(COLUMNS) do
					local label = Instance.new("TextLabel")
					label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
					label.TextColor3 = Library.FontColor
					label.BackgroundTransparency = 1
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextTruncate = Enum.TextTruncate.AtEnd
					label.TextSize = 12
					label.Text = ""
					label.Position = UDim2.new(0, column.x + 4, 0, 0)
					label.Size = UDim2.new(0, column.w, 1, 0)
					label.Parent = frame
					cells[column.key] = label
				end

				local row = { Frame = frame, Cells = cells }
				rows[index] = row

				frame.MouseButton1Click:Connect(function()
					local Toggles = ctx.Toggles
					local Visualizer = ctx.Visualizer

					Log.selected = frame:GetAttribute("AnimationId")
					if not Log.selected then
						return
					end

					-- Clicking a row is the whole gesture: open the visualizer if it is
					-- closed, then load. Otherwise the click looks dead.
					if Visualizer and Visualizer.load then
						if Toggles.ShowAnimationVisualizer and not Toggles.ShowAnimationVisualizer.Value then
							Toggles.ShowAnimationVisualizer:SetValue(true)
						end
						Visualizer.load(Log.selected)
					end

					LoggerGui.refresh()
				end)

				frame.MouseEnter:Connect(function()
					if frame:GetAttribute("AnimationId") ~= Log.selected then
						frame.BackgroundTransparency = 0.7
					end
				end)

				frame.MouseLeave:Connect(function()
					if frame:GetAttribute("AnimationId") ~= Log.selected then
						frame.BackgroundTransparency = 1
					end
				end)

				return row
			end

			---Rebuild the row list from the log.
			function LoggerGui.refresh()
				if not screen.Enabled then
					return
				end

				countLabel.Text = string.format("%d %s", #Log.entries, #Log.entries == 1 and "entry" or "entries")

				for index, entry in ipairs(Log.entries) do
					local row = rows[index] or makeRow(index)
					local frame, cells = row.Frame, row.Cells

					frame.LayoutOrder = index
					frame.Visible = true
					frame:SetAttribute("AnimationId", entry.id)

					local selected = entry.id == Log.selected
					frame.BackgroundTransparency = selected and 0.4 or 1
					frame.BackgroundColor3 = selected and Library.AccentColor or Library.BackgroundColor

					local statusText, statusColor = statusOf(entry.id)

					cells.time.Text = entry.time or "--:--:--"
					cells.animName.Text = entry.animName or "Animation"
					cells.assetId.Text = entry.assetId or "?"
					cells.entity.Text = entry.entity or "?"
					cells.dist.Text = string.format("%.0f", entry.distance or 0)
					cells.status.Text = statusText
					cells.status.TextColor3 = statusColor

					-- Tint the whole row too, so a screen full of entries reads at a glance
					-- instead of forcing you to scan the last column.
					local bodyColor = statusText == "NEW" and Library.FontColor or statusColor
					cells.time.TextColor3 = Library.FontColor
					cells.animName.TextColor3 = bodyColor
					cells.assetId.TextColor3 = bodyColor
					cells.entity.TextColor3 = Library.FontColor
					cells.dist.TextColor3 = Library.FontColor
				end

				for index = #Log.entries + 1, #rows do
					rows[index].Frame.Visible = false
				end
			end

			ctx.LoggerGui = LoggerGui
			return LoggerGui
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/LoggerWindow.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/VisualizerWindow.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/VisualizerWindow.lua
			Animation Visualizer & Editor.

			Left half is a ViewportFrame playing the animation on a cloned rig, with a
			scrub bar and a red marker at the current parry delay. Right half is the
			Quick Edit Timing panel, which writes straight into features/Store.lua and
			persists on Save & Apply.

			The panel talks in seconds because that is how animations read; the store
			stays in milliseconds because that is what the scheduler needs. Conversion
			happens in readEditor/syncEditor and nowhere else.
		]]

		return function(ctx)
			local Library, Store, Log, Util = ctx.Library, ctx.Store, ctx.Log, ctx.Util
			local Entities, LoggerGui, notify = ctx.Entities, ctx.LoggerGui, ctx.notify
			local LocalPlayer, UserInputService, RunService = ctx.LocalPlayer, ctx.UserInputService, ctx.RunService

			local Visualizer = {}

			-- Published immediately: the logger's row click reads ctx.Visualizer, and
			-- nothing below this line needs to have run for that lookup to resolve.
			ctx.Visualizer = Visualizer

			local screen = Instance.new("ScreenGui")
			screen.Name = "AP_Visualizer"
			screen.ResetOnSpawn = false
			screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			screen.DisplayOrder = 998
			screen.Enabled = false

			pcall(function()
				if syn and syn.protect_gui then
					syn.protect_gui(screen)
				end
				screen.Parent = gethui and gethui() or game:GetService("CoreGui")
			end)

			if not screen.Parent then
				screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
			end

			local outer = Instance.new("Frame")
			outer.BackgroundColor3 = Color3.new(0, 0, 0)
			outer.BorderSizePixel = 0
			outer.Position = UDim2.new(0, 510, 0, 200)
			outer.Size = UDim2.new(0, 570, 0, 314)
			outer.Parent = screen

			local inner = Instance.new("Frame")
			inner.BackgroundColor3 = Library.MainColor
			inner.BorderColor3 = Library.OutlineColor
			inner.BorderMode = Enum.BorderMode.Inset
			inner.Size = UDim2.new(1, -2, 1, -2)
			inner.Position = UDim2.new(0, 1, 0, 1)
			inner.Parent = outer

			local accent = Instance.new("Frame")
			accent.BackgroundColor3 = Library.AccentColor
			accent.BorderSizePixel = 0
			accent.Size = UDim2.new(1, 0, 0, 2)
			accent.Parent = inner

			local title = Instance.new("TextLabel")
			title.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			title.TextColor3 = Library.AccentColor
			title.Text = "Animation Visualizer & Editor"
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextSize = 15
			title.Position = UDim2.new(0, 6, 0, 4)
			title.Size = UDim2.new(0, 300, 0, 18)
			title.Parent = inner

			local closeButton = Instance.new("TextButton")
			closeButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			closeButton.TextColor3 = Library.FontColor
			closeButton.BackgroundTransparency = 1
			closeButton.AutoButtonColor = false
			closeButton.Text = "X"
			closeButton.TextSize = 14
			closeButton.Position = UDim2.new(1, -22, 0, 4)
			closeButton.Size = UDim2.new(0, 18, 0, 18)
			closeButton.Parent = inner

			local viewport = Instance.new("ViewportFrame")
			viewport.BackgroundColor3 = Library.BackgroundColor
			viewport.BorderColor3 = Library.OutlineColor
			viewport.Position = UDim2.new(0, 5, 0, 48)
			viewport.Size = UDim2.new(0, 300, 0, 190)
			viewport.Parent = inner

			local world = Instance.new("WorldModel")
			world.Parent = viewport

			local camera = Instance.new("Camera")
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 70
			camera.Parent = viewport
			viewport.CurrentCamera = camera

			local message = Instance.new("TextLabel")
			message.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			message.TextColor3 = Library.FontColor
			message.Text = "Waiting for animation ID"
			message.BackgroundTransparency = 1
			message.TextWrapped = true
			message.TextSize = 13
			message.Size = UDim2.new(1, -10, 1, 0)
			message.Position = UDim2.new(0, 5, 0, 0)
			message.Parent = viewport

			local speedLabel = Instance.new("TextLabel")
			speedLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			speedLabel.TextColor3 = Library.FontColor
			speedLabel.Text = "Speed 0.00"
			speedLabel.BackgroundTransparency = 1
			speedLabel.TextXAlignment = Enum.TextXAlignment.Left
			speedLabel.TextSize = 12
			speedLabel.Position = UDim2.new(0, 4, 0, 2)
			speedLabel.Size = UDim2.new(0, 100, 0, 16)
			speedLabel.Parent = viewport

			local idBox = Instance.new("TextBox")
			idBox.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			idBox.TextColor3 = Library.FontColor
			idBox.BackgroundColor3 = Library.BackgroundColor
			idBox.BorderColor3 = Library.OutlineColor
			idBox.Text = "rbxassetid://0"
			idBox.TextSize = 13
			idBox.Position = UDim2.new(0, 5, 0, 26)
			idBox.Size = UDim2.new(0, 300, 0, 18)
			idBox.Parent = inner

			local sliderOuter = Instance.new("Frame")
			sliderOuter.BackgroundColor3 = Library.BackgroundColor
			sliderOuter.BorderColor3 = Library.OutlineColor
			sliderOuter.Position = UDim2.new(0, 5, 0, 242)
			sliderOuter.Size = UDim2.new(0, 300, 0, 16)
			sliderOuter.Parent = inner

			local sliderFill = Instance.new("Frame")
			sliderFill.BackgroundColor3 = Library.AccentColor
			sliderFill.BorderSizePixel = 0
			sliderFill.Size = UDim2.new(0, 0, 1, 0)
			sliderFill.Parent = sliderOuter

			local sliderText = Instance.new("TextLabel")
			sliderText.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			sliderText.TextColor3 = Library.FontColor
			sliderText.Text = "0.000 / 0.000"
			sliderText.BackgroundTransparency = 1
			sliderText.TextSize = 12
			sliderText.ZIndex = 5
			sliderText.Size = UDim2.new(1, 0, 1, 0)
			sliderText.Parent = sliderOuter

			local function button(text, x, width)
				local b = Instance.new("TextButton")
				b.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				b.TextColor3 = Library.FontColor
				b.BackgroundColor3 = Library.BackgroundColor
				b.BorderColor3 = Library.OutlineColor
				b.AutoButtonColor = false
				b.Text = text
				b.TextSize = 12
				b.Position = UDim2.new(0, x, 0, 262)
				b.Size = UDim2.new(0, width, 0, 18)
				b.Parent = inner
				Library:AddToRegistry(b, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)
				return b
			end

			local prevButton = button("<<", 5, 45)
			local playButton = button("Play", 54, 64)
			local nextButton = button(">>", 122, 45)
			local loadButton = button("From Log", 171, 134)

			local delayLine = Instance.new("Frame")
			delayLine.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
			delayLine.BorderSizePixel = 0
			delayLine.Size = UDim2.new(0, 1, 1, 0)
			delayLine.ZIndex = 6
			delayLine.Visible = false
			delayLine.Parent = sliderOuter

			local statusLabel = Instance.new("TextLabel")
			statusLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			statusLabel.TextColor3 = Library.FontColor
			statusLabel.Text = "Not in parry list"
			statusLabel.BackgroundTransparency = 1
			statusLabel.TextXAlignment = Enum.TextXAlignment.Left
			statusLabel.TextSize = 12
			statusLabel.Position = UDim2.new(0, 5, 0, 286)
			statusLabel.Size = UDim2.new(0, 300, 0, 16)
			statusLabel.Parent = inner

			----------------------------------------------------------------------------
			-- Quick Edit Timing panel
			----------------------------------------------------------------------------

			local PANEL_X = 312
			local PANEL_W = 250

			local divider = Instance.new("Frame")
			divider.BackgroundColor3 = Library.OutlineColor
			divider.BorderSizePixel = 0
			divider.Position = UDim2.new(0, PANEL_X - 6, 0, 26)
			divider.Size = UDim2.new(0, 1, 0, 276)
			divider.Parent = inner
			Library:AddToRegistry(divider, { BackgroundColor3 = "OutlineColor" }, true)

			local editorTitle = Instance.new("TextLabel")
			editorTitle.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			editorTitle.TextColor3 = Library.AccentColor
			editorTitle.Text = "Quick Edit Timing"
			editorTitle.BackgroundTransparency = 1
			editorTitle.TextXAlignment = Enum.TextXAlignment.Center
			editorTitle.TextSize = 14
			editorTitle.Position = UDim2.new(0, PANEL_X, 0, 26)
			editorTitle.Size = UDim2.new(0, PANEL_W, 0, 18)
			editorTitle.Parent = inner
			Library:AddToRegistry(editorTitle, { TextColor3 = "AccentColor" }, true)

			local DODGE_DIRS = { "None", "Left", "Right", "Back", "Forward" }

			-- kind drives parsing on save and formatting on load.
			local FIELDS = {
				{ key = "delay", label = "Delay (s)", kind = "seconds" },
				{ key = "hitboxX", label = "Hitbox X", kind = "number" },
				{ key = "hitboxY", label = "Hitbox Y", kind = "number" },
				{ key = "hitboxZ", label = "Hitbox Z", kind = "number" },
				{ key = "hso", label = "HSO", kind = "number" },
				{ key = "maxDistance", label = "Max Dist", kind = "number" },
				{ key = "repeatCount", label = "Repeat", kind = "int" },
				{ key = "repeatDelay", label = "Rep Delay", kind = "number" },
				{ key = "dodgeDir", label = "Dodge Dir", kind = "choice" },
			}

			local inputs = {}

			for index, field in ipairs(FIELDS) do
				local y = 48 + (index - 1) * 22

				local label = Instance.new("TextLabel")
				label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				label.TextColor3 = Library.FontColor
				label.Text = field.label
				label.BackgroundTransparency = 1
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextSize = 12
				label.Position = UDim2.new(0, PANEL_X + 4, 0, y)
				label.Size = UDim2.new(0, 92, 0, 20)
				label.Parent = inner
				Library:AddToRegistry(label, { TextColor3 = "FontColor" }, true)

				-- Dodge direction is a fixed set, so cycle it rather than trusting typing.
				local control
				if field.kind == "choice" then
					control = Instance.new("TextButton")
					control.AutoButtonColor = false
					control.Text = "None"
					control.MouseButton1Click:Connect(function()
						local current = table.find(DODGE_DIRS, control.Text) or 1
						control.Text = DODGE_DIRS[(current % #DODGE_DIRS) + 1]
					end)
				else
					control = Instance.new("TextBox")
					control.ClearTextOnFocus = false
					control.Text = "0"
				end

				control.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
				control.TextColor3 = Library.FontColor
				control.BackgroundColor3 = Library.BackgroundColor
				control.BorderColor3 = Library.OutlineColor
				control.TextSize = 12
				control.Position = UDim2.new(0, PANEL_X + 100, 0, y)
				control.Size = UDim2.new(0, PANEL_W - 104, 0, 20)
				control.Parent = inner
				Library:AddToRegistry(control, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

				inputs[field.key] = control
			end

			local saveButton = Instance.new("TextButton")
			saveButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			saveButton.TextColor3 = Library.FontColor
			saveButton.BackgroundColor3 = Library.BackgroundColor
			saveButton.BorderColor3 = Library.OutlineColor
			saveButton.AutoButtonColor = false
			saveButton.Text = "Save & Apply"
			saveButton.TextSize = 13
			saveButton.Position = UDim2.new(0, PANEL_X, 0, 254)
			saveButton.Size = UDim2.new(0, PANEL_W, 0, 22)
			saveButton.Parent = inner
			Library:AddToRegistry(saveButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			local toggleButton = Instance.new("TextButton")
			toggleButton.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
			toggleButton.TextColor3 = Library.FontColor
			toggleButton.BackgroundColor3 = Library.BackgroundColor
			toggleButton.BorderColor3 = Library.OutlineColor
			toggleButton.AutoButtonColor = false
			toggleButton.Text = "Add To Parry List"
			toggleButton.TextSize = 13
			toggleButton.Position = UDim2.new(0, PANEL_X, 0, 280)
			toggleButton.Size = UDim2.new(0, PANEL_W, 0, 22)
			toggleButton.Parent = inner
			Library:AddToRegistry(toggleButton, { BackgroundColor3 = "BackgroundColor", TextColor3 = "FontColor" }, true)

			Library:MakeDraggable(outer)
			Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
			Library:AddToRegistry(accent, { BackgroundColor3 = "AccentColor" }, true)
			Library:AddToRegistry(title, { TextColor3 = "AccentColor" }, true)
			Library:AddToRegistry(sliderFill, { BackgroundColor3 = "AccentColor" }, true)

			local currentTrack = nil
			local currentId = nil
			local paused = false
			local elapsed = 0

			function Visualizer.visible(state)
				screen.Enabled = state
			end

			function Visualizer.say(text)
				message.Visible = true
				message.Text = text
				world:ClearAllChildren()
			end

			closeButton.MouseButton1Click:Connect(function()
				local Toggles = ctx.Toggles
				if Toggles.ShowAnimationVisualizer then
					Toggles.ShowAnimationVisualizer:SetValue(false)
				else
					screen.Enabled = false
				end
			end)

			---Read the panel back out as a plain table.
			local function readEditor()
				local function num(key, fallback)
					return tonumber(inputs[key].Text) or fallback
				end

				return {
					-- Panel is in seconds because that is how animations read; the store
					-- stays in milliseconds because that is what the scheduler needs.
					delay = math.max(num("delay", 0) * 1000, 0),
					hitbox = {
						X = math.abs(num("hitboxX", 11)),
						Y = math.abs(num("hitboxY", 10)),
						Z = math.abs(num("hitboxZ", 30.5)),
					},
					hso = num("hso", 3),
					maxDistance = math.max(num("maxDistance", 85), 0),
					repeatCount = math.max(math.floor(num("repeatCount", 1)), 1),
					repeatDelay = math.max(num("repeatDelay", 0.35), 0),
					dodgeDir = inputs.dodgeDir.Text,
				}
			end

			---Paint the panel and the parry-list indicator for an animation id.
			---Falls back to template defaults so an unsaved animation still shows sane
			---starting numbers rather than a grid of zeroes.
			---@param animationId string
			function Visualizer.syncEditor(animationId)
				local timing = Store.get(animationId)
				local source = timing

				if not source then
					local length = (Log.playback[animationId] and Log.playback[animationId].length)
						or (currentTrack and currentTrack.Length)
						or 1
					source = Store.template(animationId, length, "Unnamed")
				end

				source = Store.normalise(source)

				inputs.delay.Text = string.format("%.3f", (source.delay or 0) / 1000)
				inputs.hitboxX.Text = tostring(source.hitbox.X)
				inputs.hitboxY.Text = tostring(source.hitbox.Y)
				inputs.hitboxZ.Text = tostring(source.hitbox.Z)
				inputs.hso.Text = tostring(source.hso)
				inputs.maxDistance.Text = tostring(source.maxDistance)
				inputs.repeatCount.Text = tostring(source.repeatCount)
				inputs.repeatDelay.Text = tostring(source.repeatDelay)
				inputs.dodgeDir.Text = source.dodgeDir or "None"

				-- Keep the world preview showing the timing that is on screen. Read
				-- through ctx: this module loads before the sliders exist.
				if ctx.Hitbox then
					ctx.Hitbox.adopt(source)
				end

				if timing and timing.enabled then
					statusLabel.Text = "In parry list"
					statusLabel.TextColor3 = Color3.fromRGB(90, 230, 120)
					toggleButton.Text = "Remove From Parry List"
				elseif timing then
					statusLabel.Text = "Saved, not enabled"
					statusLabel.TextColor3 = Color3.fromRGB(255, 190, 70)
					toggleButton.Text = "Add To Parry List"
				else
					statusLabel.Text = "Not in parry list"
					statusLabel.TextColor3 = Library.FontColor
					toggleButton.Text = "Add To Parry List"
				end

				delayLine.Visible = timing ~= nil
				if timing and currentTrack and currentTrack.Length > 0 then
					delayLine.Position = UDim2.new(math.clamp((timing.delay / 1000) / currentTrack.Length, 0, 1), 0, 0, 0)
				end
			end

			---Write the panel into the store and persist.
			---@param enable boolean? force the enabled flag, otherwise keep what it was
			local function applyEditor(enable)
				if not currentId then
					return notify("Load an animation first", 2)
				end

				local values = readEditor()
				local timing = Store.get(currentId)

				if not timing then
					local length = (currentTrack and currentTrack.Length) or values.delay / 1000
					timing = Store.template(currentId, length, idBox:GetAttribute("EntityName") or "Unnamed")
					Store.create(timing, false)
				end

				for key, value in pairs(values) do
					timing[key] = value
				end

				if enable ~= nil then
					timing.enabled = enable
				end

				Store.timings[currentId] = timing
				Store.dirty = true

				local ok = Store.save(Store.configName)
				notify(
					ok and string.format("Saved %s (%s)", Util.shortId(currentId), timing.enabled and "in parry list" or "off")
						or "Save failed - no filesystem access",
					2
				)

				Visualizer.syncEditor(currentId)
				LoggerGui.refresh()
			end

			saveButton.MouseButton1Click:Connect(function()
				applyEditor(nil)
			end)

			toggleButton.MouseButton1Click:Connect(function()
				if not currentId then
					return notify("Load an animation first", 2)
				end
				local timing = Store.get(currentId)
				applyEditor(not (timing and timing.enabled))
			end)

			---Pick a rig to play the animation on.
			---The entity that threw the animation is preferred, but it dies, despawns and
			---streams out constantly, so fall back rather than refusing to draw anything.
			---@param animationId string
			---@return Model?
			local function sourceRig(animationId)
				local data = Log.playback[animationId]
				if data and data.entity and data.entity.Parent then
					return data.entity
				end

				for _, entry in ipairs(Log.entries) do
					if entry.id == animationId and entry.model and entry.model.Parent then
						return entry.model
					end
				end

				-- Any live rig will do; the skeleton is what plays the animation.
				local rigs = Entities.list()
				if rigs[1] then
					return rigs[1]
				end

				return LocalPlayer.Character
			end

			---Load an animation id into the viewport.
			---@param animationId string
			function Visualizer.load(animationId)
				currentTrack = nil
				currentId = nil
				elapsed = 0
				paused = false

				if type(animationId) ~= "string" or animationId == "" then
					return Visualizer.say("No animation id")
				end

				local rig = sourceRig(animationId)
				if not rig then
					return Visualizer.say("No rig available.\nSpawn in, or get near an NPC, then click again.")
				end

				world:ClearAllChildren()

				-- Some games clear Archivable to block exactly this. Flip it back for the
				-- duration of the clone, then restore so we do not alter the live game.
				local restore = {}
				if not rig.Archivable then
					rig.Archivable = true
					table.insert(restore, rig)
				end
				for _, descendant in ipairs(rig:GetDescendants()) do
					if not descendant.Archivable then
						descendant.Archivable = true
						table.insert(restore, descendant)
					end
				end

				local ok, clone = pcall(function()
					return rig:Clone()
				end)

				for _, instance in ipairs(restore) do
					pcall(function()
						instance.Archivable = false
					end)
				end

				if not ok or not clone then
					return Visualizer.say("Could not clone the rig")
				end

				-- Strip scripts so nothing from the rig runs inside the viewport.
				for _, descendant in ipairs(clone:GetDescendants()) do
					if descendant:IsA("BaseScript") then
						descendant:Destroy()
					end
				end

				clone.Parent = world

				if not clone.PrimaryPart then
					clone.PrimaryPart = clone:FindFirstChild("HumanoidRootPart")
				end

				if not clone.PrimaryPart then
					clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
				end

				if not clone.PrimaryPart then
					return Visualizer.say("Rig has no parts to display")
				end

				clone:PivotTo(CFrame.new(0, 0, 0))

				-- Frame the bounding box centre, not the pivot: the pivot sits at the
				-- waist, and a sword swing needs headroom above it.
				local box, size = clone:GetBoundingBox()
				local focus = box.Position
				camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, size.Y * 0.15, -size.Magnitude * 1.6), focus)

				local animator = clone:FindFirstChildWhichIsA("Animator", true)

				-- Plenty of NPCs only carry an Animator server side, so the clone has a
				-- Humanoid and nothing to drive it. Make one.
				if not animator then
					local controller = clone:FindFirstChildWhichIsA("Humanoid")
						or clone:FindFirstChildWhichIsA("AnimationController")

					if not controller then
						controller = Instance.new("AnimationController")
						controller.Parent = clone
					end

					animator = Instance.new("Animator")
					animator.Parent = controller
				end

				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end

				local animation = Instance.new("Animation")
				animation.AnimationId = animationId

				local loaded, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)

				if not loaded or not track then
					return Visualizer.say("Could not load that animation id")
				end

				track.Priority = Enum.AnimationPriority.Action
				track.Looped = true
				track:Play(0, 100, 1)

				track.DidLoop:Connect(function()
					elapsed = 0
				end)

				currentTrack = track
				currentId = animationId
				message.Visible = false
				idBox.Text = animationId
				idBox:SetAttribute("EntityName", rig.Name)

				Visualizer.syncEditor(animationId)

				-- Length is 0 until Roblox finishes fetching the asset, so the delay
				-- marker cannot be placed on the first frame. Wait for it.
				task.spawn(function()
					local deadline = os.clock() + 5

					while track.Length <= 0 and os.clock() < deadline do
						task.wait(0.05)
					end

					if currentTrack ~= track then
						return
					end

					if track.Length <= 0 then
						return Visualizer.say(
							"Animation asset never loaded.\n" .. Util.shortId(animationId) .. "\nIt may be private or deleted."
						)
					end

					-- Re-sync now that Length is real: this is what places the delay marker.
					Visualizer.syncEditor(animationId)
				end)
			end

			idBox.FocusLost:Connect(function(enter)
				if enter then
					Visualizer.load(idBox.Text)
				end
			end)

			playButton.MouseButton1Click:Connect(function()
				if not currentTrack then
					return
				end
				paused = not paused
				playButton.Text = paused and "Paused" or "Play"
			end)

			prevButton.MouseButton1Click:Connect(function()
				if not currentTrack then
					return
				end
				paused = true
				playButton.Text = "Paused"
				currentTrack.TimePosition = math.max(currentTrack.TimePosition - 0.01, 0)
			end)

			nextButton.MouseButton1Click:Connect(function()
				if not currentTrack then
					return
				end
				paused = true
				playButton.Text = "Paused"
				currentTrack.TimePosition = math.min(currentTrack.TimePosition + 0.01, currentTrack.Length)
			end)

			loadButton.MouseButton1Click:Connect(function()
				if not Log.selected then
					return notify("Click a row in the logger window first", 2)
				end
				Visualizer.load(Log.selected)
			end)

			-- Scrubbing.
			sliderOuter.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end
				if not currentTrack then
					return
				end

				paused = true
				playButton.Text = "Paused"

				-- Mouse rather than GetMouseLocation: the library's own drag code uses
				-- Mouse against AbsolutePosition, so the two agree about the topbar inset.
				local mouse = LocalPlayer:GetMouse()

				while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					if not currentTrack then
						break
					end
					local width = sliderOuter.AbsoluteSize.X
					local x = math.clamp(mouse.X - sliderOuter.AbsolutePosition.X, 0, width)
					currentTrack.TimePosition = (x / width) * currentTrack.Length
					RunService.RenderStepped:Wait()
				end
			end)

			---Per-frame playback update.
			---@param delta number
			function Visualizer.step(delta)
				if not screen.Enabled then
					return
				end

				if not currentTrack or not currentTrack.IsPlaying then
					sliderText.Text = "0.000 / 0.000"
					sliderFill.Size = UDim2.new(0, 0, 1, 0)
					return
				end

				local fraction = currentTrack.Length > 0 and (currentTrack.TimePosition / currentTrack.Length) or 0
				sliderFill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
				local timing = Store.get(currentId)
				sliderText.Text = timing
						and string.format(
							"%.3f / %.3f (%dms)",
							currentTrack.TimePosition,
							currentTrack.Length,
							math.floor(timing.delay)
						)
					or string.format("%.3f / %.3f", currentTrack.TimePosition, currentTrack.Length)

				if paused then
					currentTrack:AdjustSpeed(0)
					speedLabel.Text = string.format("Speed %.2f", Log.speedAt(currentId, currentTrack.TimePosition))
					return
				end

				elapsed = elapsed + delta

				-- Replay at the speed the animation was actually played at us, not 1x.
				local speed = Log.speedAt(currentId, elapsed)
				currentTrack:AdjustSpeed(speed)
				speedLabel.Text = string.format("Speed %.2f", speed)
			end

			return Visualizer
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/VisualizerWindow.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/Wiring.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
			local BuilderBox, StoreBox, HitboxBox = ctx.BuilderBox, ctx.StoreBox, ctx.HitboxBox
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
				Text = "Download Timings",
				DoubleClick = true,
				Tooltip = "Replace the loaded database with the one bundled for this place",
				Func = function()
					-- Double click, because this throws away whatever is in memory. Boot
					-- only does it on a clean install; this is the manual escape hatch.
					local ok, err = Store.fetch()
					if not ok then
						return notify("Download failed: " .. tostring(err), 3)
					end

					Store.save("default")
					Options.TimingList:SetValue(nil)
					configList:SetValues(Store.list())
					configList:Display()
					refreshTimingList()
					notify(string.format("Downloaded %d timings", Store.count()), 3)
				end,
			})

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

			----------------------------------------------------------------------------
			-- Hitbox preview <-> timing database
			----------------------------------------------------------------------------

			---Which timing the preview buttons act on.
			---The logger selection wins, because if the visualizer is open that is the
			---animation you are actually looking at; the dropdown is the fallback for
			---when you are tuning without the logger up.
			local function previewTarget()
				if Log.selected then
					local fromLog = Store.get(Log.selected)
					if fromLog then
						return fromLog
					end
				end
				return Store.fromDisplay(Options.TimingList.Value)
			end

			HitboxBox:AddButton({
				Text = "Load From Selected",
				Tooltip = "Pull the hitbox off the selected timing into these sliders",
				Func = function()
					local timing = previewTarget()
					if not timing then
						return notify("Select a timing, or click a logger row", 2)
					end

					timing = Store.normalise(timing)

					Options.HB_X:SetValue(timing.hitbox.X)
					Options.HB_Y:SetValue(timing.hitbox.Y)
					Options.HB_Z:SetValue(timing.hitbox.Z)
					Options.HB_HSO:SetValue(timing.hso)
					Options.HB_MaxDistance:SetValue(timing.maxDistance)

					notify("Loaded hitbox from " .. timing.name, 2)
				end,
			}):AddButton({
				Text = "Apply To Selected",
				Tooltip = "Write these sliders back and save",
				Func = function()
					local timing = previewTarget()
					if not timing then
						return notify("Select a timing, or click a logger row", 2)
					end

					timing.hitbox = {
						X = Options.HB_X.Value,
						Y = Options.HB_Y.Value,
						Z = Options.HB_Z.Value,
					}
					timing.hso = Options.HB_HSO.Value
					timing.maxDistance = Options.HB_MaxDistance.Value

					Store.timings[timing.id] = timing
					Store.dirty = true

					local ok = Store.save(Store.configName)

					-- The visualizer's Quick Edit panel shows the same numbers, so repaint
					-- it rather than leaving two views of one timing disagreeing.
					if Visualizer.syncEditor then
						pcall(Visualizer.syncEditor, timing.id)
					end

					refreshTimingList()
					notify(ok and ("Applied hitbox to " .. timing.name) or "Save failed - no filesystem access", 2)
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/Wiring.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/ui/Settings.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
		--[[
			ui/Settings.lua
			Tab 3: unload button, menu keybind, Linoria's own theme and config managers.

			SaveManager here stores UI state (slider positions, toggles). It is a
			separate thing from features/Store.lua, which stores the timing database.
			They live in different folders on purpose.
		]]

		return function(ctx)
			local Library, Tabs = ctx.Library, ctx.Tabs
			local ThemeManager, SaveManager = ctx.ThemeManager, ctx.SaveManager
			local Options = ctx.Options

			local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

			MenuGroup:AddButton("Unload", function()
				Library:Unload()
			end)

			MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
				Default = "End",
				NoUI = true,
				Text = "Menu keybind",
			})

			Library.ToggleKeybind = Options.MenuKeybind

			ThemeManager:SetLibrary(Library)
			SaveManager:SetLibrary(Library)
			SaveManager:IgnoreThemeSettings()
			SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
			-- Linoria's BuildFolderTree only makefolder()s the paths it is given, so the
			-- intermediate AutoParry/settings has to exist before it is handed a nested
			-- path. FS.makeTree walks it segment by segment.
			local settingsFolder = ctx.SETTINGS_FOLDER .. "/" .. tostring(game.PlaceId)
			ctx.FS.makeTree(settingsFolder)

			ThemeManager:SetFolder(ctx.ROOT_FOLDER)
			SaveManager:SetFolder(settingsFolder)
			SaveManager:BuildConfigSection(Tabs["UI Settings"])
			ThemeManager:ApplyToTab(Tabs["UI Settings"])

			return MenuGroup
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/ui/Settings.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/Runtime.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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
			local Hitbox, HitboxLabel = ctx.Hitbox, ctx.HitboxLabel

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

				-- Per-frame so the box tracks a moving attacker instead of lagging behind
				-- them by up to 0.15s.
				Hitbox.step()
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

					HitboxLabel:SetText(Hitbox.status())

					task.wait(0.15)
				end
			end)

			Library:OnUnload(function()
				renderConnection:Disconnect()
				Hooks.detach()
				Hitbox.destroy()

				if Store.dirty then
					Store.save(Store.configName)
				end

				Library.Unloaded = true
				print("[AutoParry] Unloaded.")
			end)

			return renderConnection
		end
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/Runtime.lua: " .. tostring(err), 0)
	end
end


--------------------------------------------------------------------------------
-- src/Boot.lua
--------------------------------------------------------------------------------

do
	local factory = (function()
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

			-- Local database wins: it is the one you have been tuning. Only when there
			-- is nothing on disk do we pull the database bundled with the script, so an
			-- update can never overwrite your own work.
			if FS.isFile(Store.path("default")) then
				Store.load("default")
			else
				local fetched = Store.fetch()
				if fetched then
					Store.save("default")
					notify(string.format("Downloaded %d timings for this place", Store.count()), 4)
				end
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
	end)()

	local ok, err = pcall(factory, ctx)
	if not ok then
		error("[AutoParry] error in src/Boot.lua: " .. tostring(err), 0)
	end
end


return ctx
