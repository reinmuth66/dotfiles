local colors = require("colors")
local ui = require("ui")

-- A glyph that overflows the box is clipped, so use the maximum glyph width rounded up. Measured 13.5, while the advance is only 10.8.
-- The glyph is drawn from the box's left edge + padding_left, so as in spotify.lua, a per-state padding_left
-- centers the glyph width within the box. The widths are 9.5 for on and 12.0 for off.
-- Measured with Hack Nerd Font Bold 18pt; re-measure if the font or size changes.
local ICON_WIDTH = 14

-- When a device is connected, keep the same icon as on and express it only by the intensity of white: connected is white, on is slightly dimmer. Off also changes the icon.
local STATES = {
	connected = { icon = "󰂯", color = colors.white, pad = 2 }, -- nf-md-bluetooth
	on = { icon = "󰂯", color = colors.dim, pad = 2 }, -- nf-md-bluetooth
	off = { icon = "󰂲", color = colors.dim, pad = 1 }, -- nf-md-bluetooth_off
}

local SETTINGS_URL = "x-apple.systempreferences:com.apple.BluetoothSettings"

local bluetooth = ui.add_item("bluetooth", "right", {
	update_freq = 120,
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

-- Delivered on connect, disconnect, and power toggle. It was confirmed on the actual device that it also arrives every few seconds even when nothing changes,
-- so do nothing if the state is the same as last time. The power-only notification IOBluetoothHostController... is never delivered.
sbar.add("event", "bluetooth_status", "com.apple.bluetooth.status")

-- When power is off, device_connected itself disappears.
-- A connected device shows up in the system_profiler output about 0.3 seconds after the notification. Verified on the actual device.
local COMMAND = [[system_profiler SPBluetoothDataType -json | jq -r '.SPBluetoothDataType[0] | if .controller_properties.controller_state == "attrib_on" then (if ((.device_connected // []) | length) > 0 then "connected" else "on" end) else "off" end']]

local SETTLE = 0.4

local current

local function update()
	sbar.exec(COMMAND, function(out)
		local state = type(out) == "string" and out:match("^%s*(%a+)") or nil
		if STATES[state] == nil or state == current then
			return
		end
		current = state

		local s = STATES[state]
		bluetooth:set({ icon = { string = s.icon, color = s.color, padding_left = s.pad } })
	end)
end

-- Notifications arrive in bursts, so coalesce those that arrive while waiting for the update to be reflected
local pending = false

local function on_status()
	if pending then
		return
	end
	pending = true
	sbar.delay(SETTLE, function()
		pending = false
		update()
	end)
end

bluetooth:subscribe("bluetooth_status", on_status)
bluetooth:subscribe({ "system_woke", "routine", "forced" }, update)
update()

-- The bracket and the click-receiving region are created by items/network.lua, which groups Wi-Fi and Bluetooth into one bracket.
return {
	item = bluetooth,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "Bluetooth",
}
