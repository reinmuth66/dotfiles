local ui = require("ui")

-- 数字と英字の字面の高さ (px)。Hack Nerd Font Bold 13pt を CoreText で実測 (9.9)。
-- bracket の上下の余白と、左右の余白をそろえるのに使う。フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 10

-- 余白は bracket の padding で決めるため、空のアイコンは非表示にし、
-- ラベル内側の padding は 0 にする
local clock = ui.add_item("clock", "right", {
	icon = { drawing = false },
	label = {
		padding_left = 0,
		padding_right = 0,
		string = os.date("%m/%d %a %H:%M:%S"),
		-- 末尾が "4" のときだけ文字列幅が 1px 広がり、右寄せのアイテム全体がずれるため固定する。
		-- 実測値 (Hack Nerd Font Bold 13pt): 文字幅は140px、末尾が "4" のときだけ141px。
		-- アイコンとラベル内側の padding は 0 なので、文字幅の最大値をそのまま使う。
		-- フォントやサイズを変えたら再測定が必要。
		width = 141,
	},
})

ui.add_bracket("clock.bracket", { clock }, nil, ui.vertical_margin(GLYPH_HEIGHT))
ui.add_spacer("right", ui.bracket_gap)
