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

sbar.add("event", "zmk_battery_update")

local central = sbar.add("item", "zmk_battery.central", {
	position = "right",
	update_freq = 60,
	drawing = false,
})

local peripheral = sbar.add("item", "zmk_battery.peripheral", {
	position = "right",
	drawing = false,
})

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
				apply(central, connection_status, level_str)
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

central:subscribe({ "routine", "forced", "system_woke", "zmk_battery_update" }, update)

local function show_main_window()
	local script = [[
tell application "System Events"
	tell process "zmk-battery-center"
		perform action "AXPress" of menu item "Show" of menu 1 of menu bar item 1 of menu bar 2
	end tell
end tell
]]

	sbar.exec("osascript -e '" .. script .. "' 2>/dev/null")
end

central:subscribe("mouse.clicked", show_main_window)
peripheral:subscribe("mouse.clicked", show_main_window)
