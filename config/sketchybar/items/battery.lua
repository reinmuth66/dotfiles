local ui = require("ui")

-- 中身で最も高いアイコンの字面の高さ。Hack Nerd Font Bold 18pt を CoreText で実測して 15.0、label の 13pt は 9.7。
-- フォントやサイズを変えたら再測定する。
local GLYPH_HEIGHT = 15

-- label の幅は、add_item の label.width で、"100%" が収まる 34px に常に固定する。
-- 桁数や先頭の文字で幅が変わると左隣の item がずれる。先頭が "1" と "5" のときは文字列幅が 1px 狭くなる。
-- 左隣の network が動くと items/spotify.lua のポップアップとの隙間も変わるため、桁数にかかわらず固定する。
-- Hack Nerd Font Bold 13pt の実測は、label の固定幅が内側の padding を含み、文字幅 + padding_left の 3 になる。
-- "45%" が 27px、"100%" が 34px。1 桁は "05%" のように 0 埋めして 2 桁として扱う。
-- フォントやサイズ、label の padding を変えたら再測定する。
--
-- 字面は label の左端 + padding_left から描かれ、padding_left を変えても label の幅 34 と item の幅は変わらない。
-- 実機で確認した。sketchybar の label には x_offset がない。
-- 3 桁の "100%" は幅いっぱいなので 3。2 桁の "45%" は余りの 7px を左右に分けると、左に 3.5px 足す位置 6.5 が中央で、
-- 整数の 6 か 7 から選ぶ。大きくすると右へ、小さくすると左へ動く。
local LABEL_PADDING_LEFT = { [2] = 8, [3] = 3 }

-- 余白は bracket の padding で決めるため、左端の icon と右端の label の内側の padding は 0 にする。
local battery = ui.add_item("battery", "right", {
	update_freq = 120,
	icon = { font = { size = 18.0 }, y_offset = 1, padding_left = 0, padding_right = 3 },
	label = { padding_left = LABEL_PADDING_LEFT[2], padding_right = 0, width = 34, align = "left" },
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

local function icon_for(charge, charging)
	if charging then
		return CHARGING_ICON
	end

	local bucket = charge >= 100 and 100 or math.floor(charge / 10) * 10
	return icons[bucket]
end

-- 1桁のときだけ 0 埋めして、9% と 10% で幅が変わらないようにする。
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

		local text = string.format("%02d%%", charge)
		battery:set({
			icon = icon_for(charge, charging),
			label = { string = text, padding_left = LABEL_PADDING_LEFT[#text - 1] },
		})
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, update)
