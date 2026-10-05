local colors = require("colors")
local ui = require("ui")

-- 字面の高さ (px)。Hack Nerd Font Bold 18pt を CoreText で実測 (3 つとも 15.0)。
-- bracket の上下の余白と、左右の余白をそろえるのに使う。フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 15
local MARGIN = ui.vertical_margin(GLYPH_HEIGHT)

-- アイコンの箱の幅 (padding を含む全幅)。字面は箱の外にはみ出すと見切れるので、字面の最大幅
-- (実測 13.5。advance は 10.8 しかない) を切り上げた値にする。
-- 字面は箱の左端 + padding_left から描かれるので (spotify.lua と同じ)、状態ごとの padding_left で
-- 字面の幅 (on 9.5 / connected 13.5 / off 12.0) を箱の中の中央に寄せる。
-- 実測値 (Hack Nerd Font Bold 18pt): フォントやサイズを変えたら再測定が必要。
local ICON_WIDTH = 14

-- 接続中デバイスがあるときは白、電源が入っているだけのときは少し薄く、オフはさらに薄い色
local STATES = {
	connected = { icon = "󰂱", color = colors.white, pad = 0 }, -- nf-md-bluetooth_connect
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

ui.add_bracket("bluetooth.bracket", { bluetooth }, nil, MARGIN)

-- bracket 全体でクリックを受ける (item の padding の部分は、item 自身では反応しない。ui.add_hit_layer)
local hit = ui.add_hit_layer_over("bluetooth.hit", ICON_WIDTH + 2 * MARGIN, ICON_WIDTH + 2 * MARGIN)
ui.add_spacer("right", ui.bracket_gap)

-- 接続・切断・電源の切り替えで届く。何も変わらなくても数秒おきに届く (実機で確認) ので、
-- 状態が前回と同じなら何もしない。電源専用の通知 (IOBluetoothHostController...) は届かない。
sbar.add("event", "bluetooth_status", "com.apple.bluetooth.status")

-- 電源オフのときは device_connected 自体が無くなる。接続中のデバイスは、通知の約 0.3 秒後には
-- system_profiler の出力に反映されている (実機で確認)。
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

-- クリックで、システム設定の Bluetooth の画面を開く。すでに前面に出ているときは閉じる
-- (標準メニューバーのパネルは、押すと標準メニューバーが出てしまうため使わない)
hit:subscribe("mouse.clicked", function()
	ui.toggle_settings(SETTINGS_URL, "Bluetooth")
end)
