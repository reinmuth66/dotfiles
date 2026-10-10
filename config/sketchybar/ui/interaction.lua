-- 入力、つまりスクロール、右クリック、クリックの受け方と、それに対する操作の部品。
-- ui.lua が ui.scroll_accumulator と ui.pin と ui.toggle_settings として再エクスポートするので、呼び出し側は ui を通して使う。

local async = require("ui.async")

local M = {}

-- 前面かどうかは、System Settings の最前面のウィンドウのタイトルが title_pattern を含むかで見る。
-- アクセシビリティで取る。実機で、タイトルが "Wi‑Fi" と "Bluetooth" で取れることを確認した。
-- タイトルは表示言語に依存するので、取れない、または一致しないときは、閉じずに開いて前面へ出すだけにする。
-- 最後のウィンドウを閉じるとシステム設定のアプリ自体が終了する。実機で確認した。
-- 起動していないときの osascript の確認は約 1.6 秒かかるので、約 0.02 秒の pgrep で先に見て、
-- 起動していなければ確認せずにすぐ開く。起動中の確認は約 0.13 秒。
function M.toggle_settings(url, title_pattern)
	local check = string.format(
		[[tell application "System Events"
if not (exists process "System Settings") then return "open"
tell process "System Settings"
if (count of windows) = 0 then return "open"
if frontmost and (name of window 1) contains "%s" then return "close"
return "open"
end tell
end tell]],
		title_pattern
	)
	local close = [[tell application "System Events" to tell process "System Settings" to click (value of attribute "AXCloseButton" of window 1)]]
	local command = string.format(
		"if pgrep -qx 'System Settings' && [ \"$(osascript -e '%s' 2>/dev/null)\" = close ]; then osascript -e '%s' >/dev/null 2>&1; else open '%s'; fi",
		check,
		close,
		url
	)
	sbar.exec(command)
end

-- sign は向きで、上スクロールが正の delta。ticks は達した目盛りの数。返した関数の delta 以外の引数は、そのまま on_ticks に渡る。
-- トラックパッドは 1 回のスワイプで慣性スクロールを含め多数のイベントが出るので、イベントごとには反応せず、目盛りに達するまでは何もしない。
function M.scroll_accumulator(threshold, idle, on_ticks)
	local sum = 0
	local idle_timer = async.timer()

	return function(delta, ...)
		delta = tonumber(delta)
		if not delta or delta == 0 then
			return
		end

		if sum * delta < 0 then
			sum = 0
		end
		sum = sum + delta

		idle_timer.start(idle, function()
			sum = 0
		end)

		local ticks = math.floor(math.abs(sum) / threshold)
		if ticks == 0 then
			return
		end
		local sign = sum > 0 and 1 or -1
		sum = sum - sign * ticks * threshold

		on_ticks(sign, ticks, ...)
	end
end

-- ピン留め中は、閉じる側が pin.active を見て、マウスが外れてもポップアップを閉じない。
-- on_change は、状態が変わったときに active を渡して呼ぶ。
function M.pin(on_change)
	local pin = { active = false }

	function pin.set(active)
		pin.active = active
		on_change(active)
	end

	function pin.toggle(popup_open)
		if pin.active then
			pin.set(false)
		elseif popup_open then
			pin.set(true)
		end
	end

	return pin
end

return M
