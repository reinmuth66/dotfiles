local colors = require("colors")
local icons = require("icons")

sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_monitor_change")

local spaces = {}

-- `aerospace list-windows` prints "<window-id> | <app-name> | <window-title>".
-- We need the app name (2nd field), not the title (last field).
local function app_name_from_line(line)
	local fields = {}
	for field in line:gmatch("([^|]+)") do
		table.insert(fields, field)
	end
	local app = fields[2]
	if app == nil then
		return nil
	end
	return app:match("^%s*(.-)%s*$")
end

-- Builds the "icon strip" (one glyph per open window) for a workspace, then
-- shows/hides + relabels the corresponding space item.
-- The focused workspace is always shown, even when empty (matches the
-- original bash plugins/space_windows.sh, which unconditionally does
-- `sketchybar --set space.$FOCUSED_WORKSPACE drawing=on`); any other
-- workspace is only shown while it has open windows.
local function refresh_space(sid, is_focused)
	local space = spaces[sid]
	if space == nil then
		return
	end

	sbar.exec("aerospace list-windows --workspace " .. sid, function(windows)
		local apps = {}
		if windows ~= nil then
			for line in windows:gmatch("[^\r\n]+") do
				local app = app_name_from_line(line)
				if app ~= nil and app ~= "" then
					table.insert(apps, app)
				end
			end
		end

		if #apps == 0 then
			space:set({ drawing = is_focused == true, label = "" })
			return
		end

		local strip = {}
		for _, app in ipairs(apps) do
			table.insert(strip, icons.app(app))
		end

		space:set({ drawing = true, label = " " .. table.concat(strip, " ") })
	end)
end

local function highlight(sid, focused_sid)
	local space = spaces[sid]
	if space == nil then
		return
	end

	if sid == focused_sid then
		space:set({
			background = { color = colors.space.bg_focused, border_width = 2 },
			icon = { shadow = { drawing = true } },
			label = { shadow = { drawing = true } },
		})
	else
		space:set({
			background = { color = colors.space.bg, border_width = 0 },
			icon = { shadow = { drawing = false } },
			label = { shadow = { drawing = false } },
		})
	end
end

local function add_space(sid)
	local space = sbar.add("item", "space." .. sid, {
		position = "left",
		drawing = false,
		icon = {
			string = sid,
			padding_left = 10,
			shadow = { distance = 4, color = 0xa0000000 },
		},
		label = {
			font = "sketchybar-app-font:Regular:16.0",
			padding_left = 0,
			padding_right = 20,
			y_offset = -1,
			shadow = { distance = 4, color = 0xa0000000 },
		},
		background = {
			drawing = true,
			color = colors.space.bg,
			border_color = colors.space.border,
			border_width = 0,
			corner_radius = 5,
			height = 25,
		},
	})

	spaces[sid] = space

	space:subscribe("mouse.clicked", function()
		sbar.exec("aerospace workspace " .. sid)
	end)

	return space
end

-- aerospace.toml notifies us of workspace/monitor changes via
-- `sketchybar --trigger aerospace_workspace_change ...` /
-- `... aerospace_monitor_change ...` (see modules/aerospace.nix).
local function on_workspace_change(env)
	if env.FOCUSED_WORKSPACE then
		highlight(env.FOCUSED_WORKSPACE, env.FOCUSED_WORKSPACE)
		refresh_space(env.FOCUSED_WORKSPACE, true)
	end
	if env.PREV_WORKSPACE then
		highlight(env.PREV_WORKSPACE, env.FOCUSED_WORKSPACE)
		refresh_space(env.PREV_WORKSPACE, false)
	end
end

local function on_monitor_change(env)
	if env.FOCUSED_WORKSPACE and env.TARGET_MONITOR and spaces[env.FOCUSED_WORKSPACE] then
		spaces[env.FOCUSED_WORKSPACE]:set({ display = env.TARGET_MONITOR })
	end
end

-- Workspaces are created synchronously (matching persistent-workspaces in
-- modules/aerospace.nix) instead of waiting on an async
-- `aerospace list-workspaces --all` call: sbar.add() calls made later
-- (asynchronously, inside a sbar.exec callback) would land to the right of
-- items added synchronously by later items/*.lua files (e.g. front_app),
-- since bar position is ordered by add() call time, not require() order.
for i = 1, 9 do
	local sid = tostring(i)
	local space = add_space(sid)
	space:subscribe("aerospace_workspace_change", on_workspace_change)
	space:subscribe("aerospace_monitor_change", on_monitor_change)
end

sbar.exec("aerospace list-workspaces --focused", function(focused)
	focused = focused and focused:match("%S+")
	if focused == nil then
		return
	end
	for sid, _ in pairs(spaces) do
		highlight(sid, focused)
		refresh_space(sid, sid == focused)
	end
end)
