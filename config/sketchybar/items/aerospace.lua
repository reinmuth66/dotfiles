local colors = require("colors")
local icons = require("icons")
local ui = require("ui")

sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_monitor_change")

local spaces = {}

-- 番号とアプリアイコンの間隔 (px)
local LABEL_GAP = 10

-- フォーカス中の workspace に出す背景 (pill) の、文字から端までの余白 (px)。
local PILL_PADDING = 6
-- pill 同士の間隔 (px)
local PILL_GAP = 10
-- 各 workspace の外側の padding。隣り合う 2 つで足して PILL_GAP になる。
-- bracket の範囲は item の padding を含むので、bracket の左右の端から pill までの余白も
-- この値 (PILL_GAP の半分) になる。そのため端に spacer は置かない。
local ITEM_PADDING = PILL_GAP / 2
-- bracket の上下の端から pill までの余白 (px)。左右の端と同じく PILL_GAP の半分にそろえる。
local PILL_MARGIN_Y = PILL_GAP / 2
-- pill の高さは bracket の高さと上下の余白から決まる。
local PILL_HEIGHT = colors.bracket.height - 2 * PILL_MARGIN_Y

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
			space:set({
				drawing = is_focused == true,
				icon = { padding_right = PILL_PADDING },
				label = { string = "", padding_left = 0, padding_right = 0 },
			})
			return
		end

		local strip = {}
		for _, app in ipairs(apps) do
			table.insert(strip, icons.app(app))
		end

		space:set({
			drawing = true,
			icon = { padding_right = 0 },
			label = { string = table.concat(strip), padding_left = LABEL_GAP, padding_right = PILL_PADDING },
		})
	end)
end

local function highlight(sid, focused_sid)
	local space = spaces[sid]
	if space == nil then
		return
	end

	if sid == focused_sid then
		space:set({
			icon = { color = colors.space.fg_focused },
			label = { color = colors.space.fg_focused },
			background = { drawing = true },
		})
	else
		space:set({
			icon = { color = colors.space.fg },
			label = { color = colors.space.fg },
			background = { drawing = false },
		})
	end
end

local function add_space(sid)
	local space = ui.add_item("space." .. sid, "left", {
		-- 表示中の workspace は増減するので、最初は隠しておく (refresh_space で出し入れする)
		drawing = false,
		-- pill 同士の間隔は item の padding で決める
		padding_left = ITEM_PADDING,
		padding_right = ITEM_PADDING,
		icon = {
			string = sid,
			padding_left = PILL_PADDING,
			padding_right = PILL_PADDING,
		},
		label = {
			font = "sketchybar-app-font:Regular:16.0",
			padding_left = 0,
			padding_right = 0,
			y_offset = 0,
		},
		background = {
			drawing = false,
			color = colors.space.bg_focused,
			corner_radius = 5,
			height = PILL_HEIGHT,
		},
	})

	spaces[sid] = space

	space:subscribe("mouse.clicked", function()
		sbar.exec("aerospace workspace " .. sid)
	end)

	return space
end

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

local members = {}
for i = 1, 9 do
	local sid = tostring(i)
	local space = add_space(sid)
	space:subscribe("aerospace_workspace_change", on_workspace_change)
	space:subscribe("aerospace_monitor_change", on_monitor_change)
	table.insert(members, 1, space)
end

ui.add_bracket("space.bracket", members)

local app_watcher = ui.add_item("aerospace.app_watcher", "left", { drawing = false })
app_watcher:subscribe("front_app_switched", function()
	sbar.exec("aerospace list-workspaces --focused", function(focused)
		focused = focused and focused:match("%S+")
		if focused == nil then
			return
		end
		refresh_space(focused, true)
	end)
end)

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
