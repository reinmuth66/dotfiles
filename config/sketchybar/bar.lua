local colors = require("colors")
local ui = require("ui")

sbar.bar({
	position = "top",
	height = ui.bar_height,
	blur_radius = 0,
	color = colors.transparent,
	-- position "q" / "e" の item はノッチの両脇に並ぶ。既定は 200 (実測値は ui.lua)。
	notch_width = ui.notch_width,
})
