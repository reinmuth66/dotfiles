-- Commands that send AppleScript to Spotify, and reading of their output and the distributed notifications. Used by items/spotify.lua and items/spotify/artwork.lua.
-- State, track ID, title, artist, playback position, and track length are, whichever route they come from, shaped into
-- state, track_id, meta, timing to pass to apply in items/spotify.lua. meta is { title, artist } and timing is { position, duration } in seconds.

local M = {}

-- Check with pgrep first so that osascript does not launch a Spotify that is not running.
function M.command(script)
	return string.format([[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to %s' 2>/dev/null]], script)
end

-- Matches "Playing" and "Paused" of the distributed notification's Player State. Anything else, such as stopped, is nil.
local PLAYER_STATE = { playing = "Playing", paused = "Paused" }

-- Track length is in milliseconds. nil if it could not be obtained.
-- Depending on the locale, the decimal point of the position may be a comma
local function parse_timing(position, duration_ms)
	position = tonumber((position:gsub(",", ".")))
	local length = tonumber(duration_ms) / 1000
	if position and length > 0 then
		return { position = position, duration = length }
	end
	return nil
end

M.POSITION_COMMAND =
	M.command("(player state as text) & tab & (player position as text) & tab & (duration of current track as text)")

-- nil if it cannot be read.
function M.parse_position(out)
	if type(out) ~= "string" then
		return nil
	end
	local state, position, length = out:match("^(%a+)\t([%d.,]+)\t(%d+)")
	state = PLAYER_STATE[state]
	return state, state and parse_timing(position, length)
end

-- A track title and the like may contain "|", so use a tab as the delimiter.
M.SNAPSHOT_COMMAND = M.command(
	"(player state as text) & tab & (id of current track) & tab & (name of current track) & tab & (artist of current track) & tab & (player position as text) & tab & (duration of current track as text)"
)

-- nil when the state cannot be read, or when stopped and so on.
function M.parse_snapshot(out)
	if type(out) ~= "string" then
		return nil
	end
	local state, track_id, title, artist, position, duration =
		out:match("^(%a+)\t(%S+)\t([^\t]*)\t([^\t]*)\t([%d.,]+)\t(%d+)")
	state = PLAYER_STATE[state]
	if not state then
		return nil
	end
	return state, track_id, { title = title, artist = artist }, parse_timing(position, duration)
end

-- Player State is passed as is. Values other than "Playing" and "Paused" also arrive. Playback Position is fractional seconds, Duration is milliseconds. Verified on the actual device.
function M.parse_notification(info)
	local position, duration = tonumber(info["Playback Position"]), tonumber(info["Duration"])
	local timing = nil
	if position and duration and duration > 0 then
		timing = { position = position, duration = duration / 1000 }
	end
	return info["Player State"], info["Track ID"], { title = info["Name"], artist = info["Artist"] }, timing
end

return M
