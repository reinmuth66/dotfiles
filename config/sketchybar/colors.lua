-- 無彩色の色 (ARGB) はここにまとめる。
-- Spotify のポップアップの配色は、アルバム画像から palette.lua が決める (colors.popup の色は、決められないときの既定)。
local black = 0xff000000
local white = 0xffffffff
local light_gray = 0xffdddddd
local dim = 0x99ffffff -- 無効・未接続・未起動の表示。白の約 60%

return {
	white = white,
	transparent = 0x00000000,
	dim = dim,
	pinned_border = light_gray, -- ピン留め中の bracket の枠線 (space.bg_focused と同じ)

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

	-- 形と、既定の色。Spotify のポップアップは、画像から配色を決める (palette.lua。palette.default がここの色を使う)。
	-- 壁紙のポップアップは、この色のまま使う。
	popup = {
		border_width = 1,
		corner_radius = 5,
		bg = black,
		-- 背景と枠は透過させない。bracket の半透明の枠 (colors.bracket.border_color の 0x44ffffff) を、黒の上に重ねた色にしてある。
		border = 0xff444444,
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
