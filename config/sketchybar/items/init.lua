-- The order of require is the order items are added, which directly determines placement.
-- Items with position "right" and "q" are laid out right to left in the order added; items with "left" and "e" are laid out left to right. See also the ui.add_bracket documentation.
-- A spacer beside the notch must be added before the items on that side. Use ui.add_notch_spacer.
-- items.wifi, items.bluetooth and items.volume are required by items.network and grouped into one bracket.
require("items.aerospace")
require("items.clock")
require("items.battery")
require("items.zmk_battery")
require("items.ime")
require("items.network")
require("items.system")
require("items.spotify")
require("items.wallpaper")
