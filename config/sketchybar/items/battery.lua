local battery = sbar.add("item", "battery", {
	position = "right",
	update_freq = 120,
	icon = { font = { size = 18.0 }, y_offset = 1, padding_right = 3 },
	label = { font = { style = "Bold" }, padding_left = 3 },
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

-- 先頭が "1" "5" のときだけ文字列幅が 1px 狭くなり、左隣のアイテムがずれるため、桁数ごとに幅を固定する。
-- 実測値 (Hack Nerd Font Bold 13pt): アイテム幅 40/48/55px から余白 17px を引いた値。
-- フォントやサイズ、label の padding を変えたら再測定が必要。
local LABEL_WIDTH_BY_DIGITS = { [1] = 23, [2] = 31, [3] = 38 }

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

		local text = charge .. "%"
		battery:set({
			icon = icon_for(charge, charging),
			label = { string = text, width = LABEL_WIDTH_BY_DIGITS[#text - 1] },
		})
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, update)
