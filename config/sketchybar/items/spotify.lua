-- Spotify のアルバム画像を表示し、再生状態を明るさと回転で示す。
--   再生中  : 覆いを外して明るくし、画像をゆっくり回す
--   一時停止: 画像を暗くし、回転はその角度で止める
--   未起動・停止中: 画像の代わりに Spotify のアイコンを出す (アイテム自体は常に表示)
--   切り替え時は覆いの濃さを滑らかに変える
-- 状態は Spotify の分散通知 (media_change は macOS 26 で発火しない) から受け取り、
-- 画像は osascript の artwork url を取得して使う。
-- 回転は background.image.rotation を使う (SketchyBar#815 のパッチが前提、pkgs/sketchybar/)。
-- 操作: 左クリックで再生/一時停止、上スクロールで前の曲、下スクロールで次の曲。
-- マウスを乗せると、曲名・アーティスト・アルバムをポップアップで表示する。
-- マウス操作は、bracket 全体を覆う透明な item (hit) が受ける。画像の item は再描画が多く、
-- マウスを購読させると mouse.exited が届かずポップアップが閉じなくなることがあるため (ui.add_hit_layer)。

local ui = require("ui")
local colors = require("colors")

local SIZE = 28 -- 表示サイズ (pt)
local ART_PX = SIZE * 4 -- キャッシュする画像の一辺 (px)
local ICON_PX = 16 -- アイコンのフォントサイズ。このフォントでは字面が一辺 ICON_PX の正方形になる
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/spotify"

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
		font = "sketchybar-app-font:Regular:" .. ICON_PX .. ".0",
		color = 0x99ffffff, -- 起動していないことが分かるよう、少し薄くする
		width = SIZE,
		align = "left",
		padding_left = (SIZE - ICON_PX) / 2,
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
		background = colors.popup,
	},
})

ui.add_bracket("spotify.bracket", { spotify }, nil, ui.bracket_padding)

-- bracket の範囲 (spotify の幅 + 左右の padding) 全体でマウス操作を受ける
local hit = ui.add_hit_layer("spotify.hit", SIZE, ui.bracket_padding)

-- ポップアップの中身。縦に追加順 (上から曲名、アーティスト、アルバム) で並ぶ。
-- 空の項目 (ポッドキャストのアーティストなど) は非表示にする。
local POPUP_MAX_CHARS = 24

local function add_popup_row(name, font_style, size, color)
	return sbar.add("item", name, {
		position = "popup.spotify",
		drawing = false,
		icon = { drawing = false },
		label = {
			font = { family = "Hack Nerd Font", style = font_style, size = size },
			color = color,
			padding_left = 8,
			padding_right = 8,
		},
	})
end

local rows = {
	title = add_popup_row("spotify.title", "Bold", 14.0, colors.white),
	artist = add_popup_row("spotify.artist", "Regular", 12.0, colors.white),
	album = add_popup_row("spotify.album", "Regular", 11.0, 0xaaffffff),
}

-- 長い文字列は POPUP_MAX_CHARS 文字で切る (utf8.len が nil なら不正なバイト列なのでそのまま使う)
local function truncate(text)
	local len = utf8.len(text)
	if len == nil or len <= POPUP_MAX_CHARS then
		return text
	end
	return text:sub(1, utf8.offset(text, POPUP_MAX_CHARS + 1) - 1) .. "..."
end

local function set_popup_info(meta)
	for key, row in pairs(rows) do
		local text = meta[key]
		if type(text) ~= "string" then
			text = ""
		end
		row:set({ drawing = text ~= "", label = { string = truncate(text) } })
	end
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
	spotify:set({
		icon = { drawing = true },
		label = { drawing = false },
		background = { image = { drawing = false } },
		popup = { drawing = false },
	})
end

-- アルバム画像を取得してキャッシュし、そのパスを標準出力に返す。
-- 未起動の Spotify を osascript が起動してしまわないよう、先に pgrep で確認する。
local FETCH_ARTWORK = string.format(
	[[
pgrep -x Spotify >/dev/null || exit 1
url=$(osascript -e 'tell application "Spotify" to get artwork url of current track') || exit 1
[ -n "$url" ] || exit 1
dir=%q
file="$dir/${url##*/}.jpg"
if [ ! -s "$file" ]; then
  mkdir -p "$dir"
  find "$dir" -type f -mtime +30 -delete 2>/dev/null
  curl -sfL --max-time 10 "$url" -o "$file.tmp" \
    && sips -s format jpeg -s dpiWidth 72 -s dpiHeight 72 -Z %d "$file.tmp" --out "$file" >/dev/null \
    || { rm -f "$file.tmp"; exit 1; }
  rm -f "$file.tmp"
fi
printf '%%s' "$file"
]],
	CACHE_DIR,
	ART_PX
)

local current_track = nil

local function load_artwork(track_id)
	current_track = track_id
	sbar.exec(FETCH_ARTWORK, function(path)
		-- 取得中に曲が変わった・停止した場合は捨てる
		if current_track ~= track_id then
			return
		end
		if type(path) ~= "string" or path == "" then
			current_track = nil -- 次のイベントで再試行する
			return
		end
		spotify:set({ background = { image = { string = path } } })
		show_art()
	end)
end

-- meta は { title, artist, album }。曲情報が取れなかったときは nil で、ポップアップはそのまま。
local function apply(state, track_id, meta)
	local playing = state == "Playing"
	if playing or state == "Paused" then
		if track_id ~= current_track then
			load_artwork(track_id)
		end
		if meta then
			set_popup_info(meta)
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
	apply(info["Player State"], info["Track ID"], {
		title = info["Name"],
		artist = info["Artist"],
		album = info["Album"],
	})
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
	end
end)

hit:subscribe({ "mouse.exited", "mouse.exited.global" }, function()
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
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & tab & (id of current track) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track)' 2>/dev/null]],
	function(out)
		if type(out) ~= "string" then
			return
		end
		local state, track_id, title, artist, album = out:match("^(%a+)\t(%S+)\t([^\t]*)\t([^\t]*)\t([^\t\n]*)")
		if INITIAL_STATES[state] then
			apply(INITIAL_STATES[state], track_id, { title = title, artist = artist, album = album })
		end
	end
)
