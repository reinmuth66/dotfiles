-- 入力 (スクロール、右クリック、クリック) の受け方と、それに対する操作の部品。
-- ui.lua が ui.scroll_accumulator / ui.pin / ui.toggle_settings として再エクスポートするので、呼び出し側は ui を通して使う。

local async = require("ui.async")

local M = {}

-- システム設定の画面を開く。その画面がすでに前面に出ているときは、閉じる (トグル)。
-- 前面かどうかは、System Settings のウィンドウ (最前面の 1 枚) のタイトルが title_pattern を含むかで見る
-- (アクセシビリティ。実機で、タイトルが "Wi‑Fi" / "Bluetooth" で取れることを確認)。
-- タイトルは表示言語に依存するので、取れない・一致しないときは、閉じずに開く (前面へ出す) だけにする。
-- 最後のウィンドウを閉じるとシステム設定のアプリ自体が終了する (実機で確認)。
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
	-- 起動していないときの確認 (osascript) は約 1.6 秒かかるので、pgrep (約 0.02 秒) で先に見て、
	-- 起動していなければ確認せずにすぐ開く (起動中の確認は約 0.13 秒)
	local command = string.format(
		"if pgrep -qx 'System Settings' && [ \"$(osascript -e '%s' 2>/dev/null)\" = close ]; then osascript -e '%s' >/dev/null 2>&1; else open '%s'; fi",
		check,
		close,
		url
	)
	sbar.exec(command)
end

-- スクロールの量 (delta) を足し合わせ、threshold に達するごとに on_ticks(sign, ticks, ...) を呼ぶ関数を返す。
-- sign は向き (上スクロールが正の delta)、ticks は達した目盛りの数。返した関数の delta 以外の引数は、そのまま
-- on_ticks に渡る。トラックパッドは 1 回のスワイプで多数のイベントが出る (慣性スクロール含む) ので、
-- イベントごとには反応せず、目盛りに達するまでは何もしない。
-- 向きが変わったら、逆向きの分は持ち越さない。idle 秒スクロールが止まったら、足し合わせた量を捨てる
-- (次の操作に持ち越さない)。量 0 のイベントは無視する。
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

-- 右クリックでのピン留め。ピン留め中は、マウスが外れてもポップアップを閉じない (閉じる側が pin.active を見る)。
-- もう一度右クリックすると外す (toggle)。on_change(active) は、状態が変わったときに呼ぶ
-- (ピン留め中を bracket の枠線の色などで示す)。
function M.pin(on_change)
	local pin = { active = false }

	function pin.set(active)
		pin.active = active
		on_change(active)
	end

	-- 右クリックの処理。ポップアップが開いていないときは、ピン留めしない。外すのはいつでもできる
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
