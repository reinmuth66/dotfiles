-- Spotify に AppleScript を送るコマンドと、その出力や分散通知の読み取り (items/spotify.lua と items/spotify/artwork.lua が使う)。
-- 状態、曲の ID、曲名、アーティスト、再生位置、曲の長さは、どの経路でも apply (items/spotify.lua) に渡す形
-- (state, track_id, meta, timing) にそろえる。meta は { title, artist }、timing は { position, duration } (どちらも秒)。

local M = {}

-- Spotify に AppleScript を送るコマンドを作る。
-- 未起動の Spotify を osascript が起動してしまわないよう、先に pgrep で確認する。
function M.command(script)
	return string.format([[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to %s' 2>/dev/null]], script)
end

-- osascript の player state を、分散通知の Player State ("Playing" / "Paused") に合わせる。それ以外 (停止など) は nil
local PLAYER_STATE = { playing = "Playing", paused = "Paused" }

-- osascript の位置 (秒、小数) と曲の長さ (ミリ秒) の文字列から { position, duration } (どちらも秒) を作る。取れなければ nil。
-- ロケールによっては、位置の小数点がカンマになる
local function parse_timing(position, duration_ms)
	position = tonumber((position:gsub(",", ".")))
	local length = tonumber(duration_ms) / 1000
	if position and length > 0 then
		return { position = position, duration = length }
	end
	return nil
end

-- 状態と位置と曲の長さ (ミリ秒) をタブ区切りで返す。出力は parse_position で読む。
M.POSITION_COMMAND =
	M.command("(player state as text) & tab & (player position as text) & tab & (duration of current track as text)")

-- POSITION_COMMAND の出力から、状態 ("Playing" / "Paused") と timing を返す。読めなければ nil。
function M.parse_position(out)
	if type(out) ~= "string" then
		return nil
	end
	local state, position, length = out:match("^(%a+)\t([%d.,]+)\t(%d+)")
	state = PLAYER_STATE[state]
	return state, state and parse_timing(position, length)
end

-- 状態、曲の ID、曲名、アーティスト、位置、曲の長さを、この順にタブ区切りで返す。出力は parse_snapshot で読む。
-- 曲名などに "|" が含まれうるので、区切りにはタブを使う。
M.SNAPSHOT_COMMAND = M.command(
	"(player state as text) & tab & (id of current track) & tab & (name of current track) & tab & (artist of current track) & tab & (player position as text) & tab & (duration of current track as text)"
)

-- SNAPSHOT_COMMAND の出力から、state, track_id, meta, timing を返す。状態が読めない (停止中など) ときは nil。
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

-- 分散通知 (com.spotify.client.PlaybackStateChanged) の INFO (表) から、state, track_id, meta, timing を返す。
-- Player State はそのまま ("Playing" / "Paused" 以外も来る)。Playback Position は秒 (小数)、Duration はミリ秒 (実機で確認)。
function M.parse_notification(info)
	local position, duration = tonumber(info["Playback Position"]), tonumber(info["Duration"])
	local timing = nil
	if position and duration and duration > 0 then
		timing = { position = position, duration = duration / 1000 }
	end
	return info["Player State"], info["Track ID"], { title = info["Name"], artist = info["Artist"] }, timing
end

return M
