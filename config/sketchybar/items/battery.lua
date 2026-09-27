local battery = sbar.add("item", "battery", {
	position = "right",
	update_freq = 120,
})

local icons = {
	[100] = "󰁹",
	[90] = "󰂂",
	[80] = "󰂁",
	[70] = "󰂀",
	[60] = "󰁿",
	[50] = "󰁾",
	[40] = "󰁽",
	[30] = "󰁼",
	[20] = "󰁻",
	[10] = "󰁺",
	[0] = "󰂎",
}

local CHARGING_ICON = "󰂄"

local function icon_for(charge, charging)
	if charging then
		return CHARGING_ICON
	end

	local bucket = charge >= 100 and 100 or math.floor(charge / 10) * 10
	return icons[bucket]
end

local function update()
	sbar.exec("pmset -g batt", function(batt_info)
		if batt_info == nil then
			return
		end

		local charge = tonumber(batt_info:match("(%d+)%%"))
		if charge == nil then
			return
		end

		local charging = batt_info:find("AC Power") ~= nil

		battery:set({ icon = icon_for(charge, charging), label = charge .. "%" })
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, update)
