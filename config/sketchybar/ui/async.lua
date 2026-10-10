-- Components for asynchronous processing, i.e. deferred execution and receiving shell command results.
-- ui.lua re-exports them as ui.latest and ui.timer, so callers use them through ui.

local M = {}

-- A token that makes only the last call effective. On completion of asynchronous work, it is used to check whether another call came in the meantime.
-- Unlike begin, snapshot does not invalidate previous calls.
function M.latest()
	local generation = 0
	local latest = {}

	function latest.begin()
		generation = generation + 1
		return latest.snapshot()
	end

	function latest.snapshot()
		local id = generation
		return function()
			return id == generation
		end
	end

	function latest.cancel()
		generation = generation + 1
	end

	return latest
end

-- start cancels the previous reservation. When called repeatedly, only the last one runs.
-- pending is true while it has been neither executed nor cancelled.
function M.timer()
	local latest = M.latest()
	local timer = { pending = false }

	function timer.start(delay, fn)
		local valid = latest.begin()
		timer.pending = true
		sbar.delay(delay, function()
			if not valid() then
				return
			end
			timer.pending = false
			fn()
		end)
	end

	function timer.cancel()
		latest.cancel()
		timer.pending = false
	end

	return timer
end

return M
