local ui = require("ui")

local ime = ui.add_item("ime", "right", {
	icon = { drawing = false },
	label = { font = { family = "Hack Nerd Font", style = "Bold" } },
})

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
