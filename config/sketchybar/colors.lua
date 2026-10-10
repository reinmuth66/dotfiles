-- 無彩色の色は ARGB でここにまとめる。
-- Spotify のポップアップの配色は palette.lua がアルバム画像から決める。colors.popup は決められないときの既定。
local black = 0xff000000
local white = 0xffffffff
local light_gray = 0xffdddddd
local dim = 0x99ffffff

return {
	white = white,
	transparent = 0x00000000,
	dim = dim,
	pinned_border = light_gray, -- space.bg_focused と同じ

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

	-- 壁紙のポップアップは、この色のまま使う。
	-- 背景と枠は透過させない。枠は colors.bracket.border_color の 0x44ffffff を、黒に重ねた色にしてある。
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
