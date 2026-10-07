local colors = require("colors")
local ui = require("ui")

-- 歯車の item。ホバーで、CPU・メモリ・スワップ・ネットワークの数字とグラフのポップアップを開く。
-- データは helper/system.c (sketchybar-system-helper) が一定間隔で測り、system_stats イベントで渡す。
-- 測定は helper がカーネルの API を直接呼ぶだけなので軽い。この item は、ポップアップが閉じている間は
-- 履歴を貯めるだけで、描画の指示 (set / push) は出さない。

-- アイコンのサイズ (pt)。sketchybar-app-font の :gear: は、字面がほぼ一辺 SIZE の正方形になる
-- (CoreText で実測。20pt で 19.88 x 19.63)。箱の幅も SIZE にする。フォントやサイズを変えたら再測定が必要。
local SIZE = 20

-- グラフの幅 (pt)。SketchyBar のグラフは 1pt が 1 点なので、点の数でもある (helper の間隔 2 秒 x 点数が履歴の長さ)
local GRAPH_WIDTH = 120
local GRAPH_HEIGHT = 18
local ROW_HEIGHT = 26
local TITLE_WIDTH = 52
local VALUE_WIDTH = 96
local ROW_PADDING = 8

-- ディスクの円グラフ (ドーナツ)。表示は DONUT_SIZE (pt)、画像は表示と同じ実ピクセル数 (窓の解像度 2.0 倍) で描く。
-- SketchyBar の窓は補間なし (window.c の kCGInterpolationNone) で画像を描くので、縮小すると円周の縁が間引かれて
-- ギザギザになる。等倍で貼れば、ImageMagick のアンチエイリアスがそのまま見える。
-- ファイルから読んだ画像の表示サイズは 実ピクセル * scale (pt)。高さ 32pt にそろえるのは、リンク画像 (media.artwork)
-- だけ (image.c の image_calculate_bounds)。なので scale = 表示サイズ / 実ピクセル = 0.5 (窓の解像度が 2.0 なので等倍)。
local DONUT_SIZE = 22
local DONUT_PX = DONUT_SIZE * 2
local DONUT_STROKE = DONUT_PX * 0.14
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/system"

-- ネットワークのグラフは、履歴の最大値で 0〜1 にそろえる。通信が少ないときに細かい揺れで振り切れないよう、
-- 最大値の下限を決める (バイト/秒)
local NET_SCALE_FLOOR = 100 * 1000

-- helper が送るイベント。helper が起動するより先に登録しておく (未登録のイベントは --trigger できない)
sbar.add("event", "system_stats")

-- ノッチの右隣 (position "e") に置く。ノッチとの間隔は spacer で作る (ui.add_notch_spacer)。
-- ノッチに最も近い位置に置くので、gear より先に追加する。
ui.add_notch_spacer("e", "system.notch_gap")

-- bracket は円にする。幅を高さ (colors.bracket.height) と同じにし、角の半径は短辺の半分にする。
-- 円の中に歯車が同心で収まるよう、歯車の左右に余白 (ICON_PADDING) を取る。
local BRACKET_WIDTH = colors.bracket.height
local ICON_PADDING = (BRACKET_WIDTH - SIZE) / 2

-- item の width は指定しない。width を指定した item の後は、配置が width の分しか進まず、bracket の padding が
-- 数えられないので、隣の item が padding の分だけ重なる (ui.add_hit_layer の説明)。幅は icon.width で決める。
-- 余白は item の padding ではなく icon の padding にして、item の幅を bracket の幅 (円の直径) と同じにする。
-- ポップアップは item の端にそろう (align = "right" は item の右端) ので、item が bracket より狭いと、
-- ポップアップの右端が円の端からずれる。icon.width は padding を含む箱の全幅 (spotify.lua)。
local gear = ui.add_item("system", "e", {
	icon = {
		string = ":gear:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		width = BRACKET_WIDTH,
		-- 字面は箱の左端 + padding_left から描かれる (spotify.lua)。字面は幅 19.88 なので、円の中心より 0.06 pt 左に寄るだけ。
		align = "left",
		padding_left = ICON_PADDING,
		padding_right = 0,
	},
	label = { drawing = false },
	popup = {
		align = "right",
		height = ROW_HEIGHT,
		background = colors.popup,
	},
})

ui.add_bracket("system.bracket", { gear }, {
	background = { corner_radius = colors.bracket.height / 2 },
}, 0)

-- bracket 全体でマウス操作を受ける (ui.add_hit_layer_over)。item の幅は自動なので、配置が進む幅 (chain) は
-- bracket の幅と同じ
local hit = ui.add_hit_layer_over("system.hit", BRACKET_WIDTH, BRACKET_WIDTH, { position = "e" })

-- 10 進接頭辞 (1 KB = 1000 B)。メモリ・スワップ・ネットワーク・ディスクで、単位をそろえる。
-- 100 以上は整数、それ未満は小数 1 桁で出す。
local UNITS = { "B", "KB", "MB", "GB", "TB" }

local function scale_bytes(bytes)
	local unit = 1
	while bytes >= 1000 and unit < #UNITS do
		bytes = bytes / 1000
		unit = unit + 1
	end
	return bytes, UNITS[unit]
end

local function format_bytes(bytes, per_second)
	local value, unit = scale_bytes(bytes)
	local suffix = per_second and "/s" or ""
	if unit == "B" or value >= 100 then
		return string.format("%.0f %s%s", value, unit, suffix)
	end
	return string.format("%.1f %s%s", value, unit, suffix)
end

-- df -H と同じ桁 (10 未満は小数 1 桁、それ以上は整数。四捨五入)。ディスクの容量用
local function format_disk(bytes)
	local value, unit = scale_bytes(bytes)
	return string.format(value < 10 and "%.1f %s" or "%.0f %s", value, unit)
end

-- 行の定義。title は左の見出し、
--   point(env): グラフに積む値 (そのまま履歴に入る。0〜1 にする割り算は scale で行う)
--   scale(values): 履歴全体を割る値 (固定なら 1)
--   text(env): 右の数字
--   color(env): グラフの色 (省略すると既定)
local function fixed()
	return 1
end

local function history_max(values)
	local max = NET_SCALE_FLOOR
	for _, v in ipairs(values) do
		if v > max then
			max = v
		end
	end
	return max
end

local ROWS = {
	{
		name = "cpu",
		title = "CPU",
		point = function(env)
			return tonumber(env.CPU) / 100
		end,
		scale = fixed,
		text = function(env)
			return string.format("%.0f%%", tonumber(env.CPU))
		end,
	},
	{
		-- CPU のうち、カーネルの処理 (sys) の分。合計と同じ全 CPU 時間に対する割合なので、CPU の行以下になる
		name = "cpu_sys",
		title = "Sys",
		point = function(env)
			return tonumber(env.CPU_SYS) / 100
		end,
		scale = fixed,
		text = function(env)
			return string.format("%.0f%%", tonumber(env.CPU_SYS))
		end,
	},
	{
		name = "ram",
		title = "RAM",
		point = function(env)
			return tonumber(env.RAM) / 100
		end,
		scale = fixed,
		text = function(env)
			return string.format("%.0f%%  %s", tonumber(env.RAM), format_bytes(tonumber(env.RAM_USED)))
		end,
	},
	{
		name = "swap",
		title = "Swap",
		point = function(env)
			local total = tonumber(env.SWAP_TOTAL)
			return total > 0 and tonumber(env.SWAP_USED) / total or 0
		end,
		scale = fixed,
		text = function(env)
			return format_bytes(tonumber(env.SWAP_USED))
		end,
		-- スワップを使い始めたら (メモリが足りていない合図) 色を変える。使っていなければ薄いままにする
		color = function(env)
			return tonumber(env.SWAP_USED) > 0 and colors.swap.alert or colors.swap.default
		end,
	},
	{
		name = "rx",
		title = "\u{2193} Net", -- 下向きの矢印: 受信
		point = function(env)
			return tonumber(env.NET_RX)
		end,
		scale = history_max,
		text = function(env)
			return format_bytes(tonumber(env.NET_RX), true)
		end,
	},
	{
		name = "tx",
		title = "\u{2191} Net", -- 上向きの矢印: 送信
		point = function(env)
			return tonumber(env.NET_TX)
		end,
		scale = history_max,
		text = function(env)
			return format_bytes(tonumber(env.NET_TX), true)
		end,
	},
}

local GRAPH_COLOR = 0xccffffff
local GRAPH_FILL_COLOR = 0x33ffffff

for _, row in ipairs(ROWS) do
	row.values = {}
	row.item = sbar.add("graph", "system." .. row.name, GRAPH_WIDTH, {
		position = "popup.system",
		padding_left = ROW_PADDING,
		padding_right = ROW_PADDING,
		icon = {
			string = row.title,
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
			width = VALUE_WIDTH,
			align = "right",
			padding_left = 8,
			padding_right = 0,
		},
		-- 背景に高さを指定すると、グラフはその中に描かれる
		background = { drawing = true, color = 0x00000000, height = GRAPH_HEIGHT },
		graph = { color = GRAPH_COLOR, fill_color = GRAPH_FILL_COLOR, line_width = 1.0 },
	})
end

local last_env
local last_percent -- 空き (%)。円グラフの画像を選ぶ
local popup_open = false

-- ディスクの行: 見出し | 円グラフ (空きの割合) | 空き / 総容量。
-- 円グラフの画像は、空きの割合 (整数 %) ごとに 1 枚、magick で描いて cache に置く。
-- 画像の位置は背景の左端からの距離 (image.padding_left) で決まるので、真ん中の列 (グラフの幅) の中央に置く。
local disk = sbar.add("item", "system.disk", {
	position = "popup.system",
	padding_left = ROW_PADDING,
	padding_right = ROW_PADDING,
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
local function render()
	if last_env == nil then
		return
	end
	local shown = GRAPH_WIDTH - 1
	for _, row in ipairs(ROWS) do
		local values = row.values
		local scale = row.scale(values)
		local count = #values
		local points = {}
		for i = 1, shown do
			local index = count - shown + i
			points[i] = index >= 1 and math.min(values[index] / scale, 1) or 0
		end
		points[GRAPH_WIDTH] = points[1]
		local props = { label = { string = row.text(last_env) } }
		if row.color then
			local color = row.color(last_env)
			props.graph = { color = color, fill_color = (color & 0x00ffffff) | 0x33000000 }
		end
		row.item:set(props)
		row.item:push(points)
	end

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
	popup_open = true
	render()
	gear:set({ popup = { drawing = true } })
end)

-- バーの外へ出たときは mouse.exited.global でも閉じる
hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
	popup_open = false
	gear:set({ popup = { drawing = false } })
end)
