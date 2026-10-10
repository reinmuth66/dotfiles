local ui = require("ui")

-- 英大文字の字面の高さ。Hack Nerd Font Bold 16pt を CoreText で実測した 11.7。
-- フォントやサイズを変えたら再測定する。
local GLYPH_HEIGHT = 12

-- label の width は最大値に固定する。JP と EN で描画幅が 1px 違い、EN が 18px、JP が 19px なので、
-- 切り替えで bracket の幅が変わってしまう。
-- 実測は Hack Nerd Font Bold 16pt で、フォントやサイズを変えたら再測定する。
local ime = ui.add_item("ime", "right", {
	icon = { drawing = false },
	label = {
		font = { size = 16.0 },
		padding_left = 0,
		padding_right = 0,
		width = 19,
	},
})

-- 字面の左右には label の端から約 1px の空きがあるので、その分を引いて見た目の左右の余白を上下にそろえる。
-- 実測は左 0.9〜1.3px、右 0.4〜0.7px で、平均は約 0.8px。
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
