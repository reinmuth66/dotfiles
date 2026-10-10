local colors = require("colors")
local ui = require("ui")

-- 字面は箱の外にはみ出すと見切れるので、字面の幅
-- (実測 17.5。advance は 10.8 しかない。どのグリフも同じ幅で、左端から始まる) を切り上げた値にする。
-- 字面は箱の左端 + padding_left から描かれる (spotify.lua と同じ) ので、padding_left は 0 のままでよい。
-- 実測値 (Hack Nerd Font Bold 18pt): フォントやサイズを変えたら再測定が必要。
local ICON_WIDTH = 18

-- 形はすべて扇形にそろえてある。
local LEVEL_ICONS = {
	"󰤟", -- nf-md-wifi_strength_1
	"󰤢", -- nf-md-wifi_strength_2
	"󰤥", -- nf-md-wifi_strength_3
	"󰤨", -- nf-md-wifi_strength_4
}
local DISCONNECTED = { key = "disconnected", icon = "󰤫", color = colors.dim } -- nf-md-wifi_strength_alert_outline
local OFF = { key = "off", icon = "󰤭", color = colors.dim } -- nf-md-wifi_strength_off

local SETTINGS_URL = "x-apple.systempreferences:com.apple.wifi-settings-extension"

local wifi = ui.add_item("wifi", "right", {
	update_freq = 15,
	-- 余白は bracket の padding で決めるため、アイコンの内側の padding は箱の位置合わせ以外は 0 にする
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

-- 説明文の例: "Wi‑Fi、接続済み、3本" (標準メニューバーの Wi-Fi 項目。アクセシビリティ)。
-- SketchyBar のプロセスから取れる (実機で確認。約 0.13 秒)。
-- 項目の位置は変わるので、説明文に "Wi" を含むものを探す。説明文は表示言語に依存するので、
-- 数字を取れなければ、強さ不明として最大のアイコンにする。
local SIGNAL_SCRIPT = [[tell application "System Events" to tell process "ControlCenter"
repeat with mi in menu bar items of menu bar 1
set d to description of mi
if d contains "Wi" then return d
end repeat
end tell]]

-- en0 が Wi-Fi (networksetup -listallhardwareports で確認)。ipconfig は IP が無いと何も出力しない。
local COMMAND = [[
ip=$(ipconfig getifaddr en0)
echo "ip=$ip"
echo "power=$(networksetup -getairportpower en0)"
if [ -n "$ip" ]; then
	echo "signal=$(osascript -e ']] .. SIGNAL_SCRIPT .. [[' 2>/dev/null)"
fi
]]

local function update()
	sbar.exec(COMMAND, function(out)
		if type(out) ~= "string" then
			return
		end

		local state
		if out:match("ip=%d+%.%d+%.%d+%.%d+") then
			-- 線の数は 0〜3 で、アイコンの段階 (1〜4) に 1 を足して対応させる
			local signal = out:match("signal=([^\n]*)") or ""
			local bars = tonumber(signal:match("(%d+)本") or signal:match("(%d+)%s*bars?"))
			local level = bars and math.max(1, math.min(bars + 1, #LEVEL_ICONS)) or #LEVEL_ICONS
			state = { key = "connected" .. level, icon = LEVEL_ICONS[level], color = colors.white }
		elseif out:match("power=[^\n]*Off") then -- "Wi-Fi Power (en0): Off"
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

-- wifi_change は、接続し直したときなどに同じ時刻に 2 回届く (実機で確認)。
-- update は状態が前回と同じなら何もしないので、そのまま購読する。
wifi:subscribe({ "wifi_change", "system_woke", "routine", "forced" }, update)
update()

-- bracket と、クリックを受ける領域は、items/network.lua が作る (Wi-Fi と Bluetooth を 1 つの bracket にまとめる)
return {
	item = wifi,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "Wi",
}
