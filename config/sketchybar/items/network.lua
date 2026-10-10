local ui = require("ui")
local wifi = require("items.wifi")
local bluetooth = require("items.bluetooth")
local volume = require("items.volume")

-- Wi-Fi が右、Bluetooth が中、音量が左で、1 つの bracket にまとめる。

-- 字面の高さは Hack Nerd Font Bold 18pt を CoreText で実測した。Wi-Fi の信号 1〜4 と alert は 13.9、off は 15.0、
-- Bluetooth は 3 つとも 15.0 で最大。フォントやサイズを変えたら再測定する。
local GLYPH_HEIGHT = 15
local MARGIN = ui.vertical_margin(GLYPH_HEIGHT)

-- 字面どうしの間隔は、箱の中の字面の位置の分だけ前後する。
local ICON_GAP = 8

-- add_bracket が決めるのは両端の padding だけで、item の既定の padding 5 が間に残る。
-- そのため間隔は左側の item の padding_right だけで決め、右側の item の padding_left は 0 にする。
ui.add_bracket("network.bracket", { wifi.item, bluetooth.item, volume.item }, nil, MARGIN)
wifi.item:set({ padding_left = 0 })
bluetooth.item:set({ padding_left = 0, padding_right = ICON_GAP })
volume.item:set({ padding_right = ICON_GAP })

-- 幅が自動の item なので、padding も配置を進める幅に数えられる。
local CHAIN = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + ICON_GAP + volume.icon_width + MARGIN
-- bracket の右端からの距離。
local SPLIT_WIFI = MARGIN + wifi.icon_width + ICON_GAP / 2
local SPLIT_BLUETOOTH = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + ICON_GAP / 2

-- item の padding の部分は item 自身では反応しないので、ui.add_hit_region で覆う。
local wifi_hit = ui.add_hit_region("network.wifi.hit", CHAIN, 0, SPLIT_WIFI)
local bluetooth_hit = ui.add_hit_region("network.bluetooth.hit", CHAIN, SPLIT_WIFI, SPLIT_BLUETOOTH)
local volume_hit = ui.add_hit_region("network.volume.hit", CHAIN, SPLIT_BLUETOOTH, CHAIN)

-- 標準メニューバーのパネルは、押すと標準メニューバーが出てしまうため使わない
for _, entry in ipairs({ { wifi_hit, wifi }, { bluetooth_hit, bluetooth } }) do
	local hit, target = entry[1], entry[2]
	hit:subscribe("mouse.clicked", function()
		ui.toggle_settings(target.settings_url, target.title_pattern)
	end)
end

-- ctrl は使えない。アクセシビリティ > ズームの "スクロールジェスチャと修飾キーで拡大" が有効だと、
-- ctrl+スクロールは macOS が先に奪い、sketchybar に届かない。既定の修飾キーが ctrl のため。
volume_hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		volume.toggle_mute()
	else
		ui.toggle_settings(volume.settings_url, volume.title_pattern)
	end
end)

volume_hit:subscribe("mouse.scrolled", function(env)
	volume.scroll(env.INFO.delta, env.INFO.modifier == "alt")
end)
