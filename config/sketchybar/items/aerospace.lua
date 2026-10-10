local colors = require("colors")
local icons = require("icons")
local ui = require("ui")

sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_monitor_change")

local spaces = {}

local LABEL_GAP = 10

local PILL_PADDING = 6
local PILL_GAP = 10
-- bracket の範囲は item の padding を含むので、bracket の左右の端から pill までの余白も
-- この値 (PILL_GAP の半分) になる。そのため端に spacer は置かない。
local ITEM_PADDING = PILL_GAP / 2
local PILL_MARGIN_Y = PILL_GAP / 2
local PILL_HEIGHT = colors.bracket.height - 2 * PILL_MARGIN_Y

local function refresh_space(sid, is_focused)
	local space = spaces[sid]
	if space == nil then
		return
	end

	sbar.exec("aerospace list-windows --workspace " .. sid .. " --format '%{app-name}'", function(windows)
		local strip = {}
		for app in (windows or ""):gmatch("[^\r\n]+") do
			table.insert(strip, icons.app(app))
		end

		if #strip == 0 then
			space:set({
				drawing = is_focused == true,
				icon = { padding_right = PILL_PADDING },
				label = { string = "", padding_left = 0, padding_right = 0 },
			})
			return
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
		-- 表示中の workspace は増減するので、最初は隠しておく
		drawing = false,
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
	table.insert(members, 1, add_space(sid))
end

ui.add_bracket("space.bracket", members)

-- 名前が取れなかったときは callback を呼ばない
local function with_focused(callback)
	sbar.exec("aerospace list-workspaces --focused", function(focused)
		focused = focused and focused:match("%S+")
		if focused == nil then
			return
		end
		callback(focused)
	end)
end

-- イベントの購読は、space の item ごとではなく、この非表示の item で 1 回だけ行う。
-- ハンドラはどの item でも同じ処理 (全 workspace を見る) なので、space の item ごとに購読すると、
-- 1 回のイベントで aerospace の問い合わせが item の数だけ重なる。
local watcher = ui.add_item("aerospace.watcher", "left", { drawing = false })
watcher:subscribe("aerospace_workspace_change", on_workspace_change)
watcher:subscribe("aerospace_monitor_change", on_monitor_change)
watcher:subscribe("front_app_switched", function()
	with_focused(function(focused)
		refresh_space(focused, true)
	end)
end)

with_focused(function(focused)
	for sid, _ in pairs(spaces) do
		highlight(sid, focused)
		refresh_space(sid, sid == focused)
	end
end)
