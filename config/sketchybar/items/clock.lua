local ui = require("ui")

-- 余白は bracket の padding で決めるため、空のアイコンは非表示にし、
-- ラベル内側の padding は 0 にする
local clock = ui.add_item("clock", "right", {
	icon = { drawing = false },
	label = {
		padding_left = 0,
		padding_right = 0,
		string = os.date("%m/%d %a %H:%M:%S"),
		font = { style = "Bold" },
		-- 末尾が "4" のときだけ文字列幅が 1px 広がり、右寄せのアイテム全体がずれるため固定する。
		-- 実測値 (Hack Nerd Font Bold 13pt): 文字幅は140px、末尾が "4" のときだけ141px。
		-- アイコンとラベル内側の padding は 0 なので、文字幅の最大値をそのまま使う。
		-- フォントやサイズを変えたら再測定が必要。
		width = 141,
	},
})

ui.add_bracket("clock.bracket", { clock }, nil, ui.bracket_padding)
ui.add_spacer("right", ui.bracket_gap)
