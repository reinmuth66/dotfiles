local ui = require("ui")
local wifi = require("items.wifi")
local bluetooth = require("items.bluetooth")
local volume = require("items.volume")

-- Wi-Fi (右)、Bluetooth (中)、音量 (左) を 1 つの bracket にまとめる。
-- 字面の高さ (px)。Hack Nerd Font Bold 18pt を CoreText で実測 (Wi-Fi の信号 1〜4 / alert は 13.9、off は 15.0、
-- Bluetooth は 3 つとも 15.0 の最大)。bracket の上下の余白と、左右の余白をそろえるのに使う。
-- フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 15
local MARGIN = ui.vertical_margin(GLYPH_HEIGHT)

-- 隣り合うアイコンの箱の間隔 (px)。字面どうしの間隔は、箱の中の字面の位置の分だけ前後する。
local ICON_GAP = 8

ui.add_bracket("network.bracket", { wifi.item, bluetooth.item, volume.item }, nil, MARGIN)
-- add_bracket が決めるのは両端の padding だけ。item の既定の padding (5) が間に残るので、
-- 間隔は、左側の item の padding_right だけで決める (右側の item の padding_left は 0 にする)
wifi.item:set({ padding_left = 0 })
bluetooth.item:set({ padding_left = 0, padding_right = ICON_GAP })
volume.item:set({ padding_right = ICON_GAP })

-- bracket の中の item が配置を進める幅の合計 (padding を含む。幅が自動の item なので padding が数えられる)
local CHAIN = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + ICON_GAP + volume.icon_width + MARGIN
-- アイコンどうしの境目 (bracket の右端からの距離)。間隔の真ん中で分ける
local SPLIT_WIFI = MARGIN + wifi.icon_width + ICON_GAP / 2
local SPLIT_BLUETOOTH = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + ICON_GAP / 2

-- クリックは、アイコンごとの領域で受ける (item の padding の部分は、item 自身では反応しない。ui.add_hit_region)。
-- bracket の右端から SPLIT_WIFI までが Wi-Fi、SPLIT_WIFI から SPLIT_BLUETOOTH までが Bluetooth、
-- そこから左端までが音量。
local wifi_hit = ui.add_hit_region("network.wifi.hit", CHAIN, 0, SPLIT_WIFI)
local bluetooth_hit = ui.add_hit_region("network.bluetooth.hit", CHAIN, SPLIT_WIFI, SPLIT_BLUETOOTH)
local volume_hit = ui.add_hit_region("network.volume.hit", CHAIN, SPLIT_BLUETOOTH, CHAIN)

-- クリックで、システム設定のそれぞれの画面を開く。すでに前面に出ているときは閉じる
-- (標準メニューバーのパネルは、押すと標準メニューバーが出てしまうため使わない)
for _, entry in ipairs({ { wifi_hit, wifi }, { bluetooth_hit, bluetooth } }) do
	local hit, target = entry[1], entry[2]
	hit:subscribe("mouse.clicked", function()
		ui.toggle_settings(target.settings_url, target.title_pattern)
	end)
end

-- 左クリックでサウンド設定、右クリックで mute の切り替え、スクロールで音量 (ctrl で細かく)
volume_hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		volume.toggle_mute()
	else
		ui.toggle_settings(volume.settings_url, volume.title_pattern)
	end
end)

volume_hit:subscribe("mouse.scrolled", function(env)
	volume.scroll(env.INFO.delta, env.INFO.modifier == "ctrl")
end)
