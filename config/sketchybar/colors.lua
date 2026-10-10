-- Achromatic colors are collected here as ARGB.
-- The Spotify popup colors are derived from the album art by palette.lua. colors.popup is the default used when they cannot be determined.
local black = 0xff000000
local white = 0xffffffff
local light_gray = 0xffdddddd
local dim = 0x99ffffff

return {
	white = white,
	transparent = 0x00000000,
	dim = dim,
	pinned_border = light_gray, -- same as space.bg_focused

	space = {
		fg = dim,
		fg_focused = black,
		bg_focused = light_gray,
	},

	bracket = {
		color = 0x66000000,
		border_color = 0x44ffffff,
		border_width = 1,
		corner_radius = 5,
		height = 34,
	},

	-- The wallpaper popup uses this color as is.
	-- The background and border are not made transparent. The border is colors.bracket.border_color (0x44ffffff) composited over black.
	popup = {
		border_width = 1,
		corner_radius = 5,
		bg = black,
		border = 0xff444444,
	},

	spotify = {
		overlay_paused = 0x99000000,
		bracket_bg = black,
	},

	status = {
		normal = white,
		warn = 0xffffb454,
		critical = 0xffff5555,
	},
}
