-- Spotify のアルバム画像を表示し、再生状態を明るさと回転で示す。
--   再生中  : 覆いを外して明るくし、画像をゆっくり回す
--   一時停止: 画像を暗くし、回転はその角度で止める
--   未起動・停止中: 画像の代わりに Spotify のアイコンを出す (アイテム自体は常に表示)
--   切り替え時は覆いの濃さを滑らかに変える
-- 状態は Spotify の分散通知 (media_change は macOS 26 で発火しない) から受け取り、
-- 画像は osascript の artwork url を取得して使う。
-- ポップアップの再生位置は、通知の Playback Position を基準に、ローカルの時計で進める
-- (毎秒の osascript の取得は行わない。詳しくは再生位置の節を参照)。
-- 回転は background.image.rotation を使う (SketchyBar#815 のパッチが前提、pkgs/sketchybar/)。
-- 操作: 左クリックで再生/一時停止、上スクロールで前の曲、下スクロールで次の曲。
-- マウスを乗せると、カバー画像と、曲名・アーティスト・アルバム・再生位置をポップアップで横並びに表示する
-- (配置は FelixKratz/dotfiles の spotify ウィジェットを参考にした。表示のみで、ボタンは持たない)。
-- マウス操作は、bracket 全体を覆う透明な item (hit) が受ける。画像の item は再描画が多く、
-- マウスを購読させると mouse.exited が届かずポップアップが閉じなくなることがあるため (ui.add_hit_layer)。

local ui = require("ui")
local colors = require("colors")

local SIZE = 24 -- 表示サイズ (pt)。アイコンのフォントサイズも同じ値にする (このフォントでは字面が一辺 SIZE の正方形になる)
local ART_PX = SIZE * 4 -- キャッシュする画像の一辺 (px)
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/spotify"

-- ポップアップの配置 (pt)。見た目は実機で確認して調整する。
-- 左から 余白 | カバー画像 | 余白 | 文字の領域 (TEXT_WIDTH) | 余白 の順に並べる。
local COVER_SIZE = 72
local COVER_PX = COVER_SIZE * 4 -- ポップアップ用に、アイコン用 (ART_PX) とは別に大きい画像をキャッシュする
local POPUP_HEIGHT = 98
local POPUP_PADDING = 12
local TEXT_WIDTH = 200
-- ポップアップの文字は、メニューバーと同じシステムフォントにする。
-- ファミリに ".AppleSystemUIFont" を指定すると欧文は SF になり、日本語は自動で
-- メニューバーと同じ ".Hiragino Kaku Gothic Interface" (W4) に切り替わる (CoreText で確認)。
-- "SF Pro" などの名前は、SF Pro が入っていないと Helvetica に解決されてしまう。
local POPUP_FONT_FAMILY = ".AppleSystemUIFont"
local POPUP_FONT_STYLE = "Bold" -- 欧文は System Font Bold、日本語は W6 になる (Regular なら W4)
local TIME_WIDTH = 36 -- 再生位置バーの両脇の時刻 (経過 / 総時間) の幅
local SLIDER_WIDTH = TEXT_WIDTH - 2 * TIME_WIDTH

-- bracket は円にする。幅を高さ (colors.bracket.height) と同じにし、角の半径は短辺の半分以上にする
-- (背景の描画側で短辺の半分に丸められる)。左右の padding は、円の中に画像が同心で収まる値。
local BRACKET_PADDING = (colors.bracket.height - SIZE) / 2

-- 回転: 1 周が ROTATION_PERIOD 秒になるよう、TICK 秒ごとに角度を進める。
-- 負の値は rotation を減らす向き (見た目の向きはこの符号で決まる)。
local ROTATION_PERIOD = 60
local TICK = 1
local ROTATION_STEP = -360 * TICK / ROTATION_PERIOD

-- 画像に重ねる覆いの色 (ARGB)。alpha が 0x00 で透明、0xff で真っ黒
local PAUSED_COLOR = 0x99000000
local PLAYING_COLOR = 0x00000000
local FADE_FRAMES = 12 -- 再生/一時停止の切り替えにかけるフレーム数 (60 フレームで 1 秒)

-- 常に表示する。曲がない間 (未起動・停止中) は Spotify のアイコン、再生中・一時停止中は
-- アルバム画像を出す。初期状態はアイコン側 (画像と覆いは非表示)。
local spotify = ui.add_item("spotify", "right", {
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
		color = 0x99ffffff, -- 起動していないことが分かるよう、少し薄くする
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
		color = 0x00000000,
		image = {
			drawing = false,
			scale = SIZE / ART_PX,
			corner_radius = SIZE / 2,
		},
	},
	popup = {
		align = "center",
		horizontal = true,
		height = POPUP_HEIGHT,
		background = colors.popup,
	},
})

ui.add_bracket("spotify.bracket", { spotify }, {
	background = { color = 0xff000000, corner_radius = colors.bracket.height / 2 },
}, BRACKET_PADDING)

-- bracket の範囲 (spotify の幅 + 左右の padding) 全体でマウス操作を受ける
local hit = ui.add_hit_layer("spotify.hit", SIZE, BRACKET_PADDING)

-- ポップアップの中身。横に追加順で並ぶ: カバー画像 | 文字の領域。
-- 文字の領域は、曲名・アーティスト・アルバム・再生位置の item を width = 0 にして同じ x から
-- y_offset で縦にずらして重ね、その右に TEXT_WIDTH の空き (spotify.pad.body) を置いて幅を確保する。
-- 空の項目 (ポッドキャストのアーティストなど) は非表示にする (その行は空く)。
-- 文字は POPUP_FONT_FAMILY / POPUP_FONT_STYLE (メニューバーと同じフォント) で、size と color だけ行ごとに変える。
-- features は OpenType の機能タグ (カンマ区切り)。時刻には等幅数字の "tnum" を渡す
local function popup_font(size, features)
	return { family = POPUP_FONT_FAMILY, style = POPUP_FONT_STYLE, size = size, features = features }
end

local function add_popup_spacer(name, width)
	return sbar.add("item", name, {
		position = "popup.spotify",
		width = width,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
	})
end

add_popup_spacer("spotify.pad.left", POPUP_PADDING)

-- 画像の表示サイズは 実ピクセル * scale (アイコンと同じ)。画像は取得できてから出す。
-- 枠線はポップアップの枠 (colors.popup) と同じ色と太さで、画像の外側にくっつける。
-- item の背景を画像より枠線の太さの 2 倍だけ大きくし、その枠線 (図形の内側に引かれる) を外周の
-- 1 本分に置く。画像は背景の左端から枠線の太さだけ内側 (image.padding_left)、縦は中央に描かれるので、
-- 枠線と画像は重ならない。item の幅 (COVER_BOX) は画像より枠線の分だけ広い。
local COVER_RADIUS = 6
local COVER_BORDER = colors.popup.border_width
local COVER_BOX = COVER_SIZE + 2 * COVER_BORDER

local cover = sbar.add("item", "spotify.cover", {
	position = "popup.spotify",
	width = COVER_BOX,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = { drawing = false },
	background = {
		drawing = true,
		color = 0x00000000,
		height = COVER_BOX,
		corner_radius = COVER_RADIUS + COVER_BORDER, -- 画像の角 (COVER_RADIUS) と同心になる
		border_width = COVER_BORDER,
		border_color = colors.popup.border_color,
		image = {
			drawing = false,
			scale = COVER_SIZE / COVER_PX,
			corner_radius = COVER_RADIUS,
			padding_left = COVER_BORDER,
		},
	},
})

add_popup_spacer("spotify.pad.cover", POPUP_PADDING)

-- max_cells は文字数の上限 (半角 1、全角 2 と数える)。TEXT_WIDTH に収まるよう、size から決めた値
-- 全角 (1em) だけの文字列が TEXT_WIDTH にほぼ収まる数 (曲名 14 文字 = 196pt、アーティスト 16 = 192pt、
-- アルバム 18 = 198pt)。SF の欧文は平均で 0.5em 強なので、半角だけだと曲名は領域より少し広くなりうる。
-- 実機で見て調整する。
local ROWS = {
	{ key = "title", size = 14.0, y_offset = 30, max_cells = 28 },
	{ key = "artist", size = 12.0, y_offset = 10, max_cells = 32 },
	{ key = "album", size = 11.0, y_offset = -7, max_cells = 36, color = 0xffaaaaaa },
}

local rows = {}
for _, row in ipairs(ROWS) do
	rows[row.key] = {
		max_cells = row.max_cells,
		item = sbar.add("item", "spotify." .. row.key, {
			position = "popup.spotify",
			drawing = false,
			width = 0,
			y_offset = row.y_offset,
			padding_left = 0,
			padding_right = 0,
			icon = { drawing = false },
			label = {
				font = popup_font(row.size),
				color = row.color,
				padding_left = 0,
				padding_right = 0,
			},
		}),
	}
end

-- 再生位置: 左に経過時間、右に総時間、間にバー。バーは表示だけ (操作は受けない)。
-- ポップアップを開いている間だけ、1 秒ごとに routine が来る (更新の仕組みは advance_time の付近)。
local time = sbar.add("slider", "spotify.time", SLIDER_WIDTH, {
	position = "popup.spotify",
	width = 0,
	y_offset = -32,
	padding_left = 0,
	padding_right = 0,
	update_freq = 1,
	updates = "when_shown",
	-- 時刻は等幅数字 (tnum) にして、秒が変わっても幅を変えない。
	-- 経過時間は左端、総時間は右端に寄せ、文字の領域の両端 (曲名の左端、バーの右端) にそろえる
	icon = {
		string = "00:00",
		font = popup_font(10.0, "tnum"),
		width = TIME_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = {
		string = "00:00",
		font = popup_font(10.0, "tnum"),
		width = TIME_WIDTH,
		align = "right",
		padding_left = 0,
		padding_right = 0,
	},
	slider = {
		percentage = 0,
		highlight_color = colors.white,
		background = { height = 4, corner_radius = 2, color = 0xff444444 },
	},
})

add_popup_spacer("spotify.pad.body", TEXT_WIDTH)
add_popup_spacer("spotify.pad.right", POPUP_PADDING)

-- 長い文字列は max_cells 幅で切る (全角は半角 2 つ分と数える。
-- utf8.len が nil なら不正なバイト列なのでそのまま使う)
local function truncate(text, max_cells)
	if utf8.len(text) == nil then
		return text
	end
	local cells = 0
	for pos, code in utf8.codes(text) do
		cells = cells + (code >= 0x2E80 and 2 or 1)
		if cells > max_cells then
			return text:sub(1, pos - 1) .. "..."
		end
	end
	return text
end

local function set_popup_info(meta)
	for key, row in pairs(rows) do
		local text = meta[key]
		if type(text) ~= "string" then
			text = ""
		end
		row.item:set({ drawing = text ~= "", label = { string = truncate(text, row.max_cells) } })
	end
end

-- 再生位置の表示は、基準の位置とその時刻 (os.time、整数秒) をもとに、ローカルの時計で 1 秒ずつ進める。
-- 基準は、分散通知の Playback Position と、ホバーで開いたときの osascript の取得で取り直す。
-- 通知は一時停止・再開・曲の切り替えで来るが、シークでは来ない (実機で確認)。
-- そのため、ポップアップを閉じている間のシークは、開いた瞬間の取得で直る。
-- 開いている間のシークは、次の通知か開き直しまで直らない。毎秒の osascript の取得は行わない。
-- 整数秒の時計なので、表示は実際の位置から最大 1 秒ほどずれることがある (ずれは、基準を取った時刻の
-- 秒の中での位置と、毎秒の更新の位置の差で決まり、同じ基準の間は一定)。
local playback = { position = 0, at = os.time(), playing = false, duration = 0 }
local shown = nil -- 表示している秒 (整数)。ポップアップを開くたびに、見積もりに合わせ直す
local popup_open = false
local SNAP_BACK = 1.5 -- 再生中に、実際の位置が表示より後ろへこの秒数以上ずれていたら、表示も戻して合わせる

-- 分も 0 埋めの 2 桁 (mm:ss) にして、桁数が増えて幅が変わらないようにする。
-- 100 分以上は 3 桁になり、TIME_WIDTH を超えて見切れる。
local function format_time(seconds)
	return string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- 基準から進めた現在の位置 (秒)。曲の長さを超えない。
local function estimate()
	local position = playback.position
	if playback.playing then
		position = position + (os.time() - playback.at)
	end
	if playback.duration > 0 then
		position = math.min(position, playback.duration)
	end
	return position
end

local function render()
	if shown == nil or playback.duration <= 0 then
		return
	end
	sbar.animate("linear", 10, function()
		time:set({
			icon = { string = format_time(shown) },
			label = { string = format_time(playback.duration) },
			slider = { percentage = math.min(100, shown / playback.duration * 100) },
		})
	end)
end

-- 基準を取り直す。duration は秒 (nil なら前の値のまま)。
-- 再生中の小さな補正では、表示を戻さない: 実際の位置が表示より前なら進めて合わせ、
-- 後ろへ SNAP_BACK 秒未満のずれなら、表示はそのまま進める (数字が戻らないようにする)。
-- 一時停止中、曲の切り替え (force)、ポップアップを閉じている間は、そのまま合わせる。
local function rebase(position, duration, playing, force)
	local before = estimate()
	playback = {
		position = position,
		at = os.time(),
		playing = playing,
		duration = duration or playback.duration,
	}
	local diff = position - before
	if shown == nil or force or not playing or not popup_open or diff >= 0 or diff <= -SNAP_BACK then
		shown = math.floor(position)
	end
	if popup_open then
		render()
	end
end

-- 毎秒の更新 (ポップアップを開いている間だけ)。ローカルの時計で、表示を 1 秒ずつ進める。
local function advance_time()
	if shown == nil or not playback.playing then
		return
	end
	if math.floor(estimate()) > shown then
		shown = shown + 1
		render()
	end
end

time:subscribe("routine", advance_time)

-- 状態と位置と曲の長さ (ミリ秒) をタブ区切りで返す。未起動の Spotify を起動しないよう pgrep で確認する。
local POSITION_COMMAND =
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & tab & (player position as text) & tab & (duration of current track as text)' 2>/dev/null]]

-- ロケールによっては、位置の小数点がカンマになる
local function parse_position(text)
	return tonumber((text:gsub(",", ".")))
end

-- ホバーで開いたとき、基準を取り直す (閉じている間のシークはここで直る)
local function refresh_position()
	sbar.exec(POSITION_COMMAND, function(out)
		if type(out) ~= "string" then
			return
		end
		local state, position, duration = out:match("^(%a+)\t([%d.,]+)\t(%d+)")
		if state ~= "playing" and state ~= "paused" then
			return
		end
		position = parse_position(position)
		duration = tonumber(duration) / 1000
		if position and duration > 0 then
			rebase(position, duration, state == "playing")
		end
	end)
end

-- ポップアップを開く。表示は、通知で取った基準からの見積もりに合わせ、その後に取得で直す。
local function open_time()
	popup_open = true
	shown = math.floor(estimate())
	render()
	refresh_position()
end

-- 回転ループ。停止 -> 再生が短時間で続いても古いループが残らないよう世代で管理する。
-- 停止しても角度は戻さず、次の再生は止まった角度から続ける。
local angle = 0
local spinning = false
local generation = 0

local function tick(id)
	if not spinning or id ~= generation then
		return
	end
	angle = (angle + ROTATION_STEP) % 360
	spotify:set({ background = { image = { rotation = angle } } })
	sbar.delay(TICK, function()
		tick(id)
	end)
end

local function set_spinning(on)
	if on == spinning then
		return
	end
	spinning = on
	generation = generation + 1
	if on then
		-- 開始の瞬間には進めず、1 周期待ってから最初のステップを進める。
		-- 瞬間に進めると、再生と停止を素早く繰り返したとき、そのたびに回転が進んでしまう。
		local id = generation
		sbar.delay(TICK, function()
			tick(id)
		end)
	end
end

-- 再生中は明るく、それ以外は暗くする。覆いの初期色は暗い側なので、最初の状態が暗いなら何もしない。
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

-- 表示の切り替え。アルバム画像 (と覆い) を出すか、Spotify のアイコンを出すか。
-- 画像は取得できてから出す (取得前に切り替えると、画像のない覆いだけが見えてしまう)。
local showing_art = false

local function show_art()
	showing_art = true
	spotify:set({
		icon = { drawing = false },
		label = { drawing = true },
		background = { image = { drawing = true } },
	})
end

local function show_icon()
	showing_art = false
	popup_open = false
	playback.playing = false
	spotify:set({
		icon = { drawing = true },
		label = { drawing = false },
		background = { image = { drawing = false } },
		popup = { drawing = false },
	})
end

-- アルバム画像を取得してキャッシュし、アイコン用 (ART_PX) とポップアップ用 (COVER_PX) のパスを
-- タブ区切りで標準出力に返す。
-- キャッシュのファイル名には画像の一辺 (px) を含める。サイズを変えたとき、古い解像度の画像が残ると、
-- 表示サイズが設定からずれる (表示サイズ = 画像の実ピクセル * scale)。
-- 未起動の Spotify を osascript が起動してしまわないよう、先に pgrep で確認する。
local FETCH_ARTWORK = string.format(
	[[
pgrep -x Spotify >/dev/null || exit 1
url=$(osascript -e 'tell application "Spotify" to get artwork url of current track') || exit 1
[ -n "$url" ] || exit 1
dir=%q
small="$dir/${url##*/}.%d.jpg"
large="$dir/${url##*/}.%d.jpg"
if [ ! -s "$small" ] || [ ! -s "$large" ]; then
  mkdir -p "$dir"
  find "$dir" -type f -mtime +30 -delete 2>/dev/null
  src="$dir/${url##*/}.tmp"
  curl -sfL --max-time 10 "$url" -o "$src" \
    && sips -s format jpeg -s dpiWidth 72 -s dpiHeight 72 -Z %d "$src" --out "$small" >/dev/null \
    && sips -s format jpeg -s dpiWidth 72 -s dpiHeight 72 -Z %d "$src" --out "$large" >/dev/null \
    || { rm -f "$src" "$small" "$large"; exit 1; }
  rm -f "$src"
fi
printf '%%s\t%%s' "$small" "$large"
]],
	CACHE_DIR,
	ART_PX,
	COVER_PX,
	ART_PX,
	COVER_PX
)

local current_track = nil

local function load_artwork(track_id)
	current_track = track_id
	sbar.exec(FETCH_ARTWORK, function(path)
		-- 取得中に曲が変わった・停止した場合は捨てる
		if current_track ~= track_id then
			return
		end
		local small, large
		if type(path) == "string" then
			small, large = path:match("^([^\t]+)\t([^\t\n]+)")
		end
		if not small then
			current_track = nil -- 次のイベントで再試行する
			return
		end
		spotify:set({ background = { image = { string = small } } })
		cover:set({ background = { image = { string = large, drawing = true } } })
		show_art()
	end)
end

-- meta は { title, artist, album }、timing は { position, duration } (どちらも秒)。
-- 取れなかったときは nil で、ポップアップ (曲情報、再生位置) はそのまま。
local function apply(state, track_id, meta, timing)
	local playing = state == "Playing"
	if playing or state == "Paused" then
		local changed = track_id ~= current_track
		if changed then
			load_artwork(track_id)
		end
		if meta then
			set_popup_info(meta)
		end
		if timing then
			rebase(timing.position, timing.duration, playing, changed)
		end
		set_spinning(playing)
		set_lit(playing)
	else
		set_spinning(false)
		set_lit(false)
		current_track = nil
		show_icon()
	end
end

sbar.add("event", "spotify_change", "com.spotify.client.PlaybackStateChanged")

spotify:subscribe("spotify_change", function(env)
	local info = env.INFO
	if type(info) ~= "table" then
		return
	end
	-- Playback Position は秒 (小数)、Duration はミリ秒 (実機で確認)
	local position, duration = tonumber(info["Playback Position"]), tonumber(info["Duration"])
	local timing = nil
	if position and duration and duration > 0 then
		timing = { position = position, duration = duration / 1000 }
	end
	apply(info["Player State"], info["Track ID"], {
		title = info["Name"],
		artist = info["Artist"],
		album = info["Album"],
	}, timing)
end)

-- Spotify の終了は通知が来るとは限らないので、画像を出している間だけ、起動中かを定期的に確認する。
-- 終了していたら、曲がないときと同じくアイコンに戻す。
spotify:subscribe("routine", function()
	if not showing_art then
		return
	end
	sbar.exec("pgrep -x Spotify >/dev/null && echo running", function(out)
		if type(out) == "string" and out:find("running", 1, true) then
			return
		end
		apply(nil)
	end)
end)

-- ホバーでポップアップを開閉する (曲情報があるとき、つまり画像を出している間だけ)。
-- バーの外へ出たときは mouse.exited.global でも閉じる。
hit:subscribe("mouse.entered", function()
	if showing_art then
		spotify:set({ popup = { drawing = true } })
		open_time()
	end
end)

hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
	popup_open = false
	spotify:set({ popup = { drawing = false } })
end)

-- 操作: 左クリックで再生/一時停止、右クリックで Spotify のウィンドウを表示、
-- 上スクロールで前の曲、下スクロールで次の曲。
-- 表示は上の分散通知で追従するので、ここでは Spotify に命令を送るだけにする。
-- 未起動の Spotify を起動してしまわないよう、pgrep で確認してから送る。
local function spotify_command(command)
	sbar.exec(
		string.format([[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to %s']], command)
	)
end

-- ウィンドウの表示は open で行う。-g -j の自動起動で隠れているときも前面に出て、
-- ウィンドウを閉じただけのときも開き直す。名前 (open -a Spotify) ではなく
-- Home Manager Apps のパスで指定する (名前だと更新用の一時コピーに解決されることがある)。
local SPOTIFY_APP = os.getenv("HOME") .. "/Applications/Home Manager Apps/Spotify.app"

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		spotify_command("playpause")
	elseif env.BUTTON == "right" then
		sbar.exec(string.format("open %q", SPOTIFY_APP))
	end
end)

-- トラックパッドは 1 回のスワイプで多数のイベントが出る (慣性スクロール含む) ので、
-- 一度反応したら SCROLL_COOLDOWN 秒は無視して、1 スワイプで 1 曲だけ動かす。
-- SCROLL_DELTA の符号は上スクロールが正の想定。逆なら SCROLL_UP_SIGN を -1 にする。
local SCROLL_COOLDOWN = 1.0
local SCROLL_UP_SIGN = 1
local scroll_locked = false

hit:subscribe("mouse.scrolled", function(env)
	local delta = tonumber(env.SCROLL_DELTA)
	if not delta or delta == 0 or scroll_locked then
		return
	end
	scroll_locked = true
	sbar.delay(SCROLL_COOLDOWN, function()
		scroll_locked = false
	end)
	spotify_command(delta * SCROLL_UP_SIGN > 0 and "previous track" or "next track")
end)

-- 起動時 (再読み込み含む) に既に再生中でも拾えるよう、現在の状態を一度だけ取得する
local INITIAL_STATES = { playing = "Playing", paused = "Paused" }

-- 曲名などに "|" が含まれうるので、区切りにはタブを使う
sbar.exec(
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & tab & (id of current track) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text)' 2>/dev/null]],
	function(out)
		if type(out) ~= "string" then
			return
		end
		local state, track_id, title, artist, album, position, duration =
			out:match("^(%a+)\t(%S+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([%d.,]+)\t(%d+)")
		if INITIAL_STATES[state] then
			position = parse_position(position)
			duration = tonumber(duration) / 1000
			local timing = position and duration > 0 and { position = position, duration = duration } or nil
			apply(INITIAL_STATES[state], track_id, { title = title, artist = artist, album = album }, timing)
		end
	end
)
