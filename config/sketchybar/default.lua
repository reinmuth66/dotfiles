local colors = require("colors")

sbar.default({
	padding_left = 5,
	padding_right = 5,
	icon = {
		font = { family = "Hack Nerd Font", style = "Bold", size = 17.0 },
		color = colors.white,
		padding_left = 4,
		padding_right = 4,
	},
	label = {
		font = { family = "Hack Nerd Font", style = "Regular", size = 17.0 },
		color = colors.white,
		padding_left = 4,
		padding_right = 4,
	},
	updates = "on",
})
