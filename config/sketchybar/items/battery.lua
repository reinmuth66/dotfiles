local ui = require("ui")

-- Glyph height of the tallest icon in the contents. Measured with CoreText: 15.0 for Hack Nerd Font Bold 18pt, 9.7 for the 13pt label.
-- Re-measure if the font or size changes.
local GLYPH_HEIGHT = 15

-- The label width is always fixed via add_item's label.width to 34px, which fits "100%".
-- If the width varied with the digit count or leading character, the item to the left would shift. The string is 1px narrower when it starts with "1" or "5".
-- When the network item on the left moves, the gap to the items/spotify.lua popup also changes, so the width is fixed regardless of digit count.
-- Measured with Hack Nerd Font Bold 13pt: the label's fixed width includes the inner padding, so it is text width + padding_left of 3.
-- "45%" is 27px and "100%" is 34px. A single digit is zero-padded like "05%" and treated as two digits.
-- Re-measure if the font, size, or label padding changes.
--
-- The glyph is drawn from the label's left edge + padding_left; changing padding_left changes neither the label width of 34 nor the item width.
-- Verified on the actual device. sketchybar labels have no x_offset.
-- The three-digit "100%" fills the width, so 3. For the two-digit "45%", splitting the remaining 7px left and right puts the center at 6.5 (3.5px added on the left),
-- so choose 6 or 7 from the integers. Larger moves it right, smaller moves it left.
local LABEL_PADDING_LEFT = { [2] = 8, [3] = 3 }

-- Spacing is determined by the bracket's padding, so the inner padding of the leftmost icon and the rightmost label is 0.
local battery = ui.add_item("battery", "right", {
	update_freq = 120,
	icon = { font = { size = 18.0 }, y_offset = 1, padding_left = 0, padding_right = 3 },
	label = { padding_left = LABEL_PADDING_LEFT[2], padding_right = 0, width = 34, align = "left" },
})

ui.add_bracket("battery.bracket", { battery }, nil, ui.vertical_margin(GLYPH_HEIGHT))
ui.add_spacer("right", ui.bracket_gap)

local icons = {
	[100] = "󰁹",
	[90] = "󰂂",
	[80] = "󰂁",
	[70] = "󰂀",
	[60] = "󰁿",
	[50] = "󰁾",
	[40] = "󰁽",
	[30] = "󰁼",
	[20] = "󰁻",
	[10] = "󰁺",
	[0] = "󰂎",
}

local CHARGING_ICON = "󰂄"

local function icon_for(charge, charging)
	if charging then
		return CHARGING_ICON
	end

	local bucket = charge >= 100 and 100 or math.floor(charge / 10) * 10
	return icons[bucket]
end

-- Zero-pad only single digits so that the width does not change between 9% and 10%.
local function update()
	sbar.exec("pmset -g batt", function(batt_info)
		if batt_info == nil then
			return
		end

		local charge = tonumber(batt_info:match("(%d+)%%"))
		if charge == nil then
			return
		end

		local charging = batt_info:find("AC Power") ~= nil

		local text = string.format("%02d%%", charge)
		battery:set({
			icon = icon_for(charge, charging),
			label = { string = text, padding_left = LABEL_PADDING_LEFT[#text - 1] },
		})
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, update)
