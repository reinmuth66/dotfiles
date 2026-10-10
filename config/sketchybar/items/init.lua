-- require の順が item の追加順で、そのまま配置を決める。
-- position が "right" と "q" の item は追加順に右から左へ、"left" と "e" の item は左から右へ並ぶ。ui.add_bracket の説明も参照。
-- ノッチの脇の spacer は、その側の item より先に追加する。ui.add_notch_spacer を使う。
-- items.wifi と items.bluetooth と items.volume は、items.network が require して 1 つの bracket にまとめる。
require("items.aerospace")
require("items.clock")
require("items.battery")
require("items.zmk_battery")
require("items.ime")
require("items.network")
require("items.system")
require("items.spotify")
require("items.wallpaper")
