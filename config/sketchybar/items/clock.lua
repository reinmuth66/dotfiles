local ui = require("ui")

ui.add_item("clock", "right", {
	label = {
		string = os.date("%m/%d %a %H:%M:%S"),
		font = { style = "Bold" },
		-- 末尾が "4" のときだけ文字列幅が 1px 広がり、右寄せのアイテム全体がずれるため固定する。
		-- 実測値 (Hack Nerd Font Bold 13pt)。フォントやサイズを変えたら再測定が必要。
		width = 149,
	},
})

ui.add_bracket("clock.bracket", { "clock" })
ui.add_spacer("right", ui.bracket_gap)
