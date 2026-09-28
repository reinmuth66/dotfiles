local colors = require("colors")

local snapshot_path = os.getenv("HOME")
	.. "/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json"

local function icon_for(level)
	if level >= 90 then
		return ""
	elseif level >= 60 then
		return ""
	elseif level >= 30 then
		return ""
	elseif level >= 10 then
		return ""
	else
		return ""
	end
end

local BAR = {
	width = 20,
	height = 8,
	border_width = 1,
	corner_radius = 2,
	inset = 0,
	gap = 4,
}

sbar.add("event", "zmk_battery_update")

local central_outline = sbar.add("item", "zmk_battery.central_outline", {
	position = "right",
	drawing = false,
	width = BAR.width,
	padding_right = BAR.gap,
	icon = { drawing = false },
	label = { drawing = false },
	background = {
		color = 0x00000000,
		border_color = colors.white,
		border_width = BAR.border_width,
		corner_radius = BAR.corner_radius,
		height = BAR.height,
		drawing = true,
	},
})

local central_fill = sbar.add("item", "zmk_battery.central_fill", {
	position = "right",
	drawing = false,
	width = 0,
	padding_right = BAR.gap - BAR.border_width - BAR.inset,
	icon = { drawing = false },
	label = { drawing = false },
	background = {
		color = colors.white,
		corner_radius = math.max(BAR.corner_radius - BAR.inset, 0),
		height = BAR.height - BAR.inset * 2,
		drawing = true,
	},
})

local central = sbar.add("item", "zmk_battery.central", {
	position = "right",
	drawing = false,
	icon = { drawing = false },
})

local peripheral = sbar.add("item", "zmk_battery.peripheral", {
	position = "right",
	drawing = false,
})

local function apply_central(connection_status, level_str)
	local level = tonumber(level_str)
	if connection_status ~= "connected" or level == nil then
		central_outline:set({ drawing = false })
		central_fill:set({ drawing = false })
		central:set({ drawing = false })
		return
	end

	local inner_width = BAR.width - BAR.border_width * 2 - BAR.inset * 2
	local clamped_level = math.max(0, math.min(100, level))
	local fill_width = inner_width * clamped_level / 100
	local fill_padding_right = BAR.gap - BAR.border_width - BAR.inset - fill_width

	central_outline:set({ drawing = true })
	central_fill:set({ drawing = true, width = fill_width, padding_right = fill_padding_right })
	central:set({ drawing = true, label = level .. "%" })
end

local function apply(item, connection_status, level_str)
	local level = tonumber(level_str)
	if connection_status ~= "connected" or level == nil then
		item:set({ drawing = false })
		return
	end

	item:set({ drawing = true, icon = icon_for(level), label = level .. "%" })
end

local function update()
	local cmd = "jq -r '.devices[0] as $d | if $d == null then empty else "
		.. "$d.connectionStatus as $cs | $d.batteryParts[] | [$cs, .id, (.levelPercent | tostring)] | @tsv end' "
		.. '"'
		.. snapshot_path
		.. '" 2>/dev/null'

	sbar.exec(cmd, function(result)
		if result == nil or result == "" then
			central_outline:set({ drawing = false })
			central_fill:set({ drawing = false })
			central:set({ drawing = false })
			peripheral:set({ drawing = false })
			return
		end

		local seen_peripheral = false
		for line in result:gmatch("[^\r\n]+") do
			local fields = {}
			for field in line:gmatch("([^\t]+)") do
				table.insert(fields, field)
			end

			local connection_status, id, level_str = fields[1], fields[2], fields[3]
			if id == "central" then
				apply_central(connection_status, level_str)
			elseif not seen_peripheral then
				seen_peripheral = true
				apply(peripheral, connection_status, level_str)
			end
		end

		if not seen_peripheral then
			peripheral:set({ drawing = false })
		end
	end)
end

central:subscribe({ "forced", "system_woke", "zmk_battery_update" }, update)

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

central_outline:subscribe("mouse.clicked", toggle_main_window)
central_fill:subscribe("mouse.clicked", toggle_main_window)
central:subscribe("mouse.clicked", toggle_main_window)
peripheral:subscribe("mouse.clicked", toggle_main_window)
