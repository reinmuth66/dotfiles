-- Spotify のアルバム画像を表示し、再生状態を明るさと回転で示す。
--   再生中  : 覆いを外して明るくし、画像をゆっくり回す
--   一時停止: 画像を暗くし、回転はその角度で止める
--   切り替え時は覆いの濃さを滑らかに変える
-- 状態は Spotify の分散通知 (media_change は macOS 26 で発火しない) から受け取り、
-- 画像は osascript の artwork url を取得して使う。
-- 回転は background.image.rotation を使う (SketchyBar#815 のパッチが前提、pkgs/sketchybar/)。

local ui = require("ui")

local SIZE = 28 -- 表示サイズ (pt)
local ART_PX = SIZE * 4 -- キャッシュする画像の一辺 (px)
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

local spotify = ui.add_item("spotify", "right", {
	drawing = false,
	width = SIZE,
	icon = { drawing = false },
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
			scale = SIZE / ART_PX,
			corner_radius = SIZE / 2,
		},
	},
})

ui.add_bracket("spotify.bracket", { spotify }, nil, ui.bracket_padding)

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
		spotify:set({ drawing = true, background = { image = { string = path } } })
	end)
end

local function apply(state, track_id)
	local playing = state == "Playing"
	if playing or state == "Paused" then
		if track_id ~= current_track then
			load_artwork(track_id)
		end
		set_spinning(playing)
		set_lit(playing)
		spotify:set({ label = { drawing = true } })
	else
		set_spinning(false)
		set_lit(false)
		current_track = nil
		spotify:set({ drawing = false, label = { drawing = false } })
	end
end

sbar.add("event", "spotify_change", "com.spotify.client.PlaybackStateChanged")

spotify:subscribe("spotify_change", function(env)
	local info = env.INFO
	if type(info) ~= "table" then
		return
	end
	apply(info["Player State"], info["Track ID"])
end)

-- 起動時 (再読み込み含む) に既に再生中でも拾えるよう、現在の状態を一度だけ取得する
local INITIAL_STATES = { playing = "Playing", paused = "Paused" }

sbar.exec(
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & "|" & (id of current track)' 2>/dev/null]],
	function(out)
		if type(out) ~= "string" then
			return
		end
		local state, track_id = out:match("^(%a+)|(%S+)")
		if INITIAL_STATES[state] then
			apply(INITIAL_STATES[state], track_id)
		end
	end
)
