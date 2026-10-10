-- Spotify に AppleScript を送るコマンドと、その出力や分散通知の読み取り。items/spotify.lua と items/spotify/artwork.lua が使う。
-- 状態、曲の ID、曲名、アーティスト、再生位置、曲の長さは、どの経路でも items/spotify.lua の apply に渡す
-- state, track_id, meta, timing の形にそろえる。meta は { title, artist }、timing は { position, duration } で、どちらも秒。

local M = {}

-- 未起動の Spotify を osascript が起動してしまわないよう、先に pgrep で確認する。
function M.command(script)
	return string.format([[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to %s' 2>/dev/null]], script)
end

-- 分散通知の Player State の "Playing" と "Paused" に合わせる。それ以外は停止などで nil。
local PLAYER_STATE = { playing = "Playing", paused = "Paused" }

-- 曲の長さはミリ秒。取れなければ nil。
-- ロケールによっては、位置の小数点がカンマになる
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

-- 読めなければ nil。
function M.parse_position(out)
	if type(out) ~= "string" then
		return nil
	end
	local state, position, length = out:match("^(%a+)\t([%d.,]+)\t(%d+)")
	state = PLAYER_STATE[state]
	return state, state and parse_timing(position, length)
end

-- 曲名などに "|" が含まれうるので、区切りにはタブを使う。
M.SNAPSHOT_COMMAND = M.command(
	"(player state as text) & tab & (id of current track) & tab & (name of current track) & tab & (artist of current track) & tab & (player position as text) & tab & (duration of current track as text)"
)

-- 状態が読めないとき、停止中などは nil。
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

-- Player State はそのまま渡す。"Playing" と "Paused" 以外も来る。Playback Position は秒の小数、Duration はミリ秒。実機で確認した。
function M.parse_notification(info)
	local position, duration = tonumber(info["Playback Position"]), tonumber(info["Duration"])
	local timing = nil
	if position and duration and duration > 0 then
		timing = { position = position, duration = duration / 1000 }
	end
	return info["Player State"], info["Track ID"], { title = info["Name"], artist = info["Artist"] }, timing
end

return M
