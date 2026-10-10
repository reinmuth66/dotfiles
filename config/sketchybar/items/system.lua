local colors = require("colors")
local ui = require("ui")

-- アクティビティモニターのアイコンの item。ホバーで、次の 1 行のポップアップを開く。
--   CPU のアイコンと x%、RAM のアイコンと x%、Disk のアイコンと 使用量/総容量
-- データは pkgs/sketchybar-helper/system.c の sketchybar-system-helper が一定間隔で測り、system_stats イベントで渡す。
-- 測定は helper がカーネルの API を直接呼ぶだけなので軽い。ポップアップが閉じている間は、描画の指示の set は出さない。
-- 数字は bottom の btm と同じ値、同じ書式にしてある。btm は pkgs/btm-window が表示する。値の測り方は pkgs/sketchybar-helper/system.c。

-- sketchybar-app-font の :activity_monitor: は、字面がほぼ一辺 SIZE の正方形になる。
-- CoreText の CTLineGetImageBounds で実測した。幅は SIZE x 0.998、高さは SIZE x 0.962。20pt で 19.96 x 19.24、16pt で 15.97 x 15.39。
-- SIZE の 16 は、pill の縁とアイコンの隙間が約 4 pt になる値。pill の PILL_SIZE は 24。フォントやサイズを変えたら再測定する。
local SIZE = 16

-- バー ui.bar_height の中に収める。
local POPUP_HEIGHT = 32
-- 上下、左右、item 同士の見た目の余白をこの値にそろえる。ui.bracket_padding と同じ 8。
-- 縦は、中身の字面の高さを POPUP_HEIGHT の縦中央に置くので、(32 - 15) / 2 = 8.5 になる。整数に丸めると 8 と 9。
-- 字面の高さ GLYPH_HEIGHT は、最も高い CPU と Disk のアイコンの実測 13.5〜14.5 に y_offset 1 を足して 15。
-- 横は item の padding で作る。label は固定幅で、字面の右に約 1 pt の余りがある。実測で、"07%" は 24 の箱に字面 23.0。
-- そのため item 同士の間と右端は、その分を引く。
local POPUP_MARGIN = 8
local LABEL_SLACK = 1

-- spacer は 幅 + 1 pt 描かれるので、spacer の幅は 1 引く。ui.add_spacer を参照。
local POPUP_GAP = 4

-- helper が起動するより先に登録しておく。未登録のイベントは --trigger できない。
sbar.add("event", "system_stats")

-- ノッチに最も近い位置に置くので、gear より先に追加する。
ui.add_notch_spacer("q", "system.notch_gap")

-- 円の中にアイコンが同心で収まるよう、アイコンの左右に余白 ICON_PADDING を取る。
-- pill は btm の窓の状態を示す円の背景で、set_btm_state の付近を参照。bracket と同心にして、縁との隙間を上下 PILL_MARGIN にする。
-- 隙間は aerospace の pill や spotify の画像と同じ 5 pt。
-- 左右も同じ隙間にして、bracket の幅を高さと同じにする。円になり、spotify の bracket と同じ。
local PILL_MARGIN = 5
local SIDE_MARGIN = PILL_MARGIN
local PILL_SIZE = colors.bracket.height - 2 * PILL_MARGIN
local BRACKET_WIDTH = PILL_SIZE + 2 * SIDE_MARGIN
local ICON_PADDING = (PILL_SIZE - SIZE) / 2

-- item の width は指定しない。width を指定した item の後は、配置が width の分しか進まず、
-- bracket の padding が数えられないので、隣の item が padding の分だけ重なる。ui.add_hit_region の説明を参照。
-- 幅は icon.width で決める。icon.width は padding を含む箱の全幅で、spotify.lua と同じ。
-- 字面は箱の左端 + padding_left から描かれる。字面は幅 19.96 なので、円の中心より 0.02 pt 左に寄るだけ。
local gear = ui.add_item("system", "q", {
	icon = {
		string = ":activity_monitor:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		width = PILL_SIZE,
		align = "left",
		padding_left = ICON_PADDING,
		padding_right = 0,
	},
	label = { drawing = false },
	background = {
		drawing = false,
		height = PILL_SIZE,
		corner_radius = PILL_SIZE / 2,
	},
})

local bracket = ui.add_bracket("system.bracket", { gear }, {
	background = { corner_radius = colors.bracket.height / 2 },
}, SIDE_MARGIN)

-- item の幅は自動なので、配置が進む幅 chain は bracket の幅と同じ。
local hit = ui.add_hit_region("system.hit", BRACKET_WIDTH, 0, BRACKET_WIDTH, { position = "q" })

-- 数字の書式は btm の src/utils/data_units.rs と conversion.rs と同じ。
-- 10 進接頭辞で 1 KB = 1000 B とし、値は 1 回の割り算で出す。btm の get_decimal_bytes と get_unit_prefix に合わせる。
local DECIMAL_BYTES = { { 1e12, "TB" }, { 1e9, "GB" }, { 1e6, "MB" }, { 1e3, "KB" } }

-- btm の disk widget と同じ 325GB の形。
local function format_disk(bytes)
	for _, entry in ipairs(DECIMAL_BYTES) do
		if bytes >= entry[1] then
			return string.format("%.0f%s", bytes / entry[1], entry[2])
		end
	end
	return string.format("%.0f%s", bytes, "B")
end

-- アイコンや隣の item に被らないよう、ポップアップの持ち主は、アイコンの左に置いた空の item の anchor にする。
-- ui.add_popup_anchor を使う。
ui.add_spacer("q", POPUP_GAP - 1)
local anchor = ui.add_popup_anchor("system.anchor", "q", {
	align = "right",
	height = POPUP_HEIGHT,
	background = {
		color = colors.bracket.color,
		border_color = colors.bracket.border_color,
		border_width = colors.bracket.border_width,
		corner_radius = colors.bracket.corner_radius,
	},
})

-- 数字の見せ方は battery.lua と同じ。桁が変わっても隣の item がずれないよう、label の幅を固定する。
-- 実測は Hack Nerd Font Bold 13pt で、label の固定幅は内側の padding_left の 3 を含む。
-- "45%" が 27px、"100%" が 34px。最も長い形の "245GB/500GB" は 89px。
-- 1 桁は "05%" のように 0 埋めして 2 桁として扱う。フォントやサイズ、label の padding を変えたら再測定する。
local PERCENT_WIDTH_BY_DIGITS = { [2] = 27, [3] = 34 }
local DISK_WIDTH = 89

-- 字面は advance の 10.8 より広く、箱の外にはみ出すと数字に重なる。wifi.lua、bluetooth.lua と同じ。
-- 字面は箱の左端から描かれるので、箱の幅は、字面の幅に、字面の右端と数字の間の余白 3.9 を足して切り上げた値にする。
-- 字面の幅は CTLineGetImageBounds で実測した。Hack Nerd Font Bold 18pt で、CPU 13.5、RAM 18.7、Disk 14.5。
-- 3.9 は battery.lua の見た目の余白と同じで、advance 10.8 - 字面の右端 9.9 + icon の padding_right 3。
-- フォントやサイズを変えたら再測定する。
local CPU_ICON_WIDTH = 18
local RAM_ICON_WIDTH = 23
local DISK_ICON_WIDTH = 19

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

local function percent_label(value)
	local text = string.format("%02.0f%%", value)
	return { string = text, width = PERCENT_WIDTH_BY_DIGITS[#text - 1] }
end

-- メモリ圧力は、カーネルの kern.memorystatus_vm_pressure_level で、pkgs/sketchybar-helper/system.c の MEM_PRESSURE。その表示色。
-- 1 が normal、2 が warn、4 が critical。値が取れないとき、つまり nil は normal の色にする。
local PRESSURE_COLORS = {
	[1] = colors.status.normal,
	[2] = colors.status.warn,
	[4] = colors.status.critical,
}

-- 瞬間値で判定する。平滑化はしない。
--   CPU : warn は Apple のサポート記事による。継続的に 70% 超は高負荷。critical の 90% は目安。
--   Disk: 空き 20% 以下で warn、10% 以下で critical。macOS の "空きを 10〜20% 保つ" という目安と、Zabbix の既定 90% による。
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

local function colored(label, color)
	label.color = color
	return { icon = { color = color }, label = label }
end

local last_env
local popup_open = false

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

-- ピン留め中は開いたままなので、開き直さない。
hit:subscribe("mouse.entered", function()
	if popup_open then
		return
	end
	popup_open = true
	render()
	anchor:set({ popup = { drawing = true } })
end)

local pin = ui.pin(function(active)
	bracket:set({ background = { border_color = active and colors.pinned_border or colors.bracket.border_color } })
end)

-- バーの外へ出たときは mouse.exited.global でも閉じる。
hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
	if pin.active then
		return
	end
	popup_open = false
	anchor:set({ popup = { drawing = false } })
end)

-- btm の窓 pkgs/btm-window は AeroSpace の管理外で、今の workspace の上に重なる。workspace は切り替わらない。
local BTM_APP_NAME = "btm-window"
local TOGGLE_BTM_COMMAND = string.format("pkill -USR1 -x %s || { nohup %s >/dev/null 2>&1 & }", BTM_APP_NAME, BTM_APP_NAME)

-- 最前面のときは、aerospace の workspace と同じく色を反転する。items/aerospace.lua の highlight を参照。
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

-- 古い問い合わせの結果が、新しい状態を上書きしないよう、最後の問い合わせだけ反映する。
local btm_query = ui.latest()

-- 窓が最前面になる、外れる、閉じるのは、どれも front_app_switched で分かる。INFO は前面になったアプリ名。
-- 窓が閉じた直後は、プロセスが終わりきる前に pgrep が走らないよう、少し待つ。
gear:subscribe("front_app_switched", function(env)
	local is_latest = btm_query.begin()
	if env.INFO == BTM_APP_NAME then
		set_btm_state("front")
		return
	end
	sbar.exec("sleep 0.3; pgrep -x " .. BTM_APP_NAME, function(output)
		if not is_latest() then
			return
		end
		set_btm_state((output or ""):match("%d") and "background" or "none")
	end)
end)

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		sbar.exec(TOGGLE_BTM_COMMAND)
	elseif env.BUTTON == "right" then
		pin.toggle(popup_open)
	end
end)
