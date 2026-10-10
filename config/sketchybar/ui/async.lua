-- 非同期の処理 (遅延実行、シェルの実行結果の受け取りなど) を扱う部品。
-- ui.lua が ui.latest / ui.timer として再エクスポートするので、呼び出し側は ui を通して使う。

local M = {}

-- 「最後の呼び出しだけ有効」にするための札。非同期の処理 (遅延実行、シェルの実行結果の受け取りなど) の
-- 完了時に、その間に別の呼び出しが来ていないかを確かめるのに使う。
-- begin は、前の呼び出しを無効にして新しい呼び出しを始め、その呼び出しがまだ最後かを返す関数 (valid) を返す。
-- snapshot は、前の呼び出しを無効にせず、いまの呼び出しがまだ最後かを返す関数を返す。
-- cancel は、これまでの呼び出しをすべて無効にする。
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

-- 取り消せる遅延実行。start は前の予約を取り消して新しく予約する (連続して呼ばれたときは最後の 1 回だけ実行される)。
-- cancel は予約を取り消す。pending は、予約が残っている (まだ実行も取り消しもされていない) 間 true。
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
