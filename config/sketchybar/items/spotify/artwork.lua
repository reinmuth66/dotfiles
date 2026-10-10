-- Fetching and caching of Spotify album art. Used by items/spotify.lua.
-- The image is fetched from the artwork url obtained via osascript. The caller has M.load prepare the track's image,
-- and receives files and histogram via on_ready once it is ready.
-- files.small is the image path, and histogram is the color frequency table that is the input to palette.lua.

local paths = require("paths")
local fs = require("items.spotify.fs")
local script = require("items.spotify.script")

local M = {}

local CACHE_DIR = paths.cache .. "/spotify"
-- A fixed value independent of the display size; the caller shrinks it with scale = display size / ART_PX.
-- At 2x Retina this is enough for display sizes up to 48. When changing it, delete the cache in CACHE_DIR, because images at the old resolution remain.
local ART_PX = 96
M.ART_PX = ART_PX

-- Per image, keep two files named by the image ID: <ID>.jpg for the icon image and <ID>.colors for the color frequency table. The ID is the end of the artwork url.
-- The image size ART_PX is fixed, so it is not included in the file name. The display size is the image's actual pixels * scale.
-- Cache existence is checked in Lua, so no shell is launched for fetching an image that is in the cache.
-- Run only one fetch per image ID. Switching between tracks of the same album in a row would overlap fetches of the same image,
-- so overlapping requests wait for the running fetch to finish.
-- The fetch passes curl's output to magick without an intermediate file, and produces the image and frequency table in one decode.
-- Output is written to a temporary file and finally placed with mv, so intermediate states are never visible.

local COLOR_SWATCHES = 32
local COLOR_SAMPLE_PX = 48

local ARTWORK_URL_COMMAND = script.command("get artwork url of current track")

-- If curl or magick fails, pipefail ensures nothing is placed.
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

-- An old cache missing the color frequency table is refetched to complete it
local function cached_artwork(key)
	local files = artwork_files(key)
	local histogram = fs.read(files.colors)
	if histogram ~= nil and histogram ~= "" and fs.has_content(files.small) then
		return files, (histogram:gsub("%s+$", ""))
	end
	return nil
end

-- Cleanup of old images is done only once at load time, including reload. It does not overlap with fetching.
sbar.exec(string.format("find %q -type f -mtime +30 -delete 2>/dev/null", CACHE_DIR))

local downloads = {}

-- On failure, pass nil to done.
-- Even if only the color frequency table could not be made, the image is still output. The colors fall back to the fixed colors.
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
			local partial = artwork_files(key)
			if fs.has_content(partial.small) then
				ready, ready_histogram = partial, ""
			end
		end
		for _, callback in ipairs(waiting) do
			callback(ready, ready_histogram)
		end
	end)
end

-- Remember only tracks whose image could be output. Do not remember tracks whose fetch failed. Even if a wrong url was obtained, do not reuse it.
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

-- Used to discard the result of an old fetch when the track changed or stopped
local current_track = nil

-- When a fetch fails, i.e. a temporary network or osascript failure, wait a moment and retry.
local ARTWORK_ATTEMPTS = 3
local ARTWORK_RETRY_DELAY = 0.5 -- seconds

-- If it keeps failing even after retrying, return current_track to nil. Retry at the next event.
-- If the track changed or stopped during the fetch, discard the result.
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
			current_track = nil
		end
	end
	resolve_artwork(track_id, function(artwork)
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

-- Not called if the track changed during the fetch and another track was loaded, or if it was cleared.
-- If only the color frequency table could not be made, histogram is an empty string and the colors fall back to the fixed colors.
-- If the fetch keeps failing, current is returned to nil. It can be retried at the next event.
function M.load(track_id, on_ready)
	load_artwork(track_id, on_ready, 1)
end

function M.current()
	return current_track
end

-- The result of an in-progress fetch is discarded
function M.clear()
	current_track = nil
end

return M
