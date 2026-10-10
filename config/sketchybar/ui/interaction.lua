-- Components for receiving input (scroll, right click, click) and the actions taken on it.
-- ui.lua re-exports them as ui.scroll_accumulator, ui.pin and ui.toggle_settings, so callers use them through ui.

local async = require("ui.async")

local M = {}

-- Whether it is frontmost is determined by whether the title of System Settings' frontmost window contains title_pattern.
-- Obtained via accessibility. Confirmed on the actual device that the titles can be obtained as "Wi‑Fi" and "Bluetooth".
-- The title depends on the display language, so if it cannot be obtained or does not match, just open it and bring it to the front without closing.
-- Closing the last window quits the System Settings app itself. Verified on the actual device.
-- The osascript check takes about 1.6 seconds when it is not running, so look with pgrep (about 0.02 seconds) first and,
-- if it is not running, open immediately without the check. The check while running takes about 0.13 seconds.
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

-- sign is the direction, with scroll up being a positive delta. ticks is the number of ticks reached. Arguments of the returned function other than delta are passed to on_ticks as is.
-- A single trackpad swipe emits many events including inertial scrolling, so do not react per event and do nothing until a tick is reached.
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

-- While pinned, the closing side looks at pin.active and does not close the popup even when the mouse leaves.
-- on_change is called with active when the state changes.
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
