local colors = require("colors")
local ui = require("ui")

-- アクティビティモニターのアイコンの item。ホバーで、次の 1 行のポップアップを開く。
--   (CPU アイコン) x%  (RAM アイコン) x%  (Disk アイコン) 使用量/総容量
-- データは helper/system.c (sketchybar-system-helper) が一定間隔で測り、system_stats イベントで渡す。
-- 測定は helper がカーネルの API を直接呼ぶだけなので軽い。ポップアップが閉じている間は、描画の指示 (set) は出さない。
-- 数字は bottom (btm。pkgs/btm-window が表示する) と同じ値・同じ書式にしてある (値の測り方は helper/system.c)。

-- アイコンのサイズ (pt)。sketchybar-app-font の :activity_monitor: は、字面がほぼ一辺 SIZE の正方形になる
-- (CoreText の CTLineGetImageBounds で実測。幅は SIZE x 0.998、高さは SIZE x 0.962。20pt で 19.96 x 19.24、16pt で 15.97 x 15.39)。
-- pill (PILL_SIZE = 24) の縁とアイコンの隙間が約 4 pt になる 16。フォントやサイズを変えたら再測定が必要。
local SIZE = 16

-- ポップアップの高さ (pt)。バー (ui.bar_height) の中に収める。
local POPUP_HEIGHT = 32
-- ポップアップの余白 (pt)。上下・左右・item 同士の見た目の余白をこの値にそろえる (ui.bracket_padding と同じ 8)。
-- 縦は 中身の字面の高さ (GLYPH_HEIGHT。tallest は CPU・Disk のアイコンで実測 13.5〜14.5 に y_offset 1 を足して 15)
-- を POPUP_HEIGHT の縦中央に置くので、(32 - 15) / 2 = 8.5 になる (整数に丸めると 8 と 9)。
-- 横は item の padding で作る。label は固定幅で、字面の右に約 1 pt の余りがある (実測。"07%" は 24 の箱に字面 23.0) ので、
-- item 同士の間と右端は、その分を引く。
local POPUP_MARGIN = 8
local LABEL_SLACK = 1
-- アイコン (歯車の円) とポップアップの見た目の間隔 (pt)。spacer は 幅 + 1 pt 描かれる (ui.add_spacer) ので、幅は 1 引く
local POPUP_GAP = 4

-- helper が送るイベント。helper が起動するより先に登録しておく (未登録のイベントは --trigger できない)
sbar.add("event", "system_stats")

-- ノッチの左隣 (position "q") に置く。ノッチとの間隔は spacer で作る (ui.add_notch_spacer)。
-- ノッチに最も近い位置に置くので、gear より先に追加する。
ui.add_notch_spacer("q", "system.notch_gap")

-- bracket は円にする。幅を高さ (colors.bracket.height) と同じにし、角の半径は短辺の半分にする。
-- 円の中にアイコンが同心で収まるよう、アイコンの左右に余白 (ICON_PADDING) を取る。
local BRACKET_WIDTH = colors.bracket.height
-- pill (btm の窓の状態を示す円の背景。set_btm_state の付近を参照) は、bracket の円と同心にして、
-- 縁との隙間を上下左右とも PILL_MARGIN にする (aerospace の pill、spotify の画像と同じ 5 pt)。
local PILL_MARGIN = 5
local PILL_SIZE = BRACKET_WIDTH - 2 * PILL_MARGIN
local ICON_PADDING = (PILL_SIZE - SIZE) / 2

-- item の width は指定しない。width を指定した item の後は、配置が width の分しか進まず、bracket の padding が
-- 数えられないので、隣の item が padding の分だけ重なる (ui.add_hit_layer の説明)。幅は icon.width で決める。
-- item の背景 (pill) は icon.width の箱と同じ大きさ (PILL_SIZE) になり、bracket の範囲との隙間は item の padding
-- (PILL_MARGIN。ui.add_bracket の padding で設定する) で作る。item の幅 + padding は bracket の幅 (円の直径) と同じ。
-- icon.width は padding を含む箱の全幅 (spotify.lua)。
local gear = ui.add_item("system", "q", {
	icon = {
		string = ":activity_monitor:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		width = PILL_SIZE,
		-- 字面は箱の左端 + padding_left から描かれる (spotify.lua)。字面は幅 19.96 なので、円の中心より 0.02 pt 左に寄るだけ。
		align = "left",
		padding_left = ICON_PADDING,
		padding_right = 0,
	},
	label = { drawing = false },
	-- pill。普段は描かない (set_btm_state で色を変える)
	background = {
		drawing = false,
		height = PILL_SIZE,
		corner_radius = PILL_SIZE / 2,
	},
})

local bracket = ui.add_bracket("system.bracket", { gear }, {
	background = { corner_radius = colors.bracket.height / 2 },
}, PILL_MARGIN)

-- bracket 全体でマウス操作を受ける (ui.add_hit_layer_over)。item の幅は自動なので、配置が進む幅 (chain) は
-- bracket の幅と同じ
local hit = ui.add_hit_layer_over("system.hit", BRACKET_WIDTH, BRACKET_WIDTH, { position = "q" })

-- 数字の書式は btm (src/utils/data_units.rs、conversion.rs) と同じ。
-- 10 進接頭辞 (1 KB = 1000 B) で、値は 1 回の割り算で出す (btm の get_decimal_bytes、get_unit_prefix)
local DECIMAL_BYTES = { { 1e12, "TB" }, { 1e9, "GB" }, { 1e6, "MB" }, { 1e3, "KB" } }

local function split_unit(value, units, base_unit)
	for _, entry in ipairs(units) do
		if value >= entry[1] then
			return value / entry[1], entry[2]
		end
	end
	return value, base_unit
end

-- ディスクの使用量・総容量 (byte)。btm の disk widget と同じ「325GB」の形
local function format_disk(bytes)
	local value, unit = split_unit(bytes, DECIMAL_BYTES, "B")
	return string.format("%.0f%s", value, unit)
end

-- ポップアップは、バーの中の、アイコンの左隣に、左へ伸ばして出す (バーの下には出さない)。アイコンや隣の item に被らないよう、
-- ポップアップの持ち主は、アイコンの左に置いた空の item (anchor) にする。align = "right" は持ち主の右端にそろう。
-- ポップアップは既定でバーの下端から下に出る。y_offset を負にして上へ戻し、バーの縦の中央に置く
-- (上端が (バーの高さ - POPUP_HEIGHT) / 2 になる)。ポップアップの枠線 (border_width) の分だけ中身が下にずれる
-- (実機で、枠線 1 のとき中身の上端が 5 pt、枠線 0 のとき 4 pt) ので、その分も上げる。
ui.add_spacer("q", POPUP_GAP - 1)
local anchor = ui.add_item("system.anchor", "q", {
	width = 1,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = { drawing = false },
	popup = {
		align = "right",
		horizontal = true,
		height = POPUP_HEIGHT,
		y_offset = -(ui.bar_height + POPUP_HEIGHT) / 2 - colors.bracket.border_width,
		-- 背景は他の bracket (colors.bracket) と同じ色・枠線・角の丸み。高さは popup.height で決まる
		background = {
			color = colors.bracket.color,
			border_color = colors.bracket.border_color,
			border_width = colors.bracket.border_width,
			corner_radius = colors.bracket.corner_radius,
		},
	},
})

-- ポップアップは CPU、RAM、Disk の 3 つの item を横に並べる。数字の見せ方は battery.lua と同じ:
-- アイコン (18pt の Nerd Font のグリフ) + 数字 (13pt)。桁が変わっても隣の item がずれないよう、label の幅を固定する。
-- 実測値 (Hack Nerd Font Bold 13pt): label の固定幅は内側の padding_left(3) を含む。
-- "45%" / "100%" の順に 27 / 34 px。"245GB/500GB" (最も長い形) は 89 px。
-- 1 桁は "05%" のように 0 埋めして 2 桁として扱う。フォントやサイズ、label の padding を変えたら再測定が必要。
local PERCENT_WIDTH_BY_DIGITS = { [2] = 27, [3] = 34 }
local DISK_WIDTH = 89

-- アイコンの箱の幅 (padding を含む全幅)。字面は advance (10.8) より広く、箱の外にはみ出すと数字に重なる
-- (wifi.lua、bluetooth.lua と同じ)。字面は箱の左端から描かれるので、字面の幅 (実測。CTLineGetImageBounds、
-- Hack Nerd Font Bold 18pt。CPU 13.5、RAM 18.7、Disk 14.5) に、字面の右端と数字の間の余白 3.9 を足して切り上げた値にする。
-- 3.9 は battery.lua の見た目の余白 (advance 10.8 - 字面の右端 9.9 + icon の padding_right 3) と同じ。
-- フォントやサイズを変えたら再測定が必要。
local CPU_ICON_WIDTH = 18
local RAM_ICON_WIDTH = 23
local DISK_ICON_WIDTH = 19

-- padding_left / padding_right は item の外側の余白。左端の item だけ左に POPUP_MARGIN、右端の item だけ右に
-- POPUP_MARGIN - LABEL_SLACK、間も POPUP_MARGIN - LABEL_SLACK にして、見た目をそろえる。
local function add_stat(name, icon, icon_width, width, padding_left, padding_right)
	return sbar.add("item", "system." .. name, {
		position = "popup.system.anchor",
		padding_left = padding_left,
		padding_right = padding_right,
		icon = {
			string = icon,
			font = { size = 18.0 },
			y_offset = 1,
			width = icon_width,
			align = "left",
			padding_left = 0,
			padding_right = 0,
		},
		label = { string = "", width = width, padding_left = 3, padding_right = 0 },
	})
end

local EDGE_PADDING = POPUP_MARGIN - LABEL_SLACK
local cpu_item = add_stat("cpu", "\u{f035b}", CPU_ICON_WIDTH, PERCENT_WIDTH_BY_DIGITS[2], POPUP_MARGIN, EDGE_PADDING)
local ram_item = add_stat("ram", "\u{efc5}", RAM_ICON_WIDTH, PERCENT_WIDTH_BY_DIGITS[2], 0, EDGE_PADDING)
local disk_item = add_stat("disk", "\u{f0c7}", DISK_ICON_WIDTH, DISK_WIDTH, 0, EDGE_PADDING)

-- 0 埋めした整数の % と、その桁数に応じた label の幅
local function percent_label(value)
	local text = string.format("%02.0f%%", value)
	return { string = text, width = PERCENT_WIDTH_BY_DIGITS[#text - 1] }
end

-- メモリ圧力 (カーネルの kern.memorystatus_vm_pressure_level。helper/system.c の MEM_PRESSURE) と、その表示色。
-- 1: normal、2: warn、4: critical。値が取れないとき (nil) は normal の色にする。
local PRESSURE_COLORS = {
	[1] = colors.status.normal,
	[2] = colors.status.warn,
	[4] = colors.status.critical,
}

-- 使用率 (%) の閾値。瞬間値で判定する (平滑化はしない)。以上で warn、critical の色にする。
--   CPU : warn は Apple のサポート記事 (継続的に 70% 超は高負荷) による。critical の 90% は目安。
--   Disk: 空き 20% 以下で warn、10% 以下で critical (macOS の「空きを 10〜20% 保つ」目安と、Zabbix の既定 90%)。
local CPU_THRESHOLDS = { warn = 70, critical = 90 }
local DISK_THRESHOLDS = { warn = 80, critical = 90 }

local function threshold_color(value, thresholds)
	if value >= thresholds.critical then
		return colors.status.critical
	elseif value >= thresholds.warn then
		return colors.status.warn
	end
	return colors.status.normal
end

-- アイコンと label の色をそろえて、item の設定にする
local function colored(label, color)
	label.color = color
	return { icon = { color = color }, label = label }
end

local last_env
local popup_open = false

-- 値がそろわないとき (起動直後など) は、その回の描画を飛ばす
local function render()
	if last_env == nil then
		return
	end
	local env = last_env

	local cpu = tonumber(env.CPU)
	local ram_used, ram_total = tonumber(env.RAM_USED), tonumber(env.RAM_TOTAL)
	local disk_total, disk_free = tonumber(env.DISK_TOTAL), tonumber(env.DISK_FREE)
	if not (cpu and ram_used and ram_total and disk_total and disk_free) then
		return
	end

	local ram_percent = ram_total > 0 and ram_used / ram_total * 100 or 0
	local disk_percent = disk_total > 0 and (disk_total - disk_free) / disk_total * 100 or 0
	cpu_item:set(colored(percent_label(cpu), threshold_color(cpu, CPU_THRESHOLDS)))
	ram_item:set(colored(percent_label(ram_percent), PRESSURE_COLORS[tonumber(env.MEM_PRESSURE)] or colors.status.normal))
	disk_item:set(colored(
		{ string = string.format("%s/%s", format_disk(disk_total - disk_free), format_disk(disk_total)) },
		threshold_color(disk_percent, DISK_THRESHOLDS)
	))
end

gear:subscribe("system_stats", function(env)
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
	render()
	anchor:set({ popup = { drawing = true } })
end)

-- 右クリックでピン留めした状態。ピン留め中は、マウスが外れてもポップアップを閉じない。
-- もう一度右クリックすると外す。ピン留め中は bracket の枠線が colors.bracket.pinned_border_color になる (spotify.lua と同じ)。
local pinned = false

-- ピン留めの状態を変え、bracket の枠線の色で示す
local function set_pinned(value)
	pinned = value
	bracket:set({ background = { border_color = value and colors.bracket.pinned_border_color or colors.bracket.border_color } })
end

-- バーの外へ出たときは mouse.exited.global でも閉じる。ピン留め中は閉じない
hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
	if pinned then
		return
	end
	popup_open = false
	anchor:set({ popup = { drawing = false } })
end)

-- btm の窓 (pkgs/btm-window) の開閉。起動中なら SIGUSR1 を送り、窓が最前面なら閉じ、そうでなければ前に出させる。
-- 起動していなければ起動する。窓は AeroSpace の管理外で、今の workspace の上に重なる (workspace は切り替わらない)。
local TOGGLE_BTM_COMMAND = "pkill -USR1 -x btm-window || { nohup btm-window >/dev/null 2>&1 & }"

-- btm の窓の状態を、bracket の中の pill (gear の背景) の色で示す。bracket の背景は変えない。
--   最前面: aerospace の workspace (items/aerospace.lua の highlight) と同じく色を反転する。
--           pill を colors.space.bg_focused に、アイコンを colors.space.fg_focused にする。
--   起動中だが最前面ではない: pill を colors.dim に、アイコンを colors.space.fg_focused にする。
--   起動していない: pill は描かず、アイコンは普段の色。
-- 窓が最前面になる・外れる・閉じるのは、どれも front_app_switched (INFO は前面になったアプリ名) で分かる。
-- 最前面でないときだけ、起動しているかを pgrep で調べる。
local BTM_APP_NAME = "btm-window"

local function set_btm_state(state)
	local pill_color = {
		front = colors.space.bg_focused,
		background = colors.dim,
	}
	local color = pill_color[state]
	gear:set({
		icon = { color = color and colors.space.fg_focused or colors.white },
		background = { drawing = color ~= nil, color = color },
	})
end

-- 古い問い合わせの結果が、新しい状態を上書きしないよう、最後の問い合わせだけ反映する
local btm_query_id = 0

gear:subscribe("front_app_switched", function(env)
	btm_query_id = btm_query_id + 1
	local id = btm_query_id
	if env.INFO == BTM_APP_NAME then
		set_btm_state("front")
		return
	end
	-- 窓が閉じた直後は、プロセスが終わりきる前に pgrep が走らないよう、少し待つ
	sbar.exec("sleep 0.3; pgrep -x " .. BTM_APP_NAME, function(output)
		if id ~= btm_query_id then
			return
		end
		set_btm_state((output or ""):match("%d") and "background" or "none")
	end)
end)

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
