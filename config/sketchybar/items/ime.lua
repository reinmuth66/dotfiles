local ui = require("ui")

local ime = ui.add_item("ime", "right", {
	icon = { drawing = false },
	-- 余白は bracket の padding で決めるため、ラベル内側の padding は 0 にする
	label = { font = { family = "Hack Nerd Font", style = "Bold" }, padding_left = 0, padding_right = 0 },
})

ui.add_bracket("ime.bracket", { ime }, nil, ui.bracket_padding)
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
