local ui = require("ui")

-- 数字と英字の字面の高さ。Hack Nerd Font Bold 13pt を CoreText で実測した 9.9。
-- フォントやサイズを変えたら再測定する。
local GLYPH_HEIGHT = 10

-- 余白は bracket の padding で決めるため、空のアイコンは非表示、ラベル内側の padding は 0 にする。
-- label の width は固定する。末尾が "4" のときだけ文字列幅が 1px 広がり、右寄せの item 全体がずれるため。
-- Hack Nerd Font Bold 13pt の実測は、文字幅が 140px、末尾が "4" のときだけ 141px。
-- アイコンとラベル内側の padding は 0 なので、幅は文字幅の最大値をそのまま使う。
-- フォントやサイズを変えたら再測定する。
local clock = ui.add_item("clock", "right", {
	icon = { drawing = false },
	label = {
		padding_left = 0,
		padding_right = 0,
		string = os.date("%m/%d %a %H:%M:%S"),
		width = 141,
	},
})

ui.add_bracket("clock.bracket", { clock }, nil, ui.vertical_margin(GLYPH_HEIGHT))
ui.add_spacer("right", ui.bracket_gap)
