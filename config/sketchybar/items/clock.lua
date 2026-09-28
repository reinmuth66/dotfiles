sbar.add("item", "clock", {
	position = "right",
	label = {
		string = os.date("%m/%d %a %H:%M"),
		font = { style = "Bold" },
	},
})
