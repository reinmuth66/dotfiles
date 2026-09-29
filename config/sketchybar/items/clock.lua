sbar.add("item", "clock", {
	position = "right",
	label = {
		string = os.date("%m/%d %a %H:%M:%S"),
		font = { style = "Bold" },
	},
})
