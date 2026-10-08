local colors = require("colors")
local ui = require("ui")
local popup_state = require("popup_state")

-- アクティビティモニターのアイコンの item。ホバーで、CPU・メモリ・スワップ・ネットワークの数字とグラフのポップアップを開く。
-- データは helper/system.c (sketchybar-system-helper) が一定間隔で測り、system_stats イベントで渡す。
-- 測定は helper がカーネルの API を直接呼ぶだけなので軽い。この item は、ポップアップが閉じている間は
-- 履歴を貯めるだけで、描画の指示 (set / push) は出さない。
--
-- ポップアップは横並び (horizontal) にして、中身の item をすべて width = 0 にする。横並びでは、width = 0 の item の
-- 次が同じ x から始まるので、item が同じ位置に重なる (spotify.lua と同じ方法)。縦の位置は y_offset で決める
-- (ポップアップの縦の中央からの距離。上が正)。縦並びだと、item は高さの分だけ順に積まれるので重ねられない。
-- 数字は bottom (btm。pkgs/btm-window が表示する) と同じ値・同じ書式にしてある (値の測り方は helper/system.c)。
-- 行 (LINES) は、見出しと、同じ行に描くグラフ (series) の組。layout で、行の作りを決める:
--   overlay: CPU。グラフを重ねる行 (複数あれば数字は上下 2 段。いまは CPU の 1 本だけ)。
--   mirror:  Net。受信 (rx) を上半分に通常のグラフ、送信 (tx) を下半分に上下反転して描く。
--   text:    RAM、Swap、I/O、ディスクの空き。グラフにしない行 (数字だけ、または円グラフ)。

-- アイコンのサイズ (pt)。sketchybar-app-font の :activity_monitor: は、字面がほぼ一辺 SIZE の正方形になる
-- (CoreText で実測。20pt で 19.96 x 19.24)。箱の幅も SIZE にする。フォントやサイズを変えたら再測定が必要。
local SIZE = 20

-- グラフの幅 (pt)。SketchyBar のグラフは 1pt が 1 点なので、点の数でもある (helper の間隔 1 秒 x 点数が履歴の長さ。約 1 分)
local GRAPH_WIDTH = 60
local GRAPH_HEIGHT = 18
local ROW_HEIGHT = 26
local TITLE_WIDTH = 52
-- 数字の列の幅
local VALUE_WIDTH = 120
local ROW_PADDING = 8
local CONTENT_WIDTH = TITLE_WIDTH + GRAPH_WIDTH + VALUE_WIDTH

-- mirror の行 (Net) の上半分と下半分のグラフの高さ (pt。偶数にする)。2 つを隙間なく (余白 0 で) 隣り合わせる。
-- SketchyBar のグラフは、背景の高さ - 1 の高さで描かれ、線の太さ (1pt) の分だけ上にずれる (graph.c の graph_calculate_bounds)。
-- なので、背景の高さは MIRROR_HALF + 1 にし、位置は MIRROR_LANE_SHIFT で補正する。
local MIRROR_HALF = 18
local MIRROR_ROW_HEIGHT = 2 * MIRROR_HALF + 4
local MIRROR_LANE_SHIFT = 1
-- 数字を上下 2 段に分けるときの、行の中央からの距離 (pt)
local LABEL_SPLIT = 6

-- 行。上から順に並べる。height は偶数にする。
--   graph の行 (overlay / mirror) は series にグラフを並べる。text の行は、数字だけ (または円グラフ) で、グラフを持たない。
local LINES = {
	{ key = "cpu", title = "CPU", height = ROW_HEIGHT, layout = "overlay", series = { "cpu" } },
	{ key = "ram", height = ROW_HEIGHT, layout = "text" },
	{ key = "swap", height = ROW_HEIGHT, layout = "text" },
	{ key = "net", title = "Net", height = MIRROR_ROW_HEIGHT, layout = "mirror", series = { "rx", "tx" } },
	{ key = "io", height = ROW_HEIGHT, layout = "text" },
	{ key = "disk", height = ROW_HEIGHT, layout = "text" },
}

-- ポップアップの高さと、各行の中央 (ポップアップの縦の中央からの距離。上が正)
local POPUP_HEIGHT = 0
for _, line in ipairs(LINES) do
	POPUP_HEIGHT = POPUP_HEIGHT + line.height
end
local row_top = POPUP_HEIGHT // 2
local line_of = {}
for _, line in ipairs(LINES) do
	line.center = row_top - line.height // 2
	row_top = row_top - line.height
	line_of[line.key] = line
end

-- ディスクの円グラフ (ドーナツ)。表示は DONUT_SIZE (pt)、画像は表示と同じ実ピクセル数 (窓の解像度 2.0 倍) で描く。
-- SketchyBar の窓は補間なし (window.c の kCGInterpolationNone) で画像を描くので、縮小すると円周の縁が間引かれて
-- ギザギザになる。等倍で貼れば、ImageMagick のアンチエイリアスがそのまま見える。
-- ファイルから読んだ画像の表示サイズは 実ピクセル * scale (pt)。高さ 32pt にそろえるのは、リンク画像 (media.artwork)
-- だけ (image.c の image_calculate_bounds)。なので scale = 表示サイズ / 実ピクセル = 0.5 (窓の解像度が 2.0 なので等倍)。
local DONUT_SIZE = 22
local DONUT_PX = DONUT_SIZE * 2
local DONUT_STROKE = DONUT_PX * 0.14
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/system"

-- ネットワークのグラフは、履歴の最大値の RATE_SCALE_HEADROOM 倍を天井 (1) にして、0〜1 にそろえる。
-- 最大値で天井に張り付かないよう余裕を持たせる。下限は置かず、通信が 0 のときだけ RATE_SCALE_ZERO を使う (ビット/秒)。
-- bottom (btm) と同じ決め方 (src/canvas/widgets/network_graph.rs の adjust_network_data_point)。
local RATE_SCALE_HEADROOM = 1.5
local RATE_SCALE_ZERO = 1

-- helper が送るイベント。helper が起動するより先に登録しておく (未登録のイベントは --trigger できない)
sbar.add("event", "system_stats")

-- ノッチの右隣 (position "e") に置く。ノッチとの間隔は spacer で作る (ui.add_notch_spacer)。
-- ノッチに最も近い位置に置くので、gear より先に追加する。
ui.add_notch_spacer("e", "system.notch_gap")

-- bracket は円にする。幅を高さ (colors.bracket.height) と同じにし、角の半径は短辺の半分にする。
-- 円の中にアイコンが同心で収まるよう、アイコンの左右に余白 (ICON_PADDING) を取る。
local BRACKET_WIDTH = colors.bracket.height
local ICON_PADDING = (BRACKET_WIDTH - SIZE) / 2

-- item の width は指定しない。width を指定した item の後は、配置が width の分しか進まず、bracket の padding が
-- 数えられないので、隣の item が padding の分だけ重なる (ui.add_hit_layer の説明)。幅は icon.width で決める。
-- 余白は item の padding ではなく icon の padding にして、item の幅を bracket の幅 (円の直径) と同じにする。
-- ポップアップは item の端にそろう (align = "right" は item の右端) ので、item が bracket より狭いと、
-- ポップアップの右端が円の端からずれる。icon.width は padding を含む箱の全幅 (spotify.lua)。
local gear = ui.add_item("system", "e", {
	icon = {
		string = ":activity_monitor:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		width = BRACKET_WIDTH,
		-- 字面は箱の左端 + padding_left から描かれる (spotify.lua)。字面は幅 19.96 なので、円の中心より 0.02 pt 左に寄るだけ。
		align = "left",
		padding_left = ICON_PADDING,
		padding_right = 0,
	},
	label = { drawing = false },
	popup = {
		align = "right",
		horizontal = true,
		height = POPUP_HEIGHT,
		background = colors.popup,
	},
})

local bracket = ui.add_bracket("system.bracket", { gear }, {
	background = { corner_radius = colors.bracket.height / 2 },
}, 0)

-- bracket 全体でマウス操作を受ける (ui.add_hit_layer_over)。item の幅は自動なので、配置が進む幅 (chain) は
-- bracket の幅と同じ
local hit = ui.add_hit_layer_over("system.hit", BRACKET_WIDTH, BRACKET_WIDTH, { position = "e" })

-- 数字の書式は btm (src/utils/data_units.rs、conversion.rs) と同じ。
-- 10 進接頭辞 (1 KB = 1000 B) で、値は 1 回の割り算で出す (btm の get_decimal_bytes、get_unit_prefix)
local DECIMAL_BYTES = { { 1e12, "TB" }, { 1e9, "GB" }, { 1e6, "MB" }, { 1e3, "KB" } }
local DECIMAL_PREFIXES = { { 1e12, "T" }, { 1e9, "G" }, { 1e6, "M" }, { 1e3, "K" } }

local function split_unit(value, units, base_unit)
	for _, entry in ipairs(units) do
		if value >= entry[1] then
			return value / entry[1], entry[2]
		end
	end
	return value, base_unit
end

-- ネットワークの速度 (bit/s)。btm の RX / TX と同じ「12.3Mb/s」の形
local function format_bit_rate(bits)
	local value, prefix = split_unit(bits, DECIMAL_PREFIXES, "")
	return string.format("%.1f%sb/s", value, prefix)
end

-- ディスク I/O の速度 (byte/s)。btm の dec_bytes_per_second_string と同じ (1 GB/s 以上だけ小数 1 桁)。
-- 取れなかったとき (helper が負の値を送る) は、btm と同じ N/A
local function format_byte_rate(bytes)
	if bytes < 0 then
		return "N/A"
	end
	local value, unit = split_unit(bytes, DECIMAL_BYTES, "B")
	return string.format(bytes >= 1e9 and "%.1f%s/s" or "%.0f%s/s", value, unit)
end

-- ディスクの空き・総容量 (byte)。btm の disk widget と同じ「325GB」の形
local function format_disk(bytes)
	local value, unit = split_unit(bytes, DECIMAL_BYTES, "B")
	return string.format("%.0f%s", value, unit)
end

-- メモリ・スワップ (byte)。btm の memory_legend_label と同じ「 45%   12.3GiB/16.0GiB」の形。
-- 単位は総量で決め (2 進接頭辞。1 GiB = 1024^3 B)、使用量と総量を同じ単位で出す。
-- 総量が 0 のとき (スワップが無いとき) は、btm と同じ文字列を出す
local BINARY_UNITS = { { 1024 ^ 4, "TiB" }, { 1024 ^ 3, "GiB" }, { 1024 ^ 2, "MiB" }, { 1024, "KiB" } }

local function format_memory(used, total)
	if total <= 0 then
		return "  0%   0.0B/0.0B"
	end
	local denominator, unit = 1, "B"
	for _, entry in ipairs(BINARY_UNITS) do
		if total >= entry[1] then
			denominator, unit = entry[1], entry[2]
			break
		end
	end
	return string.format("%3.0f%%   %.1f%s/%.1f%s", used / total * 100, used / denominator, unit, total / denominator, unit)
end

-- グラフ (series) の定義。どの行のどこに置くかは LINES が決める。
--   point(env): グラフに積む値 (そのまま履歴に入る。0〜1 にする割り算は scale で行う)
--   scale(): 履歴全体を割る値 (固定なら 1)
--   text(env): 右の数字
--   flip: 上下反転して描く (mirror の下半分)
local function fixed()
	return 1
end

local ROWS -- 下で定義する。rate_scale が履歴を読む

-- 同じ group の系列 (受信と送信) は、同じ値で割る (上下で高さを比べられるように)。
-- 履歴の最大値の RATE_SCALE_HEADROOM 倍で 0〜1 にそろえる
local function rate_scale(group)
	return function()
		local max = 0
		for _, row in ipairs(ROWS) do
			if row.group == group then
				for _, v in ipairs(row.values) do
					if v > max then
						max = v
					end
				end
			end
		end
		return max > 0 and max * RATE_SCALE_HEADROOM or RATE_SCALE_ZERO
	end
end

ROWS = {
	{
		name = "cpu",
		point = function(env)
			return tonumber(env.CPU) / 100
		end,
		scale = fixed,
		text = function(env)
			return string.format("%.0f%%", tonumber(env.CPU))
		end,
	},
	{
		name = "rx",
		group = "net",
		point = function(env)
			return tonumber(env.NET_RX)
		end,
		scale = rate_scale("net"),
		text = function(env)
			return "\u{2193} " .. format_bit_rate(tonumber(env.NET_RX)) -- 下向きの矢印: 受信
		end,
	},
	{
		name = "tx",
		group = "net",
		flip = true,
		point = function(env)
			return tonumber(env.NET_TX)
		end,
		scale = rate_scale("net"),
		text = function(env)
			return "\u{2191} " .. format_bit_rate(tonumber(env.NET_TX)) -- 上向きの矢印: 送信
		end,
	},
}

local series = {}
for _, row in ipairs(ROWS) do
	row.values = {}
	series[row.name] = row
end

local GRAPH_COLOR = 0xccffffff
local GRAPH_FILL_COLOR = 0x33ffffff

-- 上下反転は、SketchyBar のグラフにない (基準線は下端で、上へ伸びる) ので、補集合で描く。
-- 値 v のかわりに 1 - v を積み、塗りをポップアップの背景色にすると、基準線 (下端) から 1 - v の高さまでが背景色になり、
-- 残りの、上端 (中央線) から v の深さが抜けて見える。抜けた所に、後ろに敷いた板 (FLIP_BASE_COLOR) の色が出る。
-- 板は、グラフと同じ位置と大きさの slider の背景 (percentage 0) で、グラフより先に追加する。
-- 抜けた所の色は板の色、折れ線は GRAPH_COLOR。板は半透明なので、塗りの所もポップアップより少しだけ明るく見える。
local FLIP_BASE_COLOR = GRAPH_FILL_COLOR
-- グラフの折れ線と塗りは、右端の 2pt 手前 (GRAPH_WIDTH - 2) までしか描かれない (graph.c の graph_draw)。板が右へはみ出すと、
-- 塗りで隠れず、細い帯になって見える。板の幅をその分だけ狭める。
local FLIP_BASE_INSET = 2
local FLIP_FILL_COLOR = colors.popup.color

-- 左右の余白と、中身の幅の確保に使う空の item
local function add_popup_spacer(name, width)
	return sbar.add("item", name, {
		position = "popup.system",
		width = width,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
	})
end

-- 見出し。描かないとき (title が nil) も、空の文字で幅 (TITLE_WIDTH) を取る。
-- グラフは icon の右から描かれるので、幅が 0 だとグラフが左へずれる。
local function icon_props(title, y_offset)
	return {
		string = title or "",
		font = ui.popup_font(12.0),
		color = colors.dim,
		width = TITLE_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
		y_offset = y_offset or 0,
	}
end

add_popup_spacer("system.pad.left", ROW_PADDING)

for _, line in ipairs(LINES) do
	for i, name in ipairs(line.series or {}) do
		local row = series[name]
		local overlay = line.layout == "overlay"
		-- グラフの位置 (y_offset) と、数字の位置 (label.y_offset)
		local y, label_y, graph_height
		if overlay then
			y = line.center
			label_y = #line.series == 1 and 0 or (i == 1 and LABEL_SPLIT or -LABEL_SPLIT)
			graph_height = GRAPH_HEIGHT
		else
			y = line.center + (i == 1 and MIRROR_HALF // 2 or -(MIRROR_HALF // 2)) - MIRROR_LANE_SHIFT
			label_y = 0
			graph_height = MIRROR_HALF + 1
		end
		-- 見出しは行の最初のグラフに持たせ、行の中央に合わせる
		local title_y = i == 1 and line.center - y or 0

		if row.flip then
			sbar.add("slider", "system." .. name .. ".base", GRAPH_WIDTH - FLIP_BASE_INSET, {
				position = "popup.system",
				width = 0,
				y_offset = y,
				padding_left = 0,
				padding_right = 0,
				icon = icon_props(nil),
				label = { drawing = false },
				slider = {
					percentage = 0,
					background = {
						height = MIRROR_HALF,
						corner_radius = 0,
						color = FLIP_BASE_COLOR,
						y_offset = MIRROR_LANE_SHIFT,
					},
				},
			})
		end

		row.item = sbar.add("graph", "system." .. name, GRAPH_WIDTH, {
			position = "popup.system",
			width = 0,
			y_offset = y,
			padding_left = 0,
			padding_right = 0,
			icon = icon_props(i == 1 and line.title or nil, title_y),
			label = {
				string = "",
				font = ui.popup_font(10.0, "tnum"),
				width = VALUE_WIDTH,
				align = "right",
				padding_left = 8,
				padding_right = 0,
				y_offset = label_y,
			},
			-- 背景に高さを指定すると、グラフはその中に描かれる
			background = { drawing = true, color = 0x00000000, height = graph_height },
			graph = {
				color = GRAPH_COLOR,
				fill_color = row.flip and FLIP_FILL_COLOR or GRAPH_FILL_COLOR,
				line_width = 1.0,
			},
		})
	end
end

local last_env
local last_percent -- 空き (%)。円グラフの画像を選ぶ
local popup_open = false

-- ディスクの行: 見出し | 円グラフ (空きの割合) | 空き / 総容量。
-- 円グラフの画像は、空きの割合 (整数 %) ごとに 1 枚、magick で描いて cache に置く。
-- 画像の位置は背景の左端からの距離 (image.padding_left) で決まるので、真ん中の列 (グラフの幅) の中央に置く。
-- メモリとスワップの行: 見出し | 使用率と使用量 / 総量 (btm の RAM、SWP と同じ書式)。グラフにしない (使用率は 7 割台で平らに
-- 張り付き、スワップはほぼ 0 なので、形が情報にならない。読みたいのは、足りているか)。
-- メモリの色は、メモリ圧力 (normal / warn / critical) で変える。スワップは、使い始めたら (足りていない合図) 色を変える。
local PRESSURE_COLORS = { [1] = colors.white, [2] = 0xffffb454, [4] = 0xffff5555 }
local SWAP_USED_COLOR = colors.swap.alert | 0xff000000

-- 数字は、右の列 (グラフの幅 + 数字の幅) の右端にそろえる (I/O、ディスクの行と同じ)
local function memory_item(name, title, line)
	return sbar.add("item", "system." .. name, {
		position = "popup.system",
		width = 0,
		y_offset = line.center,
		padding_left = 0,
		padding_right = 0,
		icon = icon_props(title),
		label = {
			string = "",
			font = ui.popup_font(12.0, "tnum"),
			width = GRAPH_WIDTH + VALUE_WIDTH,
			align = "right",
			padding_left = 8,
			padding_right = 0,
		},
	})
end

local ram = memory_item("ram", "RAM", line_of.ram)
local swap = memory_item("swap", "Swap", line_of.swap)

-- ディスク I/O の行: 見出し | 読み / 書きの速度 (数字だけ)。
-- I/O は、平常時の KB/s の揺れに、数百 MB/s のバーストが散発的に混ざるので、グラフにしても形が情報にならない。
-- 値は helper の間隔 (1 秒) の平均で、デバイスに届いた量 (アプリの read / write ではない。ページキャッシュを通った分は含まない)。
local io = sbar.add("item", "system.io", {
	position = "popup.system",
	width = 0,
	y_offset = line_of.io.center,
	padding_left = 0,
	padding_right = 0,
	icon = {
		string = "I/O",
		font = ui.popup_font(12.0),
		color = colors.dim,
		width = TITLE_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = {
		string = "",
		font = ui.popup_font(12.0, "tnum"),
		width = GRAPH_WIDTH + VALUE_WIDTH,
		align = "right",
		padding_left = 8,
		padding_right = 0,
	},
})

local disk = sbar.add("item", "system.disk", {
	position = "popup.system",
	width = 0,
	y_offset = line_of.disk.center,
	padding_left = 0,
	padding_right = 0,
	icon = {
		string = "Free",
		font = ui.popup_font(12.0),
		color = colors.dim,
		width = TITLE_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = {
		string = "",
		font = ui.popup_font(12.0, "tnum"),
		width = GRAPH_WIDTH + VALUE_WIDTH,
		align = "right",
		padding_left = 8,
		padding_right = 0,
	},
	background = {
		drawing = true,
		color = 0x00000000,
		image = {
			string = "",
			drawing = false,
			scale = DONUT_SIZE / DONUT_PX,
			padding_left = TITLE_WIDTH + (GRAPH_WIDTH - DONUT_SIZE) / 2,
		},
	},
})

-- 中身の item はすべて width = 0 で、同じ x から重なる。その右に置く空の item が、中身の幅を確保する
-- (spotify.lua の spotify.viz と同じ)。
add_popup_spacer("system.content", CONTENT_WIDTH)
add_popup_spacer("system.pad.right", ROW_PADDING)

-- 画像は 1 ファイルだけを使い回す (値ごとのキャッシュも、一時ファイルも作らない)。
-- SketchyBar が画像を読むのは --set した時だけなので、描き終わってから --set すれば、書き込み途中は読まれない。
local DONUT_PATH = CACHE_DIR .. "/disk.png"

-- 空き percent % のドーナツを描く。12 時から時計回りに空き (明るい)、残りを使用済み (薄い) にする。
-- 成功したときだけ ok を出力する。
local function donut_command(percent)
	local center = DONUT_PX / 2
	local radius = center - DONUT_STROKE / 2
	local arc
	if percent >= 100 then
		arc = string.format("ellipse %g,%g %g,%g 0,360", center, center, radius, radius)
	elseif percent <= 0 then
		arc = nil
	else
		arc = string.format(
			"arc %g,%g %g,%g -90,%g",
			center - radius,
			center - radius,
			center + radius,
			center + radius,
			-90 + 360 * percent / 100
		)
	end
	return string.format(
		[[mkdir -p %q && magick -size %dx%d xc:none -fill none -strokewidth %g -stroke 'rgba(255,255,255,0.2)' -draw 'ellipse %g,%g %g,%g 0,360' %s %q && echo ok]],
		CACHE_DIR,
		DONUT_PX,
		DONUT_PX,
		DONUT_STROKE,
		center,
		center,
		radius,
		radius,
		arc and string.format("-stroke 'rgba(255,255,255,0.85)' -draw '%s'", arc) or "",
		DONUT_PATH
	)
end

local donut_shown -- いま出している画像の空き (%)
local donut_wanted -- 出したい空き (%)
local donut_busy = false -- 描画中。同じファイルへ書くので、描画は 1 本ずつにする

local function render_donut()
	if donut_busy or donut_wanted == donut_shown then
		return
	end
	local percent = donut_wanted
	donut_busy = true
	sbar.exec(donut_command(percent), function(result)
		donut_busy = false
		if tostring(result):match("^ok") then
			donut_shown = percent
			disk:set({ background = { image = { string = DONUT_PATH, drawing = true } } })
			-- 描いている間に値が変わっていたら、続けて描き直す (失敗したときは次の更新で再試行する)
			render_donut()
		end
	end)
end

local function show_donut(percent)
	donut_wanted = percent
	render_donut()
end

-- 履歴の全体を積み直す。左が古く、右が新しいグラフにする。点が足りない分 (古い側) は 0 で埋める。
-- ネットワークは、履歴の最大値が変わると全体の高さが変わるので、毎回積み直す。
-- 並べ方は 2 つの癖に合わせる (実機とソースで確認):
--   - SbarLua の push は、table の値を逆順 (後ろから) に SketchyBar へ送る。
--   - SketchyBar は、ポップアップの中のグラフを、最後に積んだ点を左端に、その手前の点を右へ向かって描く
--     (右の item のグラフだけ逆向き)。さらに、描き始めに、最初に積んだ点から左端へ線を引く。
-- 結果として、points[1] が左端 (最も古い)、points[GRAPH_WIDTH - 1] が右端 (最新) になる。
-- points[GRAPH_WIDTH] は描き始めの点で、左端と同じ値にして、余計な縦線が出ないようにする。
-- 上下反転 (flip) のグラフは、1 - v を積む (FLIP_FILL_COLOR の説明)。点が足りない分 (値 0) は 1 になる。
local function render()
	if last_env == nil then
		return
	end
	local shown = GRAPH_WIDTH - 1
	for _, row in ipairs(ROWS) do
		local values = row.values
		local scale = row.scale()
		local count = #values
		local points = {}
		for i = 1, shown do
			local index = count - shown + i
			local v = index >= 1 and math.min(values[index] / scale, 1) or 0
			points[i] = row.flip and 1 - v or v
		end
		points[GRAPH_WIDTH] = points[1]
		row.item:set({ label = { string = row.text(last_env) } })
		row.item:push(points)
	end

	ram:set({
		label = {
			string = format_memory(tonumber(last_env.RAM_USED), tonumber(last_env.RAM_TOTAL)),
			color = PRESSURE_COLORS[tonumber(last_env.MEM_PRESSURE)] or colors.white,
		},
	})
	local swap_used = tonumber(last_env.SWAP_USED)
	swap:set({
		label = {
			string = format_memory(swap_used, tonumber(last_env.SWAP_TOTAL)),
			color = swap_used > 0 and SWAP_USED_COLOR or colors.dim,
		},
	})

	io:set({
		label = {
			string = string.format(
				"R %s    W %s",
				format_byte_rate(tonumber(last_env.DISK_READ)),
				format_byte_rate(tonumber(last_env.DISK_WRITE))
			),
		},
	})

	local total = tonumber(last_env.DISK_TOTAL)
	if total and total > 0 then
		local free = tonumber(last_env.DISK_FREE)
		last_percent = math.floor(100 * free / total + 0.5)
		disk:set({ label = { string = string.format("%s / %s", format_disk(free), format_disk(total)) } })
		show_donut(last_percent)
	end
end

gear:subscribe("system_stats", function(env)
	for _, row in ipairs(ROWS) do
		local values = row.values
		values[#values + 1] = row.point(env)
		if #values > GRAPH_WIDTH then
			table.remove(values, 1)
		end
	end
	last_env = env
	if popup_open then
		render()
	end
end)

hit:subscribe("mouse.entered", function()
	-- ピン留め中は開いたままなので、開き直さない
	if popup_open then
		return
	end
	popup_open = true
	popup_state.system_open = true
	render()
	gear:set({ popup = { drawing = true } })
end)

-- 右クリックでピン留めした状態。ピン留め中は、マウスが外れてもポップアップを閉じない。
-- もう一度右クリックすると外す。ピン留め中は bracket の枠線が白くなる (spotify.lua と同じ)。
local pinned = false
local PINNED_BORDER_COLOR = 0xffffffff -- ピン留め中の bracket の枠線の色 (普段は colors.bracket.border_color)

-- ピン留めの状態を変え、bracket の枠線の色で示す
local function set_pinned(value)
	pinned = value
	bracket:set({ background = { border_color = value and PINNED_BORDER_COLOR or colors.bracket.border_color } })
end

-- バーの外へ出たときは mouse.exited.global でも閉じる。ピン留め中は閉じない
hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
	if pinned then
		return
	end
	popup_open = false
	popup_state.system_open = false
	gear:set({ popup = { drawing = false } })
end)

-- btm の窓 (pkgs/btm-window) の開閉。起動中なら SIGUSR1 を送り、窓が最前面なら閉じ、そうでなければ前に出させる。
-- 起動していなければ起動する。窓は AeroSpace の管理外で、今の workspace の上に重なる (workspace は切り替わらない)。
local TOGGLE_BTM_COMMAND = "pkill -USR1 -x btm-window || { nohup btm-window >/dev/null 2>&1 & }"

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		sbar.exec(TOGGLE_BTM_COMMAND)
	elseif env.BUTTON == "right" then
		-- ポップアップが開いていないときは、ピン留めしない。外すのはいつでもできる
		if pinned then
			set_pinned(false)
		elseif popup_open then
			set_pinned(true)
		end
	end
end)
