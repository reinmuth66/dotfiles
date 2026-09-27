local ime = sbar.add("item", "ime", {
	position = "right",
	icon = { drawing = false },
})

sbar.add("event", "input_source_change", "AppleSelectedInputSourcesChangedNotification")

local function update()
	sbar.exec("macism", function(source)
		if source == nil then
			return
		end

		source = source:match("^%s*(.-)%s*$")

		if source:find("Japanese") then
			ime:set({ label = "あ" })
		else
			ime:set({ label = "A" })
		end
	end)
end

ime:subscribe("input_source_change", update)
update()
