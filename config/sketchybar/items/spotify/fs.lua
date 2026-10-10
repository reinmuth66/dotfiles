-- ファイルの読み書き (items/spotify.lua と items/spotify/artwork.lua が使う)。

local M = {}

-- 開けなければ nil (空のファイルは "")
function M.read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

function M.has_content(path)
	local f = io.open(path, "rb")
	if not f then
		return false
	end
	local size = f:seek("end")
	f:close()
	return size ~= nil and size > 0
end

-- 同期的に書く (シェルの起動を待たない)。書けたら true
function M.write(path, text)
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	return true
end

-- 一時ファイル (path .. ".tmp") に書いてから置き換える。読む側が書きかけを読まない。置き換えられたら true
function M.write_atomic(path, text)
	local tmp = path .. ".tmp"
	return M.write(tmp, text) and os.rename(tmp, path) and true or false
end

return M
