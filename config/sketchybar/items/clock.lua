local ui = require("ui")

-- Glyph height of digits and Latin letters. Measured 9.9 for Hack Nerd Font Bold 13pt with CoreText.
-- Re-measure if the font or size changes.
local GLYPH_HEIGHT = 10

-- Spacing is determined by the bracket's padding, so the empty icon is hidden and the label's inner padding is 0.
-- Fix the label width. Only when the string ends in "4" is the text width 1px wider, which would shift the whole right-aligned item.
-- Measured with Hack Nerd Font Bold 13pt: the text width is 140px, and 141px only when it ends in "4".
-- The inner padding of the icon and label is 0, so the maximum text width is used as is.
-- Re-measure if the font or size changes.
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
