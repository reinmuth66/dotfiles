local ui = require("ui")

-- A glyph that overflows the box is clipped, so use the maximum glyph width. Measured 15.0, while the advance is only 12.0.
-- The glyph is drawn from the box's left edge + padding_left + the glyph's left-edge offset. Same as bluetooth.lua.
-- So that the speaker position does not move when the volume changes, align the speaker's left edge with the box's left edge so that only the waves stretch and shrink to the right.
-- padding is truncated to an integer, so corrections in 0.5pt units are not possible. Verified on the actual device.
-- Regular Hack Nerd Font has a different left-edge offset per glyph. At 20pt: off and high are 0, medium is 0.38, low is 2.25.
-- So an offset of around 0.3pt remains with padding, and mute and high look shifted to the left.
-- Propo has no per-glyph position correction and every glyph's left edge is 0, so they line up without using padding.
-- Measured by drawing Hack Nerd Font Propo Bold 20pt at 32x with CoreText. Re-measure if the font or size changes.
--   glyph       ink left edge width
--   off / high  0             15.0
--   medium      0             11.3
--   low         0             7.5
--   headphones  0             15.0
local ICON_WIDTH = 15

-- Make the font size larger than the 18pt of Wi-Fi and Bluetooth. At the same 18pt the volume glyph looks smaller than the others.
-- The height of the volume-high glyph is 13.1 at 18pt, Wi-Fi is 13.9, and Bluetooth is 15.0.
local FONT_SIZE = 20.0

-- The vertical center of the glyph is the height from the baseline: 6.94 at 20pt, and 6.25 at 18pt for Wi-Fi and Bluetooth.
-- Same for every glyph, even with Propo. Others use y_offset = 1, so subtracting the difference of 0.69 gives 0.31, truncated to the integer 0.
local Y_OFFSET = 0

local HEADPHONES = { icon = "󰋋" } -- nf-md-headphones

local LEVELS = {
	{ max = 0, icon = "󰖁" }, -- nf-md-volume_off
	{ max = 33, icon = "󰕿" }, -- nf-md-volume_low
	{ max = 66, icon = "󰖀" }, -- nf-md-volume_medium
	{ max = 100, icon = "󰕾" }, -- nf-md-volume_high
}

local MUTED = LEVELS[1]

-- match is a string contained in the lowercased output destination name.
-- Hack Nerd Font has no earphone glyph, so Beats also uses the same glyph as headphones.
-- When adding other devices, check the name with SwitchAudioSource -a -t output.
local DEVICES = {
	{ match = "beats", glyph = HEADPHONES },
	{ match = "headphone", glyph = HEADPHONES },
	{ match = "headset", glyph = HEADPHONES },
	{ match = "ヘッドフォン", glyph = HEADPHONES }, -- wired headphones. They appear as the built-in output
	{ match = "ヘッドホン", glyph = HEADPHONES },
}

-- A single trackpad swipe emits many events including inertial scrolling, so
-- accumulate the scroll amount and change the volume by one volume key press at a time.
-- The volume key is synthesized and sent by media-key, so the standard volume popup appears. See pkgs/media-key.
-- One volume key press is 1/16 of the volume, about 6%. fine, while option is held, is 1/64, about 1.6%.
-- The larger SCROLL_THRESHOLD is, the duller it gets.
local SCROLL_THRESHOLD = 5
local SCROLL_IDLE = 0.3

local SETTINGS_URL = "x-apple.systempreferences:com.apple.Sound-Settings.extension"

local volume = ui.add_item("volume", "right", {
	update_freq = 5,
	icon = {
		font = { family = "Hack Nerd Font Propo", style = "Bold", size = FONT_SIZE },
		y_offset = Y_OFFSET,
		width = ICON_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = { drawing = false },
})

-- An output with no volume, such as HDMI, has the value missing value.
local COMMAND = [[
echo "device=$(SwitchAudioSource -c -t output)"
osascript -e 'set s to get volume settings' -e 'return "vol=" & (output volume of s as text) & linefeed & "muted=" & (output muted of s as text)'
]]

local current

-- An output whose volume cannot be obtained is treated as the maximum level.
local function pick(device, vol, muted)
	if muted then
		return MUTED
	end

	local name = device:lower()
	for _, d in ipairs(DEVICES) do
		if name:find(d.match, 1, true) then
			return d.glyph
		end
	end

	vol = vol or 100
	for _, level in ipairs(LEVELS) do
		if vol <= level.max then
			return level
		end
	end
	return LEVELS[#LEVELS]
end

local function update()
	sbar.exec(COMMAND, function(out)
		if type(out) ~= "string" then
			return
		end

		local device = out:match("device=([^\n]*)") or ""
		local vol = tonumber(out:match("vol=(%d+)"))
		local muted = out:match("muted=(%a+)") == "true"

		local glyph = pick(device, vol, muted)
		if glyph == current then
			return
		end
		current = glyph

		volume:set({ icon = { string = glyph.icon } })
	end)
end

-- mute does not change the volume, and it is unverified on the actual device whether volume_change arrives during mute.
-- So also pick it up with the update_freq update every few seconds.
volume:subscribe({ "volume_change", "system_woke", "routine", "forced" }, update)
update()

local function toggle_mute()
	sbar.exec("media-key mute", update)
end

-- Setting the volume unmutes even with the same value. Verified on the actual device.
-- A trackpad right click is a two-finger tap, and it is presumed that a zero-amount scroll arrives just before the click.
-- Because only mute was cleared with the volume unchanged, do not set the volume until a tick is reached.
-- Otherwise a right click during mute would be unmuted by the scroll and then muted again by the click.
local scroll = ui.scroll_accumulator(SCROLL_THRESHOLD, SCROLL_IDLE, function(sign, ticks, fine)
	sbar.exec(string.format("media-key %s %d%s", sign > 0 and "up" or "down", ticks, fine and " fine" or ""), update)
end)

-- The bracket and the click-receiving region are created by items/network.lua, which groups it together with Wi-Fi and Bluetooth into one bracket.
return {
	item = volume,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "サウンド", -- depends on the display language
	toggle_mute = toggle_mute,
	scroll = scroll,
}
