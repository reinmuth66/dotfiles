local ui = require("ui")

-- 英大文字の字面の高さ (px)。Hack Nerd Font Bold 13pt を CoreText で実測 (9.7)。
-- bracket の上下の余白と、左右の余白をそろえるのに使う。フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 10

local ime = ui.add_item("ime", "right", {
	icon = { drawing = false },
	label = { padding_left = 0, padding_right = 0 },
})

ui.add_bracket("ime.bracket", { ime }, nil, ui.vertical_margin(GLYPH_HEIGHT))
ui.add_spacer("right", ui.bracket_gap)

sbar.add("event", "input_source_change", "AppleSelectedInputSourcesChangedNotification")

local function update()
	sbar.exec("macism", function(source)
		if source == nil then
			return
		end

		source = source:match("^%s*(.-)%s*$")

		if source:find("Japanese") then
			ime:set({ label = "JP" })
		else
			ime:set({ label = "EN" })
		end
	end)
end

ime:subscribe("input_source_change", update)
update()
