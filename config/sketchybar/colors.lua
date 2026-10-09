-- 無彩色の色 (ARGB) はここにまとめる。
-- Spotify のポップアップの配色は palette.lua (default はそこで定義) が決める。
local black = 0xff000000
local white = 0xffffffff
local light_gray = 0xffdddddd
local dim = 0x99ffffff -- 無効・未接続・未起動の表示。白の約 60%

return {
	black = black,
	white = white,
	transparent = 0x00000000,
	light_gray = light_gray,
	dim = dim,

	space = {
		fg = dim,
		fg_focused = black,
		bg_focused = light_gray,
	},

	bracket = {
		color = 0x66000000,
		border_color = 0x44ffffff,
		pinned_border_color = light_gray, -- ピン留め中の枠線 (space.bg_focused と同じ)
		border_width = 1,
		corner_radius = 5,
		height = 34,
	},

	-- 色は palette.lua が決める。ここは形だけ。
	popup = {
		border_width = 1,
		corner_radius = 5,
	},

	spotify = {
		overlay_paused = 0x99000000, -- 一時停止中に画像へ重ねる覆い
		bracket_bg = black,
	},

	-- 使用状況の警告色 (system のポップアップの CPU、RAM、Disk)
	status = {
		normal = white,
		warn = 0xffffb454,
		critical = 0xffff5555,
	},
}
