-- Spotify のアルバム画像を表示し、再生状態を明るさと回転で示す。
--   再生中  : 覆いを外して明るくし、画像をゆっくり回す
--   一時停止: 画像を暗くし、回転はその角度で止める
--   未起動・停止中: 画像の代わりに Spotify のアイコンを出す (アイテム自体は常に表示)
-- 操作: 左クリックで再生/一時停止、左ダブルクリックで Spotify のウィンドウを表示、右クリックでポップアップのピン留め、
-- 上スクロールで前の曲、下スクロールで次の曲。
-- マウスを乗せると、曲名・アーティストと、再生中の音に合わせて動く棒グラフをポップアップで表示する (表示のみで、ボタンは持たない)。
-- 状態は Spotify の分散通知 (media_change は macOS 26 で発火しない) から受け取る。
-- 再生位置は、通知の Playback Position を基準に、ローカルの時計で進める (毎秒の osascript の取得は行わない)。
-- 回転は background.image.rotation を使う (SketchyBar#815 のパッチが前提、pkgs/sketchybar/)。
-- 棒グラフは cava の SDL の窓 (modules/cavaviz.nix、pkgs/cavaviz/) が、ポップアップの背景と枠と一緒に描く。
-- 窓はポップアップの下 (window level 100。ポップアップは 101) に敷き、ポップアップ自身の背景は、窓が出ている間
-- 透明にして、文字が棒グラフの上に描かれるようにする。
-- マウス操作は、bracket 全体を覆う透明な item (hit) が受ける。画像の item は再描画が多く、
-- マウスを購読させると mouse.exited が届かずポップアップが閉じなくなることがあるため (ui.add_hit_region)。

local ui = require("ui")
local colors = require("colors")
local palette = require("palette")
local paths = require("paths")
local artwork = require("items.spotify.artwork")
local fs = require("items.spotify.fs")
local script = require("items.spotify.script")
local truncate = require("items.spotify.text").truncate

local hex = palette.hex

local SIZE = 24 -- アイコンのフォントサイズも同じ値にする (このフォントでは字面が一辺 SIZE の正方形になる)
local HOME = paths.home

-- 見た目は実機で確認して調整する。
-- y_offset は、ポップアップの縦の中央からの距離 (上が正)。
-- 右隣の network bracket との隙間を、他の bracket 間と同じ 7 pt にするための幅。network の左端は battery と zmk_battery の
-- ラベル幅 (どちらも常に 3 桁用の幅で固定) だけで決まり 1243 pt になるので、ポップアップの右端 (開始 + 235) との差が 7 pt になる。
-- items/system.lua のポップアップの幅 (実測で 233 pt。CPU 60 + RAM 57 + Disk 115 + 右の枠 1) とは 2 pt 違う。
-- 幅 (VIZ_WIDTH) を決めた値にして、文字の領域の幅 (TEXT_WIDTH = 222) をそこから求める
-- (POPUP_PADDING を変えても、窓の幅は 235 のまま保たれる)。
local POPUP_PADDING = 6
local POPUP_BORDER = colors.popup.border_width
local VIZ_WIDTH = 235
local TEXT_WIDTH = VIZ_WIDTH - 2 * POPUP_PADDING - POPUP_BORDER
local POPUP_HEIGHT = colors.bracket.height - 2 * POPUP_BORDER -- 偶数にする
local POPUP_GAP = 4

-- ポップアップの背景は、中身 (POPUP_HEIGHT の高さの帯) の左端から始まり、右と上下に枠の太さの分だけ広がる
-- (左は広がらない。SketchyBar の popup.c の popup_calculate_bounds)。
-- 棒の領域 (窓の左上から x = 6, y = 4, 幅 = 235 - 6 - POPUP_BORDER - 6 = 222, 高さ = POPUP_BG_HEIGHT - 2 * 4 = 26)、
-- 角の半径 (colors.popup)、枠の太さは、pkgs/cavaviz/popup.frag の定数と同じ値にする。
-- 設定 (棒の数、感度など) は modules/cavaviz.nix。
local POPUP_BG_HEIGHT = POPUP_HEIGHT + 2 * POPUP_BORDER
local VIZ_LEFT = POPUP_PADDING
local VIZ_APP = HOME .. "/Applications/Home Manager Apps/CavaViz.app"
local VIZ_CONFIG_HOME = HOME .. "/.config/cavaviz"
local VIZ_TEMPLATE = VIZ_CONFIG_HOME .. "/config.template"
local VIZ_RUNTIME_DIR = paths.cache .. "/cavaviz"
local VIZ_CONFIG = VIZ_RUNTIME_DIR .. "/config"
local VIZ_SLOT_RETRIES = 20
local VIZ_SLOT_INTERVAL = 0.05 -- 秒
local VIZ_KILL_AGAIN = 0.6 -- 秒。open は約 0.3 秒かかる
local VIZ_CONTROL = VIZ_RUNTIME_DIR .. "/control"
-- 制御ファイルは最後の指示しか持たないので、別のファイルにしてある (sdl-progress.patch)。
local VIZ_PROGRESS = VIZ_RUNTIME_DIR .. "/progress"
-- "off" の間は cava の tap がなく、収録のインジケーターも消える (tap-gate.patch)。
local VIZ_AUDIO = VIZ_RUNTIME_DIR .. "/audio"
-- パターンの先頭を [C] にして、この pkill を実行するシェル自身 (コマンドラインにパターンを含む) に一致させない
local VIZ_STOP = "pkill -f '[C]avaViz.app/Contents/MacOS/cava'"
-- cava が、描画ループの最初に sketchybar --trigger で送る
-- (ID=起動の番号つき。CAVAVIZ_READY_BIN / CAVAVIZ_READY_EVENT / CAVAVIZ_READY_ID で渡す)。
local VIZ_READY_EVENT = "cavaviz_ready"
local VIZ_WAIT_TIMEOUT = 1.5 -- 秒
local VIZ_HIDDEN_POS = -3000
-- 窓を出す指示から、ポップアップ自身の背景を透明にするまでの秒数は、窓が実際に出る
-- (指示のファイルへの書き込みと、窓の不透明度の反映) より後にする。それまでは、窓は不透明なポップアップの背景に隠れている
-- (配色は不透明なので、窓と背景が重なっていても見た目は変わらない)。
local VIZ_HANDOVER_DELAY = 0.1

local function with_alpha(color, alpha)
	return alpha * 0x1000000 + color % 0x1000000
end

-- bracket は円にする。角の半径は短辺の半分以上にすると、背景の描画側で短辺の半分に丸められる。
local BRACKET_PADDING = (colors.bracket.height - SIZE) / 2

-- 再生位置の表示 (秒) も同じ周で 1 つ進める (秒の切り替わりと回転が同じタイミングで変わる)。
-- 負の値は rotation を減らす向き (見た目の向きはこの符号で決まる)。
local ROTATION_PERIOD = 60
local TICK = 1 -- 表示の秒を 1 周で 1 つ進めるので、1 秒にする
local ROTATION_STEP = -360 * TICK / ROTATION_PERIOD

local PAUSED_COLOR = colors.spotify.overlay_paused
local PLAYING_COLOR = colors.transparent
local FADE_FRAMES = 12 -- 60 フレームで 1 秒

-- ノッチに最も近い位置に置くので、spotify より先に追加する。
ui.add_notch_spacer("e", "spotify.notch_gap")

local spotify = ui.add_item("spotify", "e", {
	width = SIZE,
	update_freq = 5, -- 画像を出している間の、Spotify 終了の確認 (routine) に使う
	-- icon.width は padding を含む箱の全幅 (SketchyBar v2.24.0 の text.c で確認)。
	-- 字面は箱の左端 + padding_left から描かれ、箱の外にはみ出した部分は描画されず見切れる。
	-- 中央揃え (align = center) だと、字面の幅 (17pt に切り上げ) との差を整数で割るため、
	-- 左右 padding が 0 では 1pt 左に寄る。左揃えにして padding_left で位置を直接指定し、
	-- 箱は SIZE のままにして、字面が箱の中の中央に収まるようにする。
	icon = {
		string = ":spotify:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		color = colors.dim, -- 起動していないことが分かるよう、少し薄くする
		width = SIZE,
		align = "left",
		padding_left = 0, -- 字面は箱と同じ大きさなので、余白はいらない
		padding_right = 0,
	},
	-- 画像を暗くするための覆い。画像の背景より後に描かれるラベルの背景を、画像と同じ大きさで重ねる
	label = {
		drawing = false,
		string = "",
		width = SIZE,
		padding_left = 0,
		padding_right = 0,
		background = {
			drawing = true,
			color = PAUSED_COLOR,
			height = SIZE,
			corner_radius = SIZE / 2,
		},
	},
	background = {
		drawing = true,
		color = colors.transparent,
		image = {
			drawing = false,
			scale = SIZE / artwork.ART_PX, -- 画像の一辺 (px) は、キャッシュ側が決める (表示サイズとは独立)
			corner_radius = SIZE / 2,
		},
	},
})

local bracket = ui.add_bracket("spotify.bracket", { spotify }, {
	background = { color = colors.spotify.bracket_bg, corner_radius = colors.bracket.height / 2 },
}, BRACKET_PADDING)

local hit = ui.add_hit_region("spotify.hit", SIZE, 0, SIZE + 2 * BRACKET_PADDING, { position = "e" })

-- bracket や画像に被らないよう、ポップアップの持ち主は、bracket の右に置いた空の item (anchor) にする
-- (items/system.lua のポップアップと同じ作り。ui.add_popup_anchor)。
-- hit の padding_right (-2 * BRACKET_PADDING) の分、hit の次の item は bracket の右端より内側 (画像の位置) から始まる
-- (左右反転した q 側での実測。これがないと、ポップアップが bracket に 6 pt 入り込む)。その分も spacer に足して、bracket の右端から
-- POPUP_GAP だけ離す。
ui.add_spacer("e", POPUP_GAP - 1 + 2 * BRACKET_PADDING)
local anchor = ui.add_popup_anchor("spotify.anchor", "e", {
	align = "left",
	height = POPUP_HEIGHT,
	-- 起動直後の初期値。画像が読めたら apply_palette が配色ごとに上書きする
	background = {
		color = palette.default.bg,
		border_color = palette.default.border,
		border_width = colors.popup.border_width,
		corner_radius = colors.popup.corner_radius,
	},
})

-- 文字の領域は、曲名・アーティストの item を width = 0 にして同じ x から y_offset で縦にずらして重ね、
-- その右に TEXT_WIDTH の空き (spotify.viz) を置いて幅を確保する。
local popup_font = ui.popup_font

local function add_popup_spacer(name, width)
	return sbar.add("item", name, {
		position = "popup.spotify.anchor",
		width = width,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
	})
end

add_popup_spacer("spotify.pad.left", POPUP_PADDING)

local ROWS = {
	{ key = "title", size = 13.0, y_offset = 8 },
	{ key = "artist", size = 8.0, y_offset = -3 },
}

-- 影の色は、ポップアップの背景色 (palette の bg) に、この不透明度を付けたもの。
-- 文字は背景と反対の明るさ (dark の背景なら明るい文字、light の背景なら暗い文字) なので、影は文字の縁を
-- 背景に近い色でなじませ、棒グラフとの境目を作る。黒に固定すると、light の背景で暗い文字が太く汚れて見える。
local TEXT_SHADOW_ALPHA = 0xb0
local TEXT_SHADOW_COLOR = with_alpha(palette.default.bg, TEXT_SHADOW_ALPHA) -- 初期値 (apply_palette が配色ごとに更新する)

local rows = {}
for _, row in ipairs(ROWS) do
	rows[row.key] = {
		size = row.size,
		item = sbar.add("item", "spotify." .. row.key, {
			position = "popup.spotify.anchor",
			drawing = false,
			width = 0,
			y_offset = row.y_offset,
			padding_left = 0,
			padding_right = 0,
			icon = { drawing = false },
			label = {
				font = popup_font(row.size),
				padding_left = 0,
				padding_right = 0,
				-- 棒グラフの上に文字が載るので、影を付けて輪郭を出す
				shadow = { drawing = true, color = TEXT_SHADOW_COLOR, distance = 1 },
			},
		}),
	}
end

-- ビジュアライザの窓の位置の基準で、sketchybar --query の bounding_rects で取る。
-- 矩形は、popup の高さいっぱいの帯になる (y_offset は含まれない)。
-- 何も描かない item だと位置が取れない可能性があるので、透明な背景を持たせる。
sbar.add("item", "spotify.viz", {
	position = "popup.spotify.anchor",
	width = TEXT_WIDTH,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = { drawing = false },
	background = { drawing = true, color = colors.transparent },
})

add_popup_spacer("spotify.pad.right", POPUP_PADDING)

local function set_popup_info(meta)
	for key, row in pairs(rows) do
		local text = meta[key]
		if type(text) ~= "string" then
			text = ""
		end
		row.item:set({ drawing = text ~= "", label = { string = truncate(text, row.size, TEXT_WIDTH) } })
	end
end

-- 通知は一時停止・再開・曲の切り替えで来るが、シークでは来ない (実機で確認)。
-- そのため、ポップアップを閉じている間のシークは、開いた瞬間の取得で直る。
-- 開いている間のシークは、次の通知か開き直しまで直らない。毎秒の osascript の取得は行わない。
-- 秒の進みは、位置の見積もりとは切り離す。見積もりが表示に追いつくのを待つ作りだと、補正が続くとき
-- (素早いホバーの繰り返しなど) に、秒も回転も止まってしまう。
local shown = nil -- nil なら、まだ位置が分かっていない
local duration = 0 -- 秒
local popup_open = false
-- 画像は取得できてから出す (取得前に切り替えると、画像のない覆いだけが見えてしまう)。
-- 画像を出している間 (再生中と一時停止中) が、曲情報のある間で、ポップアップを出せる。
local showing_art = false
-- ポップアップを開くたびに begin する (open_popup)。古い取得の結果で、別の開き直しのポップアップを開かないための印
local open_session = ui.latest()
local SNAP_BACK = 1.5 -- 秒

-- 位置が分からないとき (shown が nil、曲の長さが 0) は 0 を書く (前の曲の位置を残さない)。
local function write_progress()
	local progress = 0
	if shown ~= nil and duration > 0 then
		progress = math.min(1, shown / duration)
	end
	fs.write(VIZ_PROGRESS, string.format("%.4f", progress))
end

-- position は秒 (小数)。new_duration が nil なら前の値のまま。
-- 再生中の小さな補正では、表示を戻さない (棒の色の境界が戻らないようにする)。
local function rebase(position, new_duration, playing, force)
	duration = new_duration or duration
	if shown == nil or force or not playing or not popup_open or position >= shown or position < shown - SNAP_BACK then
		shown = math.floor(position)
	end
	if popup_open then
		write_progress()
	end
end

local function step_time()
	if shown == nil or shown >= math.floor(duration) then
		return
	end
	shown = shown + 1
	if popup_open then
		write_progress()
	end
end

-- done は、結果の反映 (または失敗) のあとに呼ぶ (nil でもよい)。
local function refresh_position(done)
	sbar.exec(script.POSITION_COMMAND, function(out)
		local state, timing = script.parse_position(out)
		if timing then
			rebase(timing.position, timing.duration, state == "Playing", false)
		end
		if done then
			done()
		end
	end)
end

-- cava は tap がある間だけ音声を収録する。一時停止中は VIZ_AUDIO を "off" にして tap を解放し (棒は 0 に落ち、最小の高さの棒の色で
-- 再生位置だけを見せる)、再生が始まったら "on" にして作り直す (write_audio)。
-- 音声の取得 (Core Audio tap) の許可は CavaViz.app に付いているので、sketchybar の子プロセスにせず、
-- open で起動する (pkgs/cavaviz/default.nix を参照)。
-- 窓が出ていないとき (許可がなくて cava が起動できないときなど) に背景を透明にすると、ポップアップの背景がなくなってしまうので、
-- 準備完了 (viz.ready) と窓を出す指示 (viz.shown) がそろってから、viz_take_background で透明にする。
local viz = {
	running = false,
	id = 0,
	cache = nil,
	ready = false,
	on_ready = nil,
	fg = palette.default.viz,
	played = palette.default.played,
	bg = hex(palette.default.bg),
	border = hex(palette.default.border),
	applied = nil,
	shown = false,
	drawing_bg = false,
}

-- ポップアップの窓全体の透明度は変えられないので、item ごとに色の alpha と y_offset を動かす。
-- 棒グラフ (cava の窓) は SketchyBar の外なので動かせない。アニメーションの終わりに合わせて出す (open_popup)。
local FADE_IN_FRAMES = 10 -- 60 フレームで 1 秒。棒グラフがないときの長さ
local FADE_OUT_FRAMES = 8 -- 待たされる感じがしないよう、開くときより短くする
local FADE_IN_FRAMES_VIZ = 24 -- ホバーから cava の準備ができるまでの時間 (約 0.4 秒) に合わせる
local SLIDE_DISTANCE = 4 -- pt。ポップアップが低いので、文字が item の窓からはみ出して切れない範囲にする
local current_palette = palette.default -- apply_palette が更新する

local slide_items = {}
for _, row in ipairs(ROWS) do
	slide_items[#slide_items + 1] = { rows[row.key].item, row.y_offset }
end

local function popup_background(p)
	if viz.drawing_bg then
		return { color = with_alpha(p.bg, 0), border_color = with_alpha(p.border, 0) }
	end
	return { color = p.bg, border_color = p.border }
end

local function popup_look(visible)
	local p = current_palette
	local function color(c)
		return visible and c or with_alpha(c, 0)
	end
	local dy = visible and 0 or SLIDE_DISTANCE
	anchor:set({ popup = { background = popup_background(p) } })
	rows.title.item:set({ label = { color = color(p.text) } })
	rows.artist.item:set({ label = { color = color(p.subtext) } })
	for _, entry in ipairs(slide_items) do
		entry[1]:set({ y_offset = entry[2] + dy })
	end
end

local function popup_fade_in(frames)
	sbar.animate("sin", frames, function()
		popup_look(true)
	end)
end

local function popup_fade_out()
	sbar.animate("sin", FADE_OUT_FRAMES, function()
		popup_look(false)
	end)
end

local fading_out = false -- close_popup が重ねて呼ばれても、やり直さない

-- Spotify が最前面のとき、bracket の枠線を太く明るくして、画像の周りにリングを作る (items/system.lua の pill と同じ配色)。
-- bracket の背景は黒のままなので、リングと画像の間には、黒い隙間 (BRACKET_PADDING - RING_WIDTH) ができる。
-- ピン留めの枠線とは同じ枠線を使うので、両方のときはピン留めの色にする (今はリングと同じ色)。太さはリングのときだけ変える。
local RING_COLOR = colors.space.bg_focused
local RING_WIDTH = 3
local ring_active = false

local function update_border(pinned)
	local color = colors.bracket.border_color
	if pinned then
		color = colors.pinned_border
	elseif ring_active then
		color = RING_COLOR
	end
	bracket:set({
		background = { border_color = color, border_width = ring_active and RING_WIDTH or colors.bracket.border_width },
	})
end

-- 曲情報がなくなってポップアップが閉じるとき (show_icon) にも外す。
local pin = ui.pin(update_border)

-- ui.timer が世代で管理するので、停止 -> 再生が短時間で続いても古いループは残らない。
-- 停止しても角度は戻さず、次の再生は止まった角度から続ける。
local angle = 0
local spinning = false
local spin_timer = ui.timer()

local function tick()
	step_time()
	angle = (angle + ROTATION_STEP) % 360
	spotify:set({ background = { image = { rotation = angle } } })
	spin_timer.start(TICK, tick)
end

local function set_spinning(on)
	if on == spinning then
		return
	end
	spinning = on
	if on then
		-- 開始の瞬間には進めず、1 周期待ってから最初のステップを進める。
		-- 瞬間に進めると、再生と停止を素早く繰り返したとき、そのたびに回転が進んでしまう。
		spin_timer.start(TICK, tick)
	else
		spin_timer.cancel()
	end
end

-- 覆いの初期色は暗い側なので、最初の状態が暗いなら何もしない。
local lit = false

local function set_lit(on)
	if on == lit then
		return
	end
	lit = on
	local color = on and PLAYING_COLOR or PAUSED_COLOR
	sbar.animate("sin", FADE_FRAMES, function()
		spotify:set({ label = { background = { color = color } } })
	end)
end

-- ポップアップの開閉 (open_popup、close_popup) が呼ぶので、その前に定義する。
local function viz_look()
	return viz.fg .. viz.played .. viz.bg .. viz.border
end

-- ひな形が読めなければ nil。
-- 窓の位置は、起動のたびに画面外に置く (VIZ_HIDDEN_POS)。実際の位置は、準備ができてから制御ファイルで指示する。
local function viz_render_config()
	local template = fs.read(VIZ_TEMPLATE)
	if not template then
		return nil
	end
	return (template:gsub("@(%u+)@", {
		X = VIZ_HIDDEN_POS,
		Y = VIZ_HIDDEN_POS,
		W = VIZ_WIDTH,
		H = POPUP_BG_HEIGHT,
		FG = viz.fg,
		PLAYED = viz.played,
		BG = viz.bg,
		BORDER = viz.border,
	}))
end

-- ポップアップが描かれる前は nil を返す (ui.visible_rect)。
local function viz_slot()
	return ui.visible_rect("spotify.viz")
end

-- ポップアップは半ポイント位置に描かれることがある (中央揃えで、項目の位置が x.5 のとき) ので、丸めずに小数のまま渡す。
local function viz_window_pos(rect)
	local x = rect.origin[1] - VIZ_LEFT
	local y = rect.origin[2] + rect.size[2] / 2 - POPUP_BG_HEIGHT / 2
	return x, y
end

-- 取れないまま VIZ_SLOT_RETRIES 回で諦めたら、何もしない。
local function viz_find_slot(id, found, n)
	n = n or 0
	if id ~= viz.id then
		return
	end
	local rect = viz_slot()
	if rect then
		found(viz_window_pos(rect))
	elseif n < VIZ_SLOT_RETRIES then
		sbar.delay(VIZ_SLOT_INTERVAL, function()
			viz_find_slot(id, found, n + 1)
		end)
	end
end

local VIZ_OPEN = [[
open -n -a %q --env XDG_CONFIG_HOME=%q --env CAVAVIZ_CONTROL=%q --env CAVAVIZ_PROGRESS=%q --env CAVAVIZ_AUDIO=%q --env CAVAVIZ_READY_BIN="$(command -v sketchybar)" --env CAVAVIZ_READY_EVENT=%s --env CAVAVIZ_READY_ID=%d --stderr /dev/null --args -p %q
]]

-- cava は 100ms ごとに見て、tap を作る / 解放する。
local function write_audio(on)
	fs.write(VIZ_AUDIO, on and "on" or "off")
end

-- 書き出しや制御ファイルの書き込みに失敗したら、起動しない。
-- 制御ファイル ("show X Y" か "hide") は、起動後も窓の表示、移動、非表示の指示に使う。
local function viz_launch(id)
	viz.applied = viz_look()
	write_audio(spinning) -- 起動前に書く (cava は起動時に読む)
	local config = viz_render_config()
	if not (config and fs.write(VIZ_CONFIG, config) and fs.write(VIZ_CONTROL, "hide")) then
		return
	end
	sbar.exec(
		string.format(
			VIZ_OPEN,
			VIZ_APP,
			VIZ_CONFIG_HOME,
			VIZ_CONTROL,
			VIZ_PROGRESS,
			VIZ_AUDIO,
			VIZ_READY_EVENT,
			id,
			VIZ_CONFIG
		)
	)
end

-- cava は SIGUSR2 でグラデーションの色だけを読み直す
-- (foreground / background は読み直さないので、色はグラデーションで指定している。窓も音声の取得も作り直さない)。
-- cava が準備中 (ready の前) だと、シグナルの受け口がなく、終了させてしまうので、
-- 準備完了のイベントのあとに行う (そのとき viz.applied とのずれを直す)。
local VIZ_RECOLOR = "pkill -USR2 -f '[C]avaViz.app/Contents/MacOS/cava'"

local function viz_apply_color()
	if not viz.running or not viz.ready or viz.applied == viz_look() then
		return
	end
	viz.applied = viz_look()
	local config = viz_render_config()
	if config and fs.write_atomic(VIZ_CONFIG, config) then
		sbar.exec(VIZ_RECOLOR)
	end
end

local function viz_control(text)
	sbar.exec(string.format("printf %%s %q > %q", text, VIZ_CONTROL))
end

local function viz_take_background()
	if viz.drawing_bg or not (viz.running and viz.ready and viz.shown) then
		return
	end
	viz.drawing_bg = true
	anchor:set({ popup = { background = popup_background(current_palette) } })
end

local function viz_take_background_later(id)
	sbar.delay(VIZ_HANDOVER_DELAY, function()
		if id == viz.id then
			viz_take_background()
		end
	end)
end

-- use_cache: 前回の位置が分かっていれば、ポップアップが描かれるのを待たずに、まずそこへ出す
-- (ポップアップの位置は、普通は変わらない)。空きの位置が取れたあと、ずれていたときだけ出し直す。
local function viz_show_at_slot(use_cache)
	if use_cache and viz.cache then
		viz_control(string.format("show %.2f %.2f", viz.cache.x, viz.cache.y))
	end
	local id = viz.id
	viz_find_slot(id, function(x, y)
		local c = viz.cache
		if not (use_cache and c and c.x == x and c.y == y) then
			viz.cache = { x = x, y = y }
			viz_control(string.format("show %.2f %.2f", x, y))
		end
		viz.shown = true
		viz_take_background_later(id)
	end)
end

local function viz_ensure_hidden()
	if viz.running then
		return
	end
	viz.running = true
	viz.ready = false
	viz.shown = false
	viz.on_ready = nil
	viz.id = viz.id + 1 -- 直前の viz_stop の「止め直し」で、起動したばかりの cava を止めないようにする
	viz_launch(viz.id)
end

-- 止めるときは、先に窓を隠す。pkill だけだと、プロセスが終わるまで約 0.1〜0.2 秒、窓が残って見える
-- (ポップアップは先に消える)。制御ファイルへの書き込みは Lua で同期的に行い (シェルの起動を待たない)、
-- cava は書き込みで即座に起きて窓を隠す (消えるまで約 0.02 秒)。
local function viz_hide_now()
	fs.write(VIZ_CONTROL, "hide")
end

local function viz_stop()
	-- ポップアップ自身の背景を先に戻す (窓は、そのあとすぐに隠れる)。アニメーションの中で戻すと、透明から滑らかに
	-- 変わってしまうので、アニメーションの外で行う。
	viz.drawing_bg = false
	anchor:set({ popup = { background = popup_background(current_palette) } })
	viz_hide_now()
	viz.id = viz.id + 1 -- 位置を待っている処理を取り消す
	local id = viz.id
	viz.running = false
	viz.ready = false
	viz.shown = false
	viz.on_ready = nil
	sbar.exec(VIZ_STOP)
	-- open は起動に約 0.3 秒かかる。起動の直後に止めると、まだ存在しない窓には pkill が当たらず、
	-- 遅れて起動した窓が残ってしまう。その間に再び起動されていなければ、もう一度止める。
	sbar.delay(VIZ_KILL_AGAIN, function()
		if id == viz.id then
			sbar.exec(VIZ_STOP)
		end
	end)
end

local function viz_start()
	if not showing_art or not popup_open then
		return
	end
	-- 普通は、ホバーの時点で起動済み (viz_wait)。ここで起動した場合 (ポップアップを開いたまま、停止から
	-- 再生に戻したときなど) は、起動の指示 (制御ファイルへの "hide" の書き込み) と、窓を出す指示 (同じファイルへの
	-- "show" の書き込み) の順序が決まらず、"hide" があとになると窓が出なくなる。そのため、準備完了を待ってから出す。
	local was_running = viz.running
	viz_ensure_hidden()
	if was_running then
		viz_show_at_slot(true)
	else
		viz.on_ready = function()
			viz_show_at_slot(false)
		end
	end
end

-- on_ready があとで呼ばれるときは true、再生中でない、または準備が済んでいるときは false を返す。
local function viz_wait(on_ready)
	if not showing_art then
		return false
	end
	viz_ensure_hidden()
	if viz.ready then
		return false
	end
	viz.on_ready = on_ready
	return true
end

sbar.add("event", VIZ_READY_EVENT)
spotify:subscribe(VIZ_READY_EVENT, function(env)
	-- 取り消された (止めた、または起動し直した) 起動のイベントは無視する
	if not viz.running or tostring(env.ID) ~= tostring(viz.id) then
		return
	end
	viz.ready = true
	viz_apply_color() -- 起動してから準備完了までの間に、色が変わっていたとき
	if viz.shown then
		viz_take_background_later(viz.id) -- 準備完了より先に、窓を出す指示を出していたとき
	end
	local on_ready = viz.on_ready
	viz.on_ready = nil
	if on_ready then
		on_ready()
	end
end)

os.execute(string.format("mkdir -p %q", VIZ_RUNTIME_DIR))
-- 再読み込み前の窓が残っていたら止める
viz_stop()

-- 実際の位置は取得できしだい、アニメーションなしで合わせる (開いている間にバーが古い位置から伸びないように)。
local function open_popup()
	popup_open = true
	fading_out = false
	local is_current_open = open_session.begin()
	local viz_done = true
	local animation_done = false
	local viz_shown = false

	local function show_viz()
		if viz_shown or not (viz_done and animation_done) or not popup_open or not is_current_open() then
			return
		end
		viz_shown = true
		viz_start()
	end

	viz_done = not viz_wait(function()
		viz_done = true
		show_viz()
	end)
	local frames = viz_done and FADE_IN_FRAMES or FADE_IN_FRAMES_VIZ

	write_progress()
	popup_look(false)
	anchor:set({ popup = { drawing = true } })
	popup_fade_in(frames)
	sbar.delay(frames / 60, function()
		animation_done = true
		show_viz()
	end)
	-- 準備ができなくても (許可がなくて cava が起動できないときなど)、この秒数で窓を出す指示を出す
	sbar.delay(VIZ_WAIT_TIMEOUT, function()
		viz_done = true
		show_viz()
	end)
	refresh_position()
end

-- 棒グラフの窓は、消え残りを避けるため、先に即座に隠す (窓は SketchyBar の外なのでフェードできない)。
-- mouse.exited と mouse.exited.global が続けて来ても、1 回だけ行う。
local function close_popup()
	if pin.active then
		return
	end
	local was_open = popup_open
	popup_open = false
	-- 窓を隠す指示 (制御ファイルへの同期的な書き込み) を、アニメーションより先に出す
	viz_stop()
	if not was_open then
		if not fading_out then
			anchor:set({ popup = { drawing = false } })
		end
		return
	end
	fading_out = true
	local is_current_open = open_session.snapshot()
	popup_fade_out()
	sbar.delay(FADE_OUT_FRAMES / 60, function()
		if is_current_open() and not popup_open then
			fading_out = false
			anchor:set({ popup = { drawing = false } })
		end
	end)
end

-- 棒、背景、枠の色は、cava が動いていれば SIGUSR2 で即座に変わる (止まっていれば、次の起動で入る)。
local function apply_palette(p)
	current_palette = p
	local shadow_color = with_alpha(p.bg, TEXT_SHADOW_ALPHA)
	anchor:set({ popup = { background = popup_background(p) } })
	rows.title.item:set({ label = { color = p.text, shadow = { color = shadow_color } } })
	rows.artist.item:set({ label = { color = p.subtext, shadow = { color = shadow_color } } })
	viz.fg = p.viz
	viz.played = p.played
	viz.bg = hex(p.bg)
	viz.border = hex(p.border)
	viz_apply_color()
end

-- Spotify が最前面かどうかは front_app_switched (INFO は前面になったアプリ名) で分かる。
-- アイコンを出している間 (未起動・停止中) は、リングにしない (アイコンの見た目は変えない)。
local SPOTIFY_APP_NAME = "Spotify"
local spotify_front = false

local function update_ring()
	ring_active = spotify_front and showing_art
	update_border(pin.active)
end

local function show_art()
	showing_art = true
	update_ring()
	spotify:set({
		icon = { drawing = false },
		label = { drawing = true },
		background = { image = { drawing = true } },
	})
end

local function show_icon()
	showing_art = false
	update_ring()
	pin.set(false)
	popup_open = false
	viz_stop()
	spotify:set({
		icon = { drawing = true },
		label = { drawing = false },
		background = { image = { drawing = false } },
	})
	anchor:set({ popup = { drawing = false } })
end

local function on_artwork(files, histogram)
	spotify:set({ background = { image = { string = files.small } } })
	apply_palette(palette.from_histogram(histogram) or palette.default)
	show_art()
end

-- meta は { title, artist }、timing は { position, duration } (どちらも秒)。
-- 取れなかったときは nil で、ポップアップ (曲情報、再生位置) はそのまま。
local function apply(state, track_id, meta, timing)
	local playing = state == "Playing"
	if playing or state == "Paused" then
		local changed = track_id ~= artwork.current()
		if changed then
			artwork.load(track_id, on_artwork)
		end
		if meta then
			set_popup_info(meta)
		end
		if timing then
			rebase(timing.position, timing.duration, playing, changed)
		end
		set_spinning(playing)
		set_lit(playing)
		write_audio(playing) -- 一時停止したら tap を解放し、再生が始まったら作り直す
		viz_start() -- ポップアップを開いたまま曲が始まったとき
	else
		set_spinning(false)
		set_lit(false)
		artwork.clear()
		show_icon()
	end
end

sbar.add("event", "spotify_change", "com.spotify.client.PlaybackStateChanged")

spotify:subscribe("spotify_change", function(env)
	local info = env.INFO
	if type(info) ~= "table" then
		return
	end
	apply(script.parse_notification(info))
end)

spotify:subscribe("front_app_switched", function(env)
	spotify_front = env.INFO == SPOTIFY_APP_NAME
	update_ring()
end)

-- Spotify の終了は通知が来るとは限らないので、画像を出している間だけ、起動中かを定期的に確認する。
spotify:subscribe("routine", function()
	if not showing_art then
		return
	end
	sbar.exec("pgrep -x Spotify", function(out)
		if type(out) == "string" and out:find("%d") then
			return
		end
		apply(nil)
	end)
end)

-- バーの外へ出たときは mouse.exited.global でも閉じる。
hit:subscribe("mouse.entered", function()
	-- ピン留め中は開いたままなので、開き直さない (フェードインのやり直しになる)
	if showing_art and not popup_open then
		open_popup()
	end
end)

hit:subscribe({ "mouse.exited", "mouse.exited.global" }, close_popup)

-- 表示は上の分散通知で追従するので、ここでは Spotify に命令を送るだけにする。
local function spotify_command(command)
	sbar.exec(script.command(command))
end

-- ウィンドウの表示は open で行う。-g -j の自動起動で隠れているときも前面に出て、
-- ウィンドウを閉じただけのときも開き直す。名前 (open -a Spotify) ではなく
-- Home Manager Apps のパスで指定する (名前だと更新用の一時コピーに解決されることがある)。
local SPOTIFY_APP = HOME .. "/Applications/Home Manager Apps/Spotify.app"

-- SketchyBar にはダブルクリックのイベントがなく、クリックが 2 回届くだけなので、
-- 1 回目のクリックの再生/一時停止を DOUBLE_CLICK_INTERVAL 秒だけ待つ。そのため、再生/一時停止はクリックからこの秒数だけ遅れる。
-- macOS の既定のダブルクリックの間隔は約 0.5 秒だが、再生/一時停止の遅れを抑えるため短くしてある。
local DOUBLE_CLICK_INTERVAL = 0.3
-- Spotify 専用の workspace (modules/aerospace.nix の on-window-detected で Spotify を移す先)
local SPOTIFY_WORKSPACE = "F"
local DOUBLE_CLICK_COMMAND = string.format(
	'[ "$(aerospace list-workspaces --focused)" = %q ] && aerospace workspace-back-and-forth || open %q',
	SPOTIFY_WORKSPACE,
	SPOTIFY_APP
)
local click_timer = ui.timer()

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		if click_timer.pending then
			click_timer.cancel()
			sbar.exec(DOUBLE_CLICK_COMMAND)
			return
		end
		click_timer.start(DOUBLE_CLICK_INTERVAL, function()
			spotify_command("playpause")
		end)
	elseif env.BUTTON == "right" then
		pin.toggle(popup_open)
	end
end)

-- トラックパッドは 1 回のスワイプで多数のイベントが出る (慣性スクロール含む) ので、
-- 一度反応したら SCROLL_COOLDOWN 秒は無視して、1 スワイプで 1 曲だけ動かす。
-- SCROLL_DELTA の符号は、上スクロールが正。
local SCROLL_COOLDOWN = 1.0
local PREVIOUS_REFRESH_DELAY = 0.4 -- 秒
local scroll_cooldown = ui.timer()

hit:subscribe("mouse.scrolled", function(env)
	local delta = tonumber(env.SCROLL_DELTA)
	if not delta or delta == 0 or scroll_cooldown.pending then
		return
	end
	scroll_cooldown.start(SCROLL_COOLDOWN, function() end)
	local previous = delta > 0
	spotify_command(previous and "previous track" or "next track")
	if previous then
		-- 曲の途中なら、Spotify は同じ曲の先頭に戻す (シーク)。シークでは分散通知が来ないので、
		-- 少し待って (Spotify が位置を戻すのを待つ)、実際の位置に合わせ直す。別の曲に戻った場合は通知が来る。
		sbar.delay(PREVIOUS_REFRESH_DELAY, function()
			refresh_position()
		end)
	end
end)

-- 起動時 (再読み込み含む) に既に再生中でも拾えるよう、現在の状態を一度だけ取得する
sbar.exec(script.SNAPSHOT_COMMAND, function(out)
	local state, track_id, meta, timing = script.parse_snapshot(out)
	if state then
		apply(state, track_id, meta, timing)
	end
end)
