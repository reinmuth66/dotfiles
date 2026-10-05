sbar.bar({
	position = "top",
	height = 40,
	blur_radius = 0,
	color = 0x00000000,
	-- 内蔵ディスプレイのノッチの幅 (pt)。position "q" / "e" の item はこの両脇に並ぶ。
	-- 既定は 200。NSScreen の frame 幅 - auxiliaryTopLeftArea 幅 - auxiliaryTopRightArea 幅 (1710 - 751 - 750) で実測した。
	notch_width = 209,
})
