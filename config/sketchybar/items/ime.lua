local ui = require("ui")

-- Glyph height of uppercase Latin letters. Measured 11.7 for Hack Nerd Font Bold 16pt with CoreText.
-- Re-measure if the font or size changes.
local GLYPH_HEIGHT = 12

-- Fix the label width to the maximum. JP and EN render 1px apart (EN is 18px, JP is 19px),
-- so the bracket width would change on every switch.
-- Measured with Hack Nerd Font Bold 16pt; re-measure if the font or size changes.
local ime = ui.add_item("ime", "right", {
	icon = { drawing = false },
	label = {
		font = { size = 16.0 },
		padding_left = 0,
		padding_right = 0,
		width = 19,
	},
})

-- The glyph has about 1px of space from the label edge on both sides, so subtract that to even out the visible left/right margins with the top/bottom.
-- Measured 0.9 to 1.3px on the left and 0.4 to 0.7px on the right, averaging about 0.8px.
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
