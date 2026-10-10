local ui = require("ui")
local wifi = require("items.wifi")
local bluetooth = require("items.bluetooth")
local volume = require("items.volume")

-- Wi-Fi is on the right, Bluetooth in the middle, and volume on the left, grouped into one bracket.

-- Glyph heights were measured with CoreText for Hack Nerd Font Bold 18pt. Wi-Fi signal 1-4 and alert are 13.9, off is 15.0,
-- and all three Bluetooth glyphs are 15.0, the maximum. Re-measure if the font or size changes.
local GLYPH_HEIGHT = 15
local MARGIN = ui.vertical_margin(GLYPH_HEIGHT)

-- The spacing between glyphs shifts by the amount of each glyph's position within its box.
local ICON_GAP = 8

-- add_bracket decides only the padding at both ends, so the item's default padding of 5 remains in between.
-- So the spacing is decided only by the left item's padding_right, and the right item's padding_left is 0.
ui.add_bracket("network.bracket", { wifi.item, bluetooth.item, volume.item }, nil, MARGIN)
wifi.item:set({ padding_left = 0 })
bluetooth.item:set({ padding_left = 0, padding_right = ICON_GAP })
volume.item:set({ padding_right = ICON_GAP })

-- These are auto-width items, so padding also counts toward the width by which placement advances.
local CHAIN = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + ICON_GAP + volume.icon_width + MARGIN
-- Distance from the right edge of the bracket.
local SPLIT_WIFI = MARGIN + wifi.icon_width + ICON_GAP / 2
local SPLIT_BLUETOOTH = MARGIN + wifi.icon_width + ICON_GAP + bluetooth.icon_width + ICON_GAP / 2

-- The padding part of an item does not respond on its own, so cover it with ui.add_hit_region.
local wifi_hit = ui.add_hit_region("network.wifi.hit", CHAIN, 0, SPLIT_WIFI)
local bluetooth_hit = ui.add_hit_region("network.bluetooth.hit", CHAIN, SPLIT_WIFI, SPLIT_BLUETOOTH)
local volume_hit = ui.add_hit_region("network.volume.hit", CHAIN, SPLIT_BLUETOOTH, CHAIN)

-- Do not use the standard menu bar panel, because clicking it would bring up the standard menu bar
for _, entry in ipairs({ { wifi_hit, wifi }, { bluetooth_hit, bluetooth } }) do
	local hit, target = entry[1], entry[2]
	hit:subscribe("mouse.clicked", function()
		ui.toggle_settings(target.settings_url, target.title_pattern)
	end)
end

-- ctrl cannot be used. When Accessibility > Zoom > "Use scroll gesture with modifier keys to zoom" is enabled,
-- macOS takes ctrl+scroll first and it never reaches sketchybar. This is because the default modifier key is ctrl.
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
