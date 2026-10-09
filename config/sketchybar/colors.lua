-- 無彩色の色 (ARGB) はここにまとめる。
-- Spotify のポップアップの配色は palette.lua (default はそこで定義) が決める。
local black = 0xff000000
local white = 0xffffffff

return {
	black = black,
	white = white,
	transparent = 0x00000000,
	dim = 0x99ffffff, -- 無効・未接続・未起動の表示。白の約 60%

	space = {
		fg = 0x66ffffff,
		fg_focused = black,
		bg_focused = 0xffdddddd,
		bg_inactive = 0x44dddddd, -- bg_focused を薄くした色。btm の窓が起動中だが最前面ではないときの pill
	},

	bracket = {
		color = 0x66000000,
		border_color = 0x44ffffff,
		pinned_border_color = white, -- ピン留め中の枠線
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

	swap = {
		alert = 0xaaff0000,
	},
}
