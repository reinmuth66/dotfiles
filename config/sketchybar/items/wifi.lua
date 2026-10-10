local colors = require("colors")
local ui = require("ui")

-- A glyph that overflows the box is clipped, so use the glyph width rounded up.
-- Measured 17.5, while the advance is only 10.8. Every glyph has the same width and starts at the left edge.
-- The glyph is drawn from the box's left edge + padding_left, so as in spotify.lua padding_left can stay 0.
-- Measured with Hack Nerd Font Bold 18pt; re-measure if the font or size changes.
local ICON_WIDTH = 18

-- All shapes are made fan-shaped.
local LEVEL_ICONS = {
	"󰤟", -- nf-md-wifi_strength_1
	"󰤢", -- nf-md-wifi_strength_2
	"󰤥", -- nf-md-wifi_strength_3
	"󰤨", -- nf-md-wifi_strength_4
}
local DISCONNECTED = { key = "disconnected", icon = "󰤫", color = colors.dim } -- nf-md-wifi_strength_alert_outline
local OFF = { key = "off", icon = "󰤭", color = colors.dim } -- nf-md-wifi_strength_off

local SETTINGS_URL = "x-apple.systempreferences:com.apple.wifi-settings-extension"

-- Spacing is determined by the bracket's padding, so the icon's inner padding is 0 except for aligning the box.
local wifi = ui.add_item("wifi", "right", {
	update_freq = 15,
	icon = {
		font = { size = 18.0 },
		y_offset = 1,
		width = ICON_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = { drawing = false },
})

local current

-- An example description is "Wi‑Fi、接続済み、3本" (Wi-Fi, connected, 3 bars), the accessibility description of the Wi-Fi item in the standard menu bar.
-- Confirmed on the actual device that it can be obtained from the SketchyBar process in about 0.13 seconds.
-- The item's position changes, so look for one whose description contains Wi. The description depends on the display language,
-- so if the number cannot be obtained, treat the strength as unknown and use the largest icon.
local SIGNAL_SCRIPT = [[tell application "System Events" to tell process "ControlCenter"
repeat with mi in menu bar items of menu bar 1
set d to description of mi
if d contains "Wi" then return d
end repeat
end tell]]

-- Confirmed with networksetup -listallhardwareports that en0 is Wi-Fi. ipconfig prints nothing when there is no IP.
local COMMAND = [[
ip=$(ipconfig getifaddr en0)
echo "ip=$ip"
echo "power=$(networksetup -getairportpower en0)"
if [ -n "$ip" ]; then
	echo "signal=$(osascript -e ']] .. SIGNAL_SCRIPT .. [[' 2>/dev/null)"
fi
]]

-- The number of bars is 0 to 3; add 1 to map it to the icon level 1 to 4.
local function update()
	sbar.exec(COMMAND, function(out)
		if type(out) ~= "string" then
			return
		end

		local state
		if out:match("ip=%d+%.%d+%.%d+%.%d+") then
			local signal = out:match("signal=([^\n]*)") or ""
			local bars = tonumber(signal:match("(%d+)本") or signal:match("(%d+)%s*bars?"))
			local level = bars and math.max(1, math.min(bars + 1, #LEVEL_ICONS)) or #LEVEL_ICONS
			state = { key = "connected" .. level, icon = LEVEL_ICONS[level], color = colors.white }
		elseif out:match("power=[^\n]*Off") then -- the Wi-Fi Power line of the output is Off
			state = OFF
		else
			state = DISCONNECTED
		end

		if state.key == current then
			return
		end
		current = state.key

		wifi:set({ icon = { string = state.icon, color = state.color } })
	end)
end

-- wifi_change arrives twice at the same time, e.g. on reconnect. Verified on the actual device.
-- update does nothing if the state is the same as last time, so subscribe as is.
wifi:subscribe({ "wifi_change", "system_woke", "routine", "forced" }, update)
update()

-- The bracket and the click-receiving region are created by items/network.lua, which groups Wi-Fi and Bluetooth into one bracket.
return {
	item = wifi,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "Wi",
}
