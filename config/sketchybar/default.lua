local colors = require("colors")

-- Return a fresh table on every call so that the table passed to sbar.default is not shared
local function font()
	return { family = "Hack Nerd Font", style = "Bold", size = 13.0 }
end

sbar.default({
	padding_left = 5,
	padding_right = 5,
	icon = {
		font = font(),
		color = colors.white,
		padding_left = 4,
		padding_right = 4,
	},
	label = {
		font = font(),
		color = colors.white,
		padding_left = 4,
		padding_right = 4,
	},
	updates = "on",
})
