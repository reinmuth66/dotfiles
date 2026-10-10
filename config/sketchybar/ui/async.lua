-- 非同期の処理、つまり遅延実行やシェルの実行結果の受け取りなどを扱う部品。
-- ui.lua が ui.latest と ui.timer として再エクスポートするので、呼び出し側は ui を通して使う。

local M = {}

-- 最後の呼び出しだけ有効にするための札。非同期の処理の完了時に、その間に別の呼び出しが来ていないかを確かめるのに使う。
-- snapshot は、begin と違い、前の呼び出しを無効にしない。
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

-- start は前の予約を取り消す。連続して呼ばれたときは最後の 1 回だけ実行される。
-- pending は、まだ実行も取り消しもされていない間 true。
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
