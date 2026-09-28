local colors = require("colors")

local snapshot_path = os.getenv("HOME")
	.. "/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json"

local NUB = {
	width = 1,
	height = 4,
	corner_radius = 1,
	gap = 6,
}

local BAR = {
	width = 20,
	height = 8,
	border_width = 1,
	corner_radius = 2,
	inset = 0,
	outline_gap = NUB.gap,
}

local LABEL = {
	width = 40,
	font_size = 9,
	central_padding_right = 5,
	peripheral_base_padding_right = -55.8,
}

local ROW_OFFSET = 9

sbar.add("event", "zmk_battery_update")

local function create_bar_group(prefix, row_offset)
	local label = sbar.add("item", "zmk_battery." .. prefix, {
		position = "right",
		drawing = false,
		width = LABEL.width,
		icon = { drawing = false },
		label = {
			font = { size = LABEL.font_size },
			y_offset = row_offset,
		},
	})

	local nub = sbar.add("item", "zmk_battery." .. prefix .. "_nub", {
		position = "right",
		drawing = false,
		width = NUB.width,
		padding_right = NUB.gap,
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

	local outline = sbar.add("item", "zmk_battery." .. prefix .. "_outline", {
		position = "right",
		drawing = false,
		width = BAR.width,
		padding_right = BAR.outline_gap,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = 0x00000000,
			border_color = colors.white,
			border_width = BAR.border_width,
			corner_radius = BAR.corner_radius,
			height = BAR.height,
			y_offset = row_offset,
			drawing = true,
		},
	})

	local fill = sbar.add("item", "zmk_battery." .. prefix .. "_fill", {
		position = "right",
		drawing = false,
		width = 0,
		padding_right = BAR.outline_gap - BAR.border_width - BAR.inset,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.white,
			corner_radius = math.max(BAR.corner_radius - BAR.inset, 0),
			height = BAR.height - BAR.inset * 2,
			y_offset = row_offset,
			drawing = true,
		},
	})

	return { label = label, nub = nub, outline = outline, fill = fill }
end

local central = create_bar_group("central", ROW_OFFSET)
local peripheral = create_bar_group("peripheral", -ROW_OFFSET)

local function hide_group(group)
	group.nub:set({ drawing = false })
	group.outline:set({ drawing = false })
	group.fill:set({ drawing = false })
	group.label:set({ drawing = false })
end

local function apply_group(group, connection_status, level_str, delta)
	delta = delta or 0
	local level = tonumber(level_str)
	if connection_status ~= "connected" or level == nil then
		hide_group(group)
		return nil
	end

	local inner_width = BAR.width - BAR.border_width * 2 - BAR.inset * 2
	local clamped_level = math.max(0, math.min(100, level))
	local fill_width = inner_width * clamped_level / 100
	local outline_padding_right = BAR.outline_gap + delta
	local fill_padding_right = outline_padding_right - BAR.border_width - BAR.inset - fill_width

	group.nub:set({ drawing = true, padding_right = NUB.gap + delta })
	group.outline:set({ drawing = true, padding_right = outline_padding_right })
	group.fill:set({ drawing = true, width = fill_width, padding_right = fill_padding_right })
	group.label:set({ drawing = true, label = level .. "%", padding_right = LABEL.central_padding_right + delta })

	return fill_width
end

local function apply_central(connection_status, level_str)
	return apply_group(central, connection_status, level_str, 0)
end

local function apply_peripheral(connection_status, level_str, central_fill_width)
	central_fill_width = central_fill_width or 0
	local delta = LABEL.peripheral_base_padding_right - LABEL.central_padding_right - central_fill_width
	apply_group(peripheral, connection_status, level_str, delta)
end

local function update()
	local cmd = "jq -r '.devices[0] as $d | if $d == null then empty else "
		.. "$d.connectionStatus as $cs | $d.batteryParts[] | [$cs, .id, (.levelPercent | tostring)] | @tsv end' "
		.. '"'
		.. snapshot_path
		.. '" 2>/dev/null'

	sbar.exec(cmd, function(result)
		if result == nil or result == "" then
			hide_group(central)
			hide_group(peripheral)
			return
		end

		local central_fields, peripheral_fields
		for line in result:gmatch("[^\r\n]+") do
			local fields = {}
			for field in line:gmatch("([^\t]+)") do
				table.insert(fields, field)
			end

			if fields[2] == "central" then
				central_fields = fields
			elseif not peripheral_fields then
				peripheral_fields = fields
			end
		end

		local central_fill_width = 0
		if central_fields then
			central_fill_width = apply_central(central_fields[1], central_fields[3]) or 0
		else
			hide_group(central)
		end

		if peripheral_fields then
			apply_peripheral(peripheral_fields[1], peripheral_fields[3], central_fill_width)
		else
			hide_group(peripheral)
		end
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

for _, group in pairs({ central, peripheral }) do
	group.nub:subscribe("mouse.clicked", toggle_main_window)
	group.outline:subscribe("mouse.clicked", toggle_main_window)
	group.fill:subscribe("mouse.clicked", toggle_main_window)
	group.label:subscribe("mouse.clicked", toggle_main_window)
end
