-- Spotify の再生中だけアルバム画像を回す。
-- 状態は Spotify の分散通知 (media_change は macOS 26 で発火しない) から受け取り、
-- 画像は osascript の artwork url を取得して使う。
-- 回転は background.image.rotation を使う (SketchyBar#815 のパッチが前提、pkgs/sketchybar/)。

local ui = require("ui")

local SIZE = 28 -- 表示サイズ (pt)
local PERIOD = 10 -- 1周にかかる秒数
local FPS = 15
local DIRECTION = -1 -- 1: rotation が増える方向, -1: 減る方向

local ART_PX = SIZE * 4
local STEP = DIRECTION * 360 / (PERIOD * FPS)
local DELAY = 1 / FPS
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/spotify"

local spotify = ui.add_item("spotify", "right", {
	drawing = false,
	width = SIZE,
	icon = { drawing = false },
	label = { drawing = false },
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

-- 回転ループ。stop -> start が短時間で続いても古いループが残らないよう世代で管理する
local angle = 0
local spinning = false
local generation = 0

local function tick(id)
	if not spinning or id ~= generation then
		return
	end
	angle = (angle + STEP) % 360
	spotify:set({ background = { image = { rotation = angle } } })
	sbar.delay(DELAY, function()
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
		tick(generation)
	else
		-- 停止時は通常の角度に戻し、次の再生は 0 から回り始める
		angle = 0
		spotify:set({ background = { image = { rotation = 0 } } })
	end
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
	if state == "Playing" or state == "Paused" then
		if track_id ~= current_track then
			load_artwork(track_id)
		end
		set_spinning(state == "Playing")
	else
		set_spinning(false)
		current_track = nil
		spotify:set({ drawing = false })
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
sbar.exec(
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & "|" & (id of current track)' 2>/dev/null]],
	function(out)
		if type(out) ~= "string" then
			return
		end
		local state, track_id = out:match("^(%a+)|(%S+)")
		if state == "playing" then
			apply("Playing", track_id)
		elseif state == "paused" then
			apply("Paused", track_id)
		end
	end
)
