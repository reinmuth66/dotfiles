local ui = require("ui")

-- 中身で最も高いアイコンの字面の高さ (px)。Hack Nerd Font Bold 18pt を CoreText で実測 (15.0)。
-- label (13pt、9.7) はこれより低い。bracket の上下の余白と、左右の余白をそろえるのに使う。
-- フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 15

local battery = ui.add_item("battery", "right", {
	update_freq = 120,
	-- 余白は bracket の padding で決めるため、左端(icon)と右端(label)の内側の padding は 0 にする
	icon = { font = { size = 18.0 }, y_offset = 1, padding_left = 0, padding_right = 3 },
	label = { padding_left = 3, padding_right = 0 },
})

ui.add_bracket("battery.bracket", { battery }, nil, ui.vertical_margin(GLYPH_HEIGHT))
ui.add_spacer("right", ui.bracket_gap)

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
-- 実測値 (Hack Nerd Font Bold 13pt): label の固定幅は内側の padding を含む。
-- 文字幅 + padding_left(3) で、"45%"/"100%" の順に 27/34px。
-- 1桁は "05%" のように 0 埋めして2桁として扱うので、1桁用の幅は持たない。
-- フォントやサイズ、label の padding を変えたら再測定が必要。
local LABEL_WIDTH_BY_DIGITS = { [2] = 27, [3] = 34 }

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

		-- 1桁のときだけ 0 埋めして、9% と 10% で幅が変わらないようにする
		local text = string.format("%02d%%", charge)
		battery:set({
			icon = icon_for(charge, charging),
			label = { string = text, width = LABEL_WIDTH_BY_DIGITS[#text - 1] },
		})
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, update)
