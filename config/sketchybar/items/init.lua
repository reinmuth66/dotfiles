-- require の順は item の追加順で、そのまま配置を決める。
-- position が "right" / "q" の item は追加順に右から左へ、"left" / "e" の item は左から右へ並ぶ (ui.add_bracket の説明も参照)。
-- ノッチの脇の spacer は、その側の item より先に追加する (ui.add_notch_spacer)。
-- items.wifi / items.bluetooth / items.volume は、1 つの bracket にまとめる items.network が require する。
require("items.aerospace")
require("items.clock")
require("items.battery")
require("items.zmk_battery")
require("items.ime")
require("items.network")
require("items.system")
require("items.spotify")
require("items.wallpaper")
