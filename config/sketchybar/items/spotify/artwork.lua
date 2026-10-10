-- Spotify のアルバム画像の取得とキャッシュ (items/spotify.lua が使う)。
-- 画像は、osascript で引いた artwork url から取得する。使う側は、M.load で曲の画像を用意させ、
-- 準備できたら on_ready(files, histogram) を受け取る。files.small が画像のパス、histogram が色の頻度表 (palette.lua の入力)。

local script = require("items.spotify.script")

local M = {}

local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/spotify"
-- キャッシュする画像の一辺 (px)。表示サイズとは独立の固定値で、使う側が scale (表示サイズ / ART_PX) で縮める。
-- Retina (2 倍) なら、表示サイズが 48 まで足りる。変えるときは、キャッシュ (CACHE_DIR) を消すこと (古い解像度の画像が残るため)。
local ART_PX = 96
M.ART_PX = ART_PX

-- アルバム画像のキャッシュ。1 枚の画像につき、アイコン用の画像 (<ID>.jpg。一辺 ART_PX) と、
-- 色の頻度表 (<ID>.colors。"個数,R,G,B;..."。palette.lua が配色を決める) の 2 ファイルを、画像の ID (artwork url の末尾) で持つ。
-- 画像の大きさ (ART_PX) は固定なので、ファイル名には含めない (表示サイズ = 画像の実ピクセル * scale)。
-- 流れは、曲 ID -> 画像の ID と url (osascript。一度引いた曲は覚えておく) -> キャッシュの確認 (Lua) ->
-- なければ取得 (シェル)。確認を Lua で行うので、キャッシュにある画像では、取得のためのシェルを起動しない。
-- 取得は画像の ID ごとに 1 本だけ走らせる (同じアルバムの曲を続けて切り替えると、同じ画像の取得が重なる。
-- 重なった要求は、走っている取得の完了を待つ)。取得は、curl の出力を中間ファイルなしで magick に渡し、
-- 1 回のデコードで画像と頻度表を出す。出力は一時ファイルに書いて、最後に mv で置く (途中の状態が見えない)。
local COLOR_SWATCHES = 32 -- 頻度表の色数 (palette.lua の入力)
local COLOR_SAMPLE_PX = 48 -- 頻度表を数えるときの画像の一辺 (px)

local ARTWORK_URL_COMMAND = script("get artwork url of current track")

-- 画像の ID (key) と url から、2 つのファイルを作る。curl か magick が失敗したら (pipefail)、何も置かない。
local function download_command(key, url)
	return string.format(
		[[
set -o pipefail
dir=%q
key=%q
mkdir -p "$dir"
tmp="$dir/.$key.$$"
curl -sfL --max-time 10 %q \
  | magick - -units PixelsPerInch -density 72 \
      -resize %dx%d -write "jpeg:$tmp.small" \
      -resize %dx%d -colors %d -depth 8 -format %%c histogram:info:- \
  | sed -nE 's/^ *([0-9]+): *\( *([0-9]+), *([0-9]+), *([0-9]+).*/\1,\2,\3,\4/p' | paste -sd';' - > "$tmp.colors"
if [ $? -eq 0 ] && [ -s "$tmp.small" ]; then
  [ -s "$tmp.colors" ] && mv -f "$tmp.colors" "$dir/$key.colors"
  mv -f "$tmp.small" "$dir/$key.jpg"
fi
rm -f "$tmp.small" "$tmp.colors"
]],
		CACHE_DIR,
		key,
		url,
		ART_PX,
		ART_PX,
		COLOR_SAMPLE_PX,
		COLOR_SAMPLE_PX,
		COLOR_SWATCHES
	)
end

local function artwork_files(key)
	local base = CACHE_DIR .. "/" .. key
	return {
		small = base .. ".jpg",
		colors = base .. ".colors",
	}
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text ~= "" and text or nil
end

local function file_exists(path)
	local f = io.open(path, "rb")
	if not f then
		return false
	end
	local size = f:seek("end")
	f:close()
	return size ~= nil and size > 0
end

-- 2 つとも揃っていれば files と頻度表を返す (色の頻度表が欠けた古いキャッシュは、取り直して揃える)
local function cached_artwork(key)
	local files = artwork_files(key)
	local histogram = read_file(files.colors)
	if histogram and file_exists(files.small) then
		return files, (histogram:gsub("%s+$", ""))
	end
	return nil
end

-- 古い画像の掃除は、読み込み時 (再読み込み含む) に 1 回だけ行う (取得と重ならない)
sbar.exec(string.format("find %q -type f -mtime +30 -delete 2>/dev/null", CACHE_DIR))

local downloads = {} -- 画像の ID -> 取得の完了を待っている処理 (取得が走っている間だけ持つ)

-- 画像を用意して、done(files, histogram) を呼ぶ (失敗したら done(nil))。
local function ensure_artwork(key, url, done)
	local files, histogram = cached_artwork(key)
	if files then
		done(files, histogram)
		return
	end
	if downloads[key] then
		table.insert(downloads[key], done)
		return
	end
	downloads[key] = { done }
	sbar.exec(download_command(key, url), function()
		local waiting = downloads[key]
		downloads[key] = nil
		local ready, ready_histogram = cached_artwork(key)
		if not ready then
			-- 色の頻度表だけ作れなかったときも、画像は出す (配色は固定色に戻る)
			local partial = artwork_files(key)
			if file_exists(partial.small) then
				ready, ready_histogram = partial, ""
			end
		end
		for _, callback in ipairs(waiting) do
			callback(ready, ready_histogram)
		end
	end)
end

-- 曲 ID から画像の ID と url を引く。画像を出せた曲は覚えていて (load_artwork)、osascript を呼ばない。
-- 取得に失敗した曲は覚えない (誤った url を取っても、使い回さない)。
local artwork_of_track = {}

local function resolve_artwork(track_id, done)
	local known = artwork_of_track[track_id]
	if known then
		done(known)
		return
	end
	sbar.exec(ARTWORK_URL_COMMAND, function(out)
		local url = type(out) == "string" and out:match("^%s*(https?://%S+)") or nil
		local key = url and url:match("([^/]+)$")
		done(key and { key = key, url = url } or nil)
	end)
end

-- いま読み込んでいる曲の ID (M.current)。曲が変わった・停止した場合は、古い取得の結果を捨てるのに使う
local current_track = nil

-- 取得に失敗したとき (ネットワークや osascript の一時的な失敗) は、少し待って取り直す。
local ARTWORK_ATTEMPTS = 3
local ARTWORK_RETRY_DELAY = 0.5 -- 秒

local function load_artwork(track_id, on_ready, attempt)
	attempt = attempt or 1
	current_track = track_id
	local function retry()
		if attempt < ARTWORK_ATTEMPTS then
			sbar.delay(ARTWORK_RETRY_DELAY, function()
				if current_track == track_id then
					load_artwork(track_id, on_ready, attempt + 1)
				end
			end)
		else
			current_track = nil -- 次のイベントで再試行する
		end
	end
	resolve_artwork(track_id, function(artwork)
		-- 取得中に曲が変わった・停止した場合は捨てる
		if current_track ~= track_id then
			return
		end
		if not artwork then
			retry()
			return
		end
		ensure_artwork(artwork.key, artwork.url, function(files, histogram)
			if current_track ~= track_id then
				return
			end
			if not files then
				retry()
				return
			end
			artwork_of_track[track_id] = artwork
			on_ready(files, histogram)
		end)
	end)
end

-- 曲 (track_id) の画像を用意して、on_ready(files, histogram) を呼ぶ。
-- 取得中に曲が変わった (別の曲で load された)、または clear された場合は、呼ばない。
-- 色の頻度表だけ作れなかったときは、histogram は "" (配色は固定色に戻る)。
-- 取得に失敗し続けたときは、current を nil に戻す (次のイベントで再試行できる)。
function M.load(track_id, on_ready)
	load_artwork(track_id, on_ready, 1)
end

-- いま読み込んでいる (または読み込み済みの) 曲の ID。なければ nil
function M.current()
	return current_track
end

-- 曲がなくなったとき (停止、終了) に、読み込んでいる曲を忘れる。取得中の結果は捨てられる
function M.clear()
	current_track = nil
end

return M
