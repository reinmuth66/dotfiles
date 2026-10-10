local colors = require("colors")

-- sbar.default に渡す表を共有しないよう、呼ぶたびに新しい表を返す
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
