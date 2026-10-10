-- Spotify に AppleScript を送るコマンドを作る (items/spotify.lua と items/spotify/artwork.lua が使う)。
-- 未起動の Spotify を osascript が起動してしまわないよう、先に pgrep で確認する。
return function(script)
	return string.format([[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to %s' 2>/dev/null]], script)
end
