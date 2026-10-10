-- File reading and writing. Used by items/spotify.lua and items/spotify/artwork.lua.

local M = {}

-- nil if it cannot be opened. An empty file is an empty string.
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

-- Write synchronously. Does not wait for a shell to launch. Returns true if written.
function M.write(path, text)
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	return true
end

-- Write to a temporary file path .. ".tmp" and then replace. The reader never reads a half-written file. Returns true if replaced.
function M.write_atomic(path, text)
	local tmp = path .. ".tmp"
	return M.write(tmp, text) and os.rename(tmp, path) and true or false
end

return M
