local ui = require("ui")

-- 英大文字の字面の高さ (px)。Hack Nerd Font Bold 16pt を CoreText で実測 (11.7)。
-- bracket の上下の余白と、左右の余白をそろえるのに使う。フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 12

local ime = ui.add_item("ime", "right", {
	icon = { drawing = false },
	label = {
		font = { size = 16.0 },
		padding_left = 0,
		padding_right = 0,
		-- "JP" と "EN" で描画幅が 1px 違う ("EN" が 18px、"JP" が 19px) ため、切り替えで
		-- bracket の幅が変わる。最大値に固定する。
		-- 実測値 (Hack Nerd Font Bold 16pt): フォントやサイズを変えたら再測定が必要。
		width = 19,
	},
})

-- 字面の左右には、label の端から約 1px の空き (字の側面の余白) があるので、その分を引いて
-- 見た目の左右の余白を上下にそろえる (実測: 左 0.9〜1.3px、右 0.4〜0.7px の平均が約 0.8px)。
local SIDE_BEARING = 1

ui.add_bracket("ime.bracket", { ime }, nil, ui.vertical_margin(GLYPH_HEIGHT) - SIDE_BEARING)
ui.add_spacer("right", ui.bracket_gap)

sbar.add("event", "input_source_change", "AppleSelectedInputSourcesChangedNotification")

local function update()
	sbar.exec("macism", function(source)
		if source == nil then
			return
		end

		source = source:match("^%s*(.-)%s*$")

		if source:find("Japanese") then
			ime:set({ label = "JA" })
		else
			ime:set({ label = "EN" })
		end
	end)
end

ime:subscribe("input_source_change", update)
update()
