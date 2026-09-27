local clock = sbar.add("item", "clock", {
	position = "right",
	update_freq = 10,
})

local function update()
	clock:set({ label = os.date("%m/%d %a %H:%M") })
end

clock:subscribe("routine", update)
clock:subscribe("forced", update)
