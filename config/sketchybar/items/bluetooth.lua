local colors = require("colors")
local ui = require("ui")

-- 字面は箱の外にはみ出すと見切れるので、字面の最大幅を切り上げた値にする。実測は 13.5 で、advance は 10.8 しかない。
-- 字面は箱の左端 + padding_left から描かれるので、spotify.lua と同じく、状態ごとの padding_left で
-- 字面の幅を箱の中の中央に寄せる。幅は on が 9.5、off が 12.0。
-- 実測は Hack Nerd Font Bold 18pt で、フォントやサイズを変えたら再測定する。
local ICON_WIDTH = 14

-- 接続中のデバイスがあるときは on と同じアイコンのまま、白の濃さだけで表す。接続中が白、on が少し薄い。オフはアイコンも変える。
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

-- 接続、切断、電源の切り替えで届く。何も変わらなくても数秒おきに届くことを実機で確認したので、
-- 状態が前回と同じなら何もしない。電源専用の通知 IOBluetoothHostController... は届かない。
sbar.add("event", "bluetooth_status", "com.apple.bluetooth.status")

-- 電源オフのときは device_connected 自体が無くなる。
-- 接続中のデバイスは、通知の約 0.3 秒後には system_profiler の出力に反映される。実機で確認した。
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

-- 通知は束で届くので、反映を待つ間に来た分はまとめる
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

-- bracket とクリックを受ける領域は、Wi-Fi と Bluetooth を 1 つの bracket にまとめる items/network.lua が作る。
return {
	item = bluetooth,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "Bluetooth",
}
