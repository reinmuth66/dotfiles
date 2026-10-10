local colors = require("colors")
local ui = require("ui")

-- An item for the Activity Monitor icon. On hover it opens the following one-line popup.
--   CPU icon and x%, RAM icon and x%, Disk icon and used/total
-- Data is measured at regular intervals by sketchybar-system-helper from pkgs/sketchybar-helper/system.c and delivered with the system_stats event.
-- The helper only calls kernel APIs directly, so measurement is light. While the popup is closed, no set for drawing is issued.
-- The numbers have the same values and format as bottom's btm. btm is shown by pkgs/btm-window. How values are measured: pkgs/sketchybar-helper/system.c.

-- The glyph of :activity_monitor: in sketchybar-app-font is almost a square with side SIZE.
-- Measured with CoreText's CTLineGetImageBounds. Width is SIZE x 0.998 and height is SIZE x 0.962: 19.96 x 19.24 at 20pt, 15.97 x 15.39 at 16pt.
-- SIZE of 16 gives a gap of about 4 pt between the pill's edge and the icon. The pill's PILL_SIZE is 24. Re-measure if the font or size changes.
local SIZE = 16

-- Fit within the bar's ui.bar_height.
local POPUP_HEIGHT = 32
-- Make the visual margins top/bottom, left/right, and between items equal to this value. Same 8 as ui.bracket_padding.
-- Vertically, the contents' glyph height is centered in POPUP_HEIGHT, so (32 - 15) / 2 = 8.5. Rounded to integers, 8 and 9.
-- The glyph height GLYPH_HEIGHT is 15: the measured 13.5 to 14.5 of the tallest CPU and Disk icons plus y_offset 1.
-- Horizontally it is made with item padding. The label has a fixed width, with about 1 pt left over to the right of the glyph. Measured: "07%" is a glyph of 23.0 in a box of 24.
-- So the space between items and at the right edge is reduced by that amount.
local POPUP_MARGIN = 8
local LABEL_SLACK = 1

-- A spacer is drawn at width + 1 pt, so subtract 1 from the spacer's width. See ui.add_spacer.
local POPUP_GAP = 4

-- Register before the helper launches. An unregistered event cannot be --trigger'd.
sbar.add("event", "system_stats")

-- Placed at the position closest to the notch, so add it before gear.
ui.add_notch_spacer("q", "system.notch_gap")

-- So that the icon sits concentrically within the circle, leave margins of ICON_PADDING on the left and right of the icon.
-- The pill is the circular background that shows the state of the btm window; see near set_btm_state. It is concentric with the bracket, and the gap to the edge is PILL_MARGIN top and bottom.
-- The gap is 5 pt, the same as aerospace's pill and spotify's image.
-- Use the same gap on left and right, making the bracket's width equal to its height. It becomes a circle, the same as spotify's bracket.
local PILL_MARGIN = 5
local SIDE_MARGIN = PILL_MARGIN
local PILL_SIZE = colors.bracket.height - 2 * PILL_MARGIN
local BRACKET_WIDTH = PILL_SIZE + 2 * SIDE_MARGIN
local ICON_PADDING = (PILL_SIZE - SIZE) / 2

-- Do not specify the item's width. After an item with width specified, placement advances only by width,
-- and the bracket's padding is not counted, so the adjacent item overlaps by the padding. See the ui.add_hit_region documentation.
-- The width is determined by icon.width. icon.width is the full width of the box including padding, the same as spotify.lua.
-- The glyph is drawn from the box's left edge + padding_left. The glyph width is 19.96, so it is only 0.02 pt left of the circle's center.
local gear = ui.add_item("system", "q", {
	icon = {
		string = ":activity_monitor:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		width = PILL_SIZE,
		align = "left",
		padding_left = ICON_PADDING,
		padding_right = 0,
	},
	label = { drawing = false },
	background = {
		drawing = false,
		height = PILL_SIZE,
		corner_radius = PILL_SIZE / 2,
	},
})

local bracket = ui.add_bracket("system.bracket", { gear }, {
	background = { corner_radius = colors.bracket.height / 2 },
}, SIDE_MARGIN)

-- The item's width is automatic, so chain, the width by which placement advances, is the same as the bracket's width.
local hit = ui.add_hit_region("system.hit", BRACKET_WIDTH, 0, BRACKET_WIDTH, { position = "q" })

-- The number format is the same as btm's src/utils/data_units.rs and conversion.rs.
-- Use decimal prefixes with 1 KB = 1000 B and compute the value with a single division. Matches btm's get_decimal_bytes and get_unit_prefix.
local DECIMAL_BYTES = { { 1e12, "TB" }, { 1e9, "GB" }, { 1e6, "MB" }, { 1e3, "KB" } }

-- The same 325GB form as btm's disk widget.
local function format_disk(bytes)
	for _, entry in ipairs(DECIMAL_BYTES) do
		if bytes >= entry[1] then
			return string.format("%.0f%s", bytes / entry[1], entry[2])
		end
	end
	return string.format("%.0f%s", bytes, "B")
end

-- So as not to overlap the icon or the adjacent item, the popup's owner is the anchor of an empty item placed to the left of the icon.
-- Use ui.add_popup_anchor.
ui.add_spacer("q", POPUP_GAP - 1)
local anchor = ui.add_popup_anchor("system.anchor", "q", {
	align = "right",
	height = POPUP_HEIGHT,
	background = {
		color = colors.bracket.color,
		border_color = colors.bracket.border_color,
		border_width = colors.bracket.border_width,
		corner_radius = colors.bracket.corner_radius,
	},
})

-- The presentation of numbers is the same as battery.lua. The label width is fixed so that the adjacent item does not shift even when the digit count changes.
-- Measured with Hack Nerd Font Bold 13pt; the label's fixed width includes the inner padding_left of 3.
-- "45%" is 27px and "100%" is 34px. The longest form, "245GB/500GB", is 89px.
-- A single digit is zero-padded like "05%" and treated as two digits. Re-measure if the font, size, or label padding changes.
local PERCENT_WIDTH_BY_DIGITS = { [2] = 27, [3] = 34 }
local DISK_WIDTH = 89

-- The glyph is wider than the advance of 10.8, and if it overflows the box it overlaps the number. Same as wifi.lua and bluetooth.lua.
-- The glyph is drawn from the box's left edge, so the box width is the glyph width plus the 3.9 margin between the glyph's right edge and the number, rounded up.
-- Glyph widths were measured with CTLineGetImageBounds. With Hack Nerd Font Bold 18pt: CPU 13.5, RAM 18.7, Disk 14.5.
-- 3.9 is the same as battery.lua's visual margin: advance 10.8 - glyph right edge 9.9 + icon padding_right 3.
-- Re-measure if the font or size changes.
local CPU_ICON_WIDTH = 18
local RAM_ICON_WIDTH = 23
local DISK_ICON_WIDTH = 19

local function add_stat(name, icon, icon_width, width, padding_left, padding_right)
	return sbar.add("item", "system." .. name, {
		position = "popup.system.anchor",
		padding_left = padding_left,
		padding_right = padding_right,
		icon = {
			string = icon,
			font = { size = 18.0 },
			y_offset = 1,
			width = icon_width,
			align = "left",
			padding_left = 0,
			padding_right = 0,
		},
		label = { string = "", width = width, padding_left = 3, padding_right = 0 },
	})
end

local EDGE_PADDING = POPUP_MARGIN - LABEL_SLACK
local cpu_item = add_stat("cpu", "\u{f035b}", CPU_ICON_WIDTH, PERCENT_WIDTH_BY_DIGITS[2], POPUP_MARGIN, EDGE_PADDING)
local ram_item = add_stat("ram", "\u{efc5}", RAM_ICON_WIDTH, PERCENT_WIDTH_BY_DIGITS[2], 0, EDGE_PADDING)
local disk_item = add_stat("disk", "\u{f0c7}", DISK_ICON_WIDTH, DISK_WIDTH, 0, EDGE_PADDING)

local function percent_label(value)
	local text = string.format("%02.0f%%", value)
	return { string = text, width = PERCENT_WIDTH_BY_DIGITS[#text - 1] }
end

-- Memory pressure is the kernel's kern.memorystatus_vm_pressure_level, i.e. MEM_PRESSURE in pkgs/sketchybar-helper/system.c. This is its display color.
-- 1 is normal, 2 is warn, 4 is critical. When the value cannot be obtained, i.e. nil, use the normal color.
local PRESSURE_COLORS = {
	[1] = colors.status.normal,
	[2] = colors.status.warn,
	[4] = colors.status.critical,
}

-- Judged by the instantaneous value. No smoothing.
--   CPU : warn is from Apple's support article: sustained use above 70% is high load. The critical 90% is a rough guide.
--   Disk: warn at 20% free or less, critical at 10% or less. From the macOS guideline of keeping 10-20% free and Zabbix's default of 90%.
local CPU_THRESHOLDS = { warn = 70, critical = 90 }
local DISK_THRESHOLDS = { warn = 80, critical = 90 }

local function threshold_color(value, thresholds)
	if value >= thresholds.critical then
		return colors.status.critical
	elseif value >= thresholds.warn then
		return colors.status.warn
	end
	return colors.status.normal
end

local function colored(label, color)
	label.color = color
	return { icon = { color = color }, label = label }
end

local last_env
local popup_open = false

local function render()
	if last_env == nil then
		return
	end
	local env = last_env

	local cpu = tonumber(env.CPU)
	local ram_used, ram_total = tonumber(env.RAM_USED), tonumber(env.RAM_TOTAL)
	local disk_total, disk_free = tonumber(env.DISK_TOTAL), tonumber(env.DISK_FREE)
	if not (cpu and ram_used and ram_total and disk_total and disk_free) then
		return
	end

	local ram_percent = ram_total > 0 and ram_used / ram_total * 100 or 0
	local disk_percent = disk_total > 0 and (disk_total - disk_free) / disk_total * 100 or 0
	cpu_item:set(colored(percent_label(cpu), threshold_color(cpu, CPU_THRESHOLDS)))
	ram_item:set(colored(percent_label(ram_percent), PRESSURE_COLORS[tonumber(env.MEM_PRESSURE)] or colors.status.normal))
	disk_item:set(colored(
		{ string = string.format("%s/%s", format_disk(disk_total - disk_free), format_disk(disk_total)) },
		threshold_color(disk_percent, DISK_THRESHOLDS)
	))
end

gear:subscribe("system_stats", function(env)
	last_env = env
	if popup_open then
		render()
	end
end)

-- While pinned it stays open, so do not reopen.
hit:subscribe("mouse.entered", function()
	if popup_open then
		return
	end
	popup_open = true
	render()
	anchor:set({ popup = { drawing = true } })
end)

local pin = ui.pin(function(active)
	bracket:set({ background = { border_color = active and colors.pinned_border or colors.bracket.border_color } })
end)

-- Also close on mouse.exited.global when leaving the bar.
hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
	if pin.active then
		return
	end
	popup_open = false
	anchor:set({ popup = { drawing = false } })
end)

-- The btm window pkgs/btm-window is outside AeroSpace's management and overlays the current workspace. The workspace does not switch.
local BTM_APP_NAME = "btm-window"
local TOGGLE_BTM_COMMAND = string.format("pkill -USR1 -x %s || { nohup %s >/dev/null 2>&1 & }", BTM_APP_NAME, BTM_APP_NAME)

-- When frontmost, invert the colors like aerospace's workspace. See highlight in items/aerospace.lua.
local function set_btm_state(state)
	local pill_color = {
		front = colors.space.bg_focused,
		background = colors.dim,
	}
	local color = pill_color[state]
	gear:set({
		icon = { color = color and colors.space.fg_focused or colors.white },
		background = { drawing = color ~= nil, color = color },
	})
end

-- So that the result of an old query does not overwrite the new state, reflect only the last query.
local btm_query = ui.latest()

-- The window becoming frontmost, losing focus, or closing are all detected by front_app_switched. INFO is the name of the app brought to the front.
-- Right after the window closes, wait a little so that pgrep does not run before the process has fully exited.
gear:subscribe("front_app_switched", function(env)
	local is_latest = btm_query.begin()
	if env.INFO == BTM_APP_NAME then
		set_btm_state("front")
		return
	end
	sbar.exec("sleep 0.3; pgrep -x " .. BTM_APP_NAME, function(output)
		if not is_latest() then
			return
		end
		set_btm_state((output or ""):match("%d") and "background" or "none")
	end)
end)

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		sbar.exec(TOGGLE_BTM_COMMAND)
	elseif env.BUTTON == "right" then
		pin.toggle(popup_open)
	end
end)
