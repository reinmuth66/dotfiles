local ui = require("ui")
local wifi = require("items.wifi")
local bluetooth = require("items.bluetooth")

-- Wi-Fi (右) と Bluetooth (左) を 1 つの bracket にまとめる。
-- 字面の高さ (px)。Hack Nerd Font Bold 18pt を CoreText で実測 (Wi-Fi の信号 1〜4 / alert は 13.9、off は 15.0、
-- Bluetooth は 3 つとも 15.0 の最大)。bracket の上下の余白と、左右の余白をそろえるのに使う。
-- フォントやサイズを変えたら再測定が必要。
local GLYPH_HEIGHT = 15
local MARGIN = ui.vertical_margin(GLYPH_HEIGHT)

-- 2 つのアイコンの箱の間隔 (px)。字面どうしの間隔は、箱の中の字面の位置の分だけ前後する。
local ICON_GAP = 8

ui.add_bracket("network.bracket", { wifi.item, bluetooth.item }, nil, MARGIN)
-- add_bracket が決めるのは両端の padding だけ。item の既定の padding (5) が間に残るので、
-- 間隔は Bluetooth 側の padding_right だけで決める
wifi.item:set({ padding_left = 0 })
bluetooth.item:set({ padding_right = ICON_GAP })

-- bracket の中の item が配置を進める幅の合計 (padding を含む。幅が自動の item なので padding が数えられる)
local CHAIN = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + MARGIN
-- 2 つのアイコンの境目 (bracket の右端からの距離)。間隔の真ん中で分ける
local SPLIT = MARGIN + wifi.icon_width + ICON_GAP / 2

-- クリックは、アイコンごとの領域で受ける (item の padding の部分は、item 自身では反応しない。ui.add_hit_region)。
-- bracket の右端から SPLIT までが Wi-Fi、SPLIT から左端までが Bluetooth。
local wifi_hit = ui.add_hit_region("network.wifi.hit", CHAIN, 0, SPLIT)
local bluetooth_hit = ui.add_hit_region("network.bluetooth.hit", CHAIN, SPLIT, CHAIN)

-- クリックで、システム設定のそれぞれの画面を開く。すでに前面に出ているときは閉じる
-- (標準メニューバーのパネルは、押すと標準メニューバーが出てしまうため使わない)
wifi_hit:subscribe("mouse.clicked", function()
	ui.toggle_settings(wifi.settings_url, wifi.title_pattern)
end)

bluetooth_hit:subscribe("mouse.clicked", function()
	ui.toggle_settings(bluetooth.settings_url, bluetooth.title_pattern)
end)
