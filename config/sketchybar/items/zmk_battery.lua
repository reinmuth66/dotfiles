local colors = require("colors")
local paths = require("paths")
local ui = require("ui")

local snapshot_path = paths.home
	.. "/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json"

-- This is the rightmost item, so add_label sets the label's own padding_right to 0 and the margin is decided only by central_padding_right.
local LABEL = {
	font_size = 11,
	central_padding_right = ui.bracket_padding,
}

-- sketchybar places the nub shifted to the right by the label's padding_right.
-- Verified on the actual device. Changing central_padding_right from 5 to 8 also moved the nub 3px to the right.
-- Subtract that amount from gap so that it looks the same as the gap of 2 calibrated on the actual device when central_padding_right was 5.
-- outline and nub are adjacent with no gap when their padding_right values are equal. Confirmed by verification of sketchybar on the actual device.
-- The outline side uses NUB.gap as is.
local NUB = {
	width = 1,
	height = 4,
	corner_radius = 1,
	gap = LABEL.central_padding_right - 3,
}

local BAR = {
	width = 18,
	height = 10,
	border_width = 1,
	corner_radius = 2,
	inset = 1,
}

-- Always fix the label width for the three digits that fit "100%". Shared by central and peripheral.
-- If the width changed with the digit count, the item to the left would move and the gap to the Spotify popup on the right would change, so it is fixed regardless of digit count.
-- For the popup, see items/spotify.lua.
-- The value was measured by setting "45%" and "100%" to width=1 on the actual device, deliberately making it insufficient, and checking the size of bounding_rects.
-- size is the actual width after sketchybar automatically overrode and widened it, and includes 4px of the label's inner padding on each of left and right.
-- From that, 4px is subtracted for the padding_right set to 0 in add_label.
-- Re-measure if LABEL.font_size is changed.
-- The label is align=right, so with two digits the leftover becomes the gap between the bar and the text.
--
-- The number's position is moved in integer px of label.padding_right while staying right-aligned. Larger moves it left; smaller, or negative, moves it right.
-- Changing padding_right does not change the label width. Verified on the actual device. sketchybar labels have no x_offset.
-- Specify per digit count; the key is the digit count. The three-digit "100%" fills the width, so it cannot be made larger than 0.
local LABEL_PADDING_RIGHT = { [2] = 2, [3] = 0 }
local LABEL_GAP_EXTRA = 1
local LABEL_WIDTH = 32 + LABEL_GAP_EXTRA -- "100%" measured 35px - padding_right 4px + 1px spare

-- An estimate proportional to LABEL.font_size going from 9pt to 11pt.
-- The actual font size has not been visually confirmed, so check on the actual device that the two upper and lower rows do not overlap.
local ROW_OFFSET = 7

sbar.add("event", "zmk_battery_update")

local function add_label(name, width, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = width,
		padding_right = padding_right,
		icon = { drawing = false },
		label = {
			font = { size = LABEL.font_size },
			y_offset = row_offset,
			align = "right",
			padding_right = 0,
		},
	})
end

local function add_nub(name, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = NUB.width,
		padding_right = padding_right,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.white,
			corner_radius = NUB.corner_radius,
			height = NUB.height,
			y_offset = row_offset,
			drawing = true,
		},
	})
end

-- This is the item at the left edge of the bracket, so the margin from the bracket's left edge to the bar is decided by padding_left.
-- The central and peripheral outlines overlap at the same position, so give both the same value.
local function add_outline(name, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = BAR.width,
		padding_right = padding_right,
		padding_left = ui.bracket_padding,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.transparent,
			border_color = colors.white,
			border_width = BAR.border_width,
			corner_radius = BAR.corner_radius,
			height = BAR.height,
			y_offset = row_offset,
			drawing = true,
		},
	})
end

local function add_fill(name, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = 0,
		padding_right = padding_right,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.white,
			corner_radius = math.max(BAR.corner_radius - BAR.inset, 0),
			height = BAR.height - BAR.border_width * 2 - BAR.inset * 2,
			y_offset = row_offset,
			drawing = true,
		},
	})
end

-- sketchybar lays out position-right items from right to left in the order added, and each item's coordinate can only be controlled by its own padding_right.
-- padding_left does not affect placement and is only included in the bracket's extent. add_outline uses it as the left margin.
-- Here the central label, nub, and outline are added first, and the peripheral label, nub, and outline are inserted right after them.
-- Then for the peripheral side, subtracting the central group's total width group_offset from padding_right is enough to overlay it directly under central.
-- central_nub and central_outline are placed by sketchybar to match the width of central_label.
local GROUP_OFFSET = LABEL_WIDTH + NUB.width + BAR.width
local PERIPHERAL_OUTLINE_PADDING_RIGHT = NUB.gap - GROUP_OFFSET

-- central_fill is added right after peripheral_outline, so compute relative to that value. This is BASE.
-- Furthermore, retreat inward by inset equally on left and right. This is DRAW_BASE, the same idea as the top/bottom height calculation.
local CENTRAL_FILL_BASE_PADDING_RIGHT = PERIPHERAL_OUTLINE_PADDING_RIGHT - BAR.border_width
local CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT = CENTRAL_FILL_BASE_PADDING_RIGHT - BAR.inset

local central_label = add_label("central", LABEL_WIDTH, LABEL.central_padding_right, ROW_OFFSET)
local central_nub = add_nub("central_nub", NUB.gap, ROW_OFFSET)
local central_outline = add_outline("central_outline", NUB.gap, ROW_OFFSET)

local peripheral_label =
	add_label("peripheral", LABEL_WIDTH, LABEL.central_padding_right - GROUP_OFFSET, -ROW_OFFSET)
local peripheral_nub = add_nub("peripheral_nub", NUB.gap - GROUP_OFFSET, -ROW_OFFSET)
local peripheral_outline = add_outline("peripheral_outline", PERIPHERAL_OUTLINE_PADDING_RIGHT, -ROW_OFFSET)

local central_fill = add_fill("central_fill", CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT, ROW_OFFSET)
local peripheral_fill = add_fill("peripheral_fill", -BAR.border_width - BAR.inset, -ROW_OFFSET)

local central = { label = central_label, nub = central_nub, outline = central_outline, fill = central_fill }
local peripheral =
	{ label = peripheral_label, nub = peripheral_nub, outline = peripheral_outline, fill = peripheral_fill }

-- Because of the negative padding_right used to stack the two rows, a gap wider than it looks is created to the left neighbor item.
-- Adjust the padding_right of the spacer placed to the left of the bracket so that the measured gap to the ime bracket on the left
-- is closed up to be the same as between other brackets, that is, as when a normal spacer is placed between them. ui.close_gap does the adjustment.
-- The spacer must be created after the bracket. Verified on the actual device. It does not take effect unless the width is automatic. See ui.add_spacer.
local GAP_SETTLE_DELAY = 0.3

ui.add_bracket("zmk_battery.bracket", { "/zmk_battery\\..*/" })

-- Must be created after the bracket. Not included in the members.
local hit = ui.add_hit_region("zmk_battery.hit", 0, 0, 0, { drawing = false })

local gap_spacer = ui.add_spacer("right", ui.bracket_gap, "zmk_battery_gap")

local gap_timer = ui.timer()

local function settle_gap()
	gap_timer.start(GAP_SETTLE_DELAY, function()
		ui.close_gap({
			left = "ime.bracket",
			right = "zmk_battery.bracket",
			spacer = gap_spacer,
			spacing = ui.bracket_gap,
		})
	end)
end

-- When not connected, do not hide it but show it in a dim color. apply_group does this.
local function hide_group(group)
	group.nub:set({ drawing = false })
	group.outline:set({ drawing = false })
	group.fill:set({ drawing = false })
	group.label:set({ drawing = false })
end

-- sketchybar keeps width and padding_right each independently truncated toward 0. Confirmed by verification on the actual device.
-- Passing fractions can make the sum of width + padding_right differ from the expectation, so truncate fill_width here first.
-- This keeps subtraction from the integer base value an integer, and no error from sketchybar's rounding arises.
local function trunc(x)
	return x >= 0 and math.floor(x) or math.ceil(x)
end

local function fill_width_for(level)
	local inner_width = BAR.width - BAR.border_width * 2 - BAR.inset * 2
	local clamped_level = math.max(0, math.min(100, level))
	return trunc(inner_width * clamped_level / 100)
end

-- "--%" has the same 3 characters as "05%", so it fits the fixed width.
-- Only the fill bar's position calculation differs between central and peripheral, so it is passed via fill_padding_right_for.
-- The label is zero-padded only for a single digit so that the width does not change between 9% and 10%. Same as battery.
-- An item with width specified advances placement by width, so chain_width is counted as the sum of widths. See ui.hit_region_geometry.
local function apply_group(group, state, fill_padding_right_for)
	local color = state.current and colors.white or colors.dim
	local fill_width = state.level and fill_width_for(state.level) or 0
	local fill_padding_right = fill_padding_right_for(fill_width)

	group.nub:set({ drawing = true, background = { color = color } })
	group.outline:set({ drawing = true, background = { border_color = color } })
	group.fill:set({
		drawing = true,
		width = fill_width,
		padding_right = fill_padding_right,
		background = { color = color },
	})
	local text = state.level and string.format("%02d%%", trunc(state.level)) or "--%"
	group.label:set({
		drawing = true,
		label = { string = text, color = color, padding_right = LABEL_PADDING_RIGHT[#text - 1] },
	})

	local chain_width = LABEL_WIDTH + NUB.width + BAR.width + fill_width

	return fill_padding_right, chain_width
end

local last_central_fill_padding_right = CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT

local function apply_central(state)
	local fill_padding_right, chain_width = apply_group(central, state, function(fill_width)
		return CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT - fill_width
	end)
	last_central_fill_padding_right = fill_padding_right
	return chain_width
end

local function apply_peripheral(state)
	local _, chain_width = apply_group(peripheral, state, function(fill_width)
		return last_central_fill_padding_right - fill_width
	end)
	return chain_width
end

local function apply_hit(chain_width)
	local bracket_width = LABEL_WIDTH + NUB.width + NUB.gap + BAR.width + ui.bracket_padding
	local geometry = ui.hit_region_geometry(chain_width, 0, bracket_width)
	geometry.drawing = true
	hit:set(geometry)
	return bracket_width
end

-- Before the first update all items are hidden and there is no baseline to compare with, so nil. The shift in the meantime is measured and closed by settle_gap.
local last_chain_width, last_bracket_width

-- The adjacent item's position is determined by the difference between chain_width, the width by which sketchybar advances placement in this bracket, and bracket_width, the width of the bracket's background.
-- When the bar changes the two change separately, so the gap changes by the increase in chain_width - the increase in bracket_width.
-- Verified on the actual device. Making fill 1px thinner shifts the left neighbor 1px to the right. Moving the spacer's padding_right by the same amount keeps the gap unchanged.
-- Relying only on re-measurement by settle_gap would leave the left neighbor's position off during GAP_SETTLE_DELAY.
-- settle_gap is left to fix errors this model cannot capture, for example switching peripheral presence.
-- As with ui.close_gap, it updates by the difference from the spacer's current value, so it is not doubled even if settle_gap already corrected it.
local function apply_gap(chain_width, bracket_width, current_padding_right)
	if last_chain_width ~= nil then
		local delta = (chain_width - last_chain_width) - (bracket_width - last_bracket_width)
		gap_spacer:set({ padding_right = current_padding_right - delta })
	end
	last_chain_width, last_bracket_width = chain_width, bracket_width
end

-- zmk-battery-center keeps the last level in levelPercent even when not connected, and sets valueStatus to "stale".
-- It becomes stale when connectionStatus is unknown or disconnected, or the latest read failed.
-- If no value has ever been obtained, levelPercent is null and valueStatus is "unavailable".
-- Show in normal white only for "current"; otherwise dim it.
local function state_from(fields)
	if fields == nil then
		return { level = nil, current = false }
	end
	return { level = tonumber(fields[2]), current = fields[3] == "current" }
end

local SNAPSHOT_COMMAND = "jq -r '.devices[0] as $d | if $d == null then empty else "
	.. '$d.batteryParts[] | [.id, (.levelPercent | tostring), (.valueStatus // "unavailable")] | @tsv end\' '
	.. '"'
	.. snapshot_path
	.. '" 2>/dev/null'

-- Combine the sets from begin_config to end_config into one message.
-- If sent separately, sketchybar would render one frame of the half-finished layout in between, and the left neighbor item would shift momentarily.
-- Verified on the actual device. Setting fill and spacer separately moves it 1px for one frame; with a single message it does not move.
-- Queries cannot be made inside a batch, so fetch the spacer's current value beforehand.
-- The computation of peripheral_fill depends on central_fill's padding_right, so always process central first. central is always shown.
local function update()
	sbar.exec(SNAPSHOT_COMMAND, function(result)
		local central_fields, peripheral_fields
		for line in (result or ""):gmatch("[^\r\n]+") do
			local fields = {}
			for field in line:gmatch("([^\t]+)") do
				table.insert(fields, field)
			end

			if fields[1] == "central" then
				central_fields = fields
			elseif not peripheral_fields then
				peripheral_fields = fields
			end
		end

		local central_state = state_from(central_fields)
		local peripheral_state = state_from(peripheral_fields)

		local gap_padding_right = sbar.query(gap_spacer.name).geometry.padding_right
		sbar.begin_config()

		local chain_width = apply_central(central_state)

		if peripheral_fields then
			chain_width = chain_width + apply_peripheral(peripheral_state)
		else
			hide_group(peripheral)
		end

		local bracket_width = apply_hit(chain_width)
		apply_gap(chain_width, bracket_width, gap_padding_right)
		sbar.end_config()
		settle_gap()
	end)
end

central.label:subscribe({ "forced", "system_woke", "zmk_battery_update" }, update)

local function toggle_main_window()
	local script = [[
tell application "System Events"
	if (count of windows of process "zmk-battery-center") > 0 then
		activate
	else
		tell process "zmk-battery-center"
			perform action "AXPress" of menu item "Show" of menu 1 of menu bar item 1 of menu bar 2
		end tell
	end if
end tell
]]

	sbar.exec("osascript -e '" .. script .. "' 2>/dev/null")
end

-- Clicks are received by a hit layer covering the whole bracket. Do not subscribe each item.
hit:subscribe("mouse.clicked", toggle_main_window)
