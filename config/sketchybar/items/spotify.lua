-- Shows the Spotify album art and indicates the playback state with brightness and rotation.
--   playing             : remove the cover to brighten, and rotate the image slowly
--   paused              : darken the image and stop rotation at that angle
--   not running/stopped : show the Spotify icon instead of the image. The item itself is always shown
-- Controls: left click toggles play/pause, left double click shows the Spotify window, right click pins the popup,
-- scroll up for the previous track, scroll down for the next track.
-- Hovering shows a popup with the title, artist, and a bar graph that moves with the audio being played. It is display only and has no buttons.
-- State is received from Spotify's distributed notifications. media_change does not fire on macOS 26.
-- The playback position is advanced by the local clock, starting from the notification's Playback Position. It does not fetch with osascript every second.
-- Rotation uses background.image.rotation. It requires the SketchyBar#815 patch, which is in pkgs/sketchybar/.
-- The bar graph is drawn by cava's SDL window together with the popup's background and border. See modules/cavaviz.nix and pkgs/cavaviz/.
-- The window is laid under the popup. The window level is 100 for the window and 101 for the popup.
-- The popup's own background is made transparent while the window is shown, so that the text is drawn on top of the bar graph.
-- Mouse interaction is received by the hit of a transparent item covering the whole bracket. The image item is redrawn often,
-- and subscribing it to the mouse can cause mouse.exited to not arrive, leaving the popup unclosed. See ui.add_hit_region.

local ui = require("ui")
local colors = require("colors")
local palette = require("palette")
local paths = require("paths")
local artwork = require("items.spotify.artwork")
local fs = require("items.spotify.fs")
local script = require("items.spotify.script")
local truncate = require("items.spotify.text").truncate

local hex = palette.hex

-- The icon's font size is also the same value as SIZE. With this font the glyph is a square with side SIZE.
local SIZE = 24
local HOME = paths.home

-- Adjust the appearance after checking on the actual device.
-- VIZ_WIDTH is the width that makes the gap to the network bracket on the right 7 pt, the same as between other brackets.
-- The left edge of network is determined only by the label widths of battery and zmk_battery, both always fixed at the 3-digit width, so it is 1243 pt.
-- The right edge of the popup is start + 235, giving a difference of 7 pt.
-- The width of the items/system.lua popup is 233 pt measured, being CPU 60 + RAM 57 + Disk 115 + right border 1. That differs from it by 2 pt.
-- Make the width VIZ_WIDTH the decided value, and derive from it TEXT_WIDTH, the width of the text area, which is 222.
-- Even if POPUP_PADDING changes, the window width stays 235.
-- POPUP_HEIGHT must be even.
local POPUP_PADDING = 6
local POPUP_BORDER = colors.popup.border_width
local VIZ_WIDTH = 235
local TEXT_WIDTH = VIZ_WIDTH - 2 * POPUP_PADDING - POPUP_BORDER
local POPUP_HEIGHT = colors.bracket.height - 2 * POPUP_BORDER
local POPUP_GAP = 4

-- The popup's background starts at the left edge of the band of height POPUP_HEIGHT for the contents, and extends by the border width on the right, top, and bottom.
-- It does not extend on the left. This comes from popup_calculate_bounds in SketchyBar's popup.c.
-- The bar area is, from the window's top left, x = 6, y = 4, width = 235 - 6 - POPUP_BORDER - 6 = 222, height = POPUP_BG_HEIGHT - 2 * 4 = 26.
-- This area, colors.popup's corner radius, and the border width must match the constants in pkgs/cavaviz/popup.frag.
-- Settings such as the number of bars and sensitivity are in modules/cavaviz.nix.
local POPUP_BG_HEIGHT = POPUP_HEIGHT + 2 * POPUP_BORDER
local VIZ_LEFT = POPUP_PADDING

-- Locations of CavaViz.app and cava's config file.
local VIZ_APP = HOME .. "/Applications/Home Manager Apps/CavaViz.app"
local VIZ_CONFIG_HOME = HOME .. "/.config/cavaviz"
local VIZ_TEMPLATE = VIZ_CONFIG_HOME .. "/config.template"
local VIZ_RUNTIME_DIR = paths.cache .. "/cavaviz"
local VIZ_CONFIG = VIZ_RUNTIME_DIR .. "/config"

-- The unit of VIZ_SLOT_INTERVAL and VIZ_KILL_AGAIN is seconds. VIZ_KILL_AGAIN takes into account that open takes about 0.3 seconds.
local VIZ_SLOT_RETRIES = 20
local VIZ_SLOT_INTERVAL = 0.05
local VIZ_KILL_AGAIN = 0.6

local VIZ_CONTROL = VIZ_RUNTIME_DIR .. "/control"

-- The control file holds only the last instruction, so progress is in a separate file. See sdl-progress.patch.
local VIZ_PROGRESS = VIZ_RUNTIME_DIR .. "/progress"

-- While "off", cava has no tap and the recording indicator also disappears. See tap-gate.patch.
local VIZ_AUDIO = VIZ_RUNTIME_DIR .. "/audio"

-- Make the leading C of the pattern a character class so that it does not match the shell that runs this pkill, because the pattern is contained in the shell's command line.
local VIZ_STOP = "pkill -f '[C]avaViz.app/Contents/MacOS/cava'"

-- cava sends it with sketchybar --trigger at the start of the render loop. The ID is the launch number.
-- Passed via CAVAVIZ_READY_BIN, CAVAVIZ_READY_EVENT and CAVAVIZ_READY_ID.
-- The unit of VIZ_WAIT_TIMEOUT is seconds.
local VIZ_READY_EVENT = "cavaviz_ready"
local VIZ_WAIT_TIMEOUT = 1.5
local VIZ_HIDDEN_POS = -3000

-- The delay from the instruction to show the window until the popup's own background is made transparent must be longer than the time until the window actually appears.
-- The window actually appears after the instruction file is written and the window's opacity is applied.
-- Until then the window is hidden behind the opaque popup background. The colors are opaque, so the appearance does not change even if the window and background overlap.
local VIZ_HANDOVER_DELAY = 0.1

local function with_alpha(color, alpha)
	return alpha * 0x1000000 + color % 0x1000000
end

-- Make the bracket a circle. If the corner radius is at least half the short side, the background drawing rounds it to half the short side.
local BRACKET_PADDING = (colors.bracket.height - SIZE) / 2

-- The seconds of the playback position display also advance by one per same cycle. The second change and the rotation change at the same timing.
-- TICK advances the displayed seconds by one per cycle, so it is 1 second.
-- A negative value is the direction that decreases rotation. The visual direction is determined by this sign.
local ROTATION_PERIOD = 60
local TICK = 1
local ROTATION_STEP = -360 * TICK / ROTATION_PERIOD

-- FADE_FRAMES is 60 frames for 1 second.
local PAUSED_COLOR = colors.spotify.overlay_paused
local PLAYING_COLOR = colors.transparent
local FADE_FRAMES = 12

-- Placed at the position closest to the notch, so add it before spotify.
ui.add_notch_spacer("e", "spotify.notch_gap")

-- update_freq is used for the routine that checks whether Spotify has quit while the image is shown.
-- icon.width is the full width of the box including padding. Confirmed in SketchyBar v2.24.0's text.c.
-- The glyph is drawn from the box's left edge + padding_left, and the part that overflows the box is not drawn and is clipped.
-- With center alignment (align = center), the difference from the glyph width rounded up to 17pt is divided as an integer, so with left/right padding of 0 it shifts 1pt to the left.
-- Use left alignment and specify the position directly with padding_left, keeping the box at SIZE, so that the glyph is centered within the box.
-- The icon color is slightly dimmed so that it is clear it is not running. The glyph is the same size as the box, so no margin is needed.
-- The label is a cover for darkening the image: it overlays the label background, drawn after the image's background, at the same size as the image.
-- The side length of the image in px is decided by the cache side. It is independent of the display size.
local spotify = ui.add_item("spotify", "e", {
	width = SIZE,
	update_freq = 5,
	icon = {
		string = ":spotify:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		color = colors.dim,
		width = SIZE,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = {
		drawing = false,
		string = "",
		width = SIZE,
		padding_left = 0,
		padding_right = 0,
		background = {
			drawing = true,
			color = PAUSED_COLOR,
			height = SIZE,
			corner_radius = SIZE / 2,
		},
	},
	background = {
		drawing = true,
		color = colors.transparent,
		image = {
			drawing = false,
			scale = SIZE / artwork.ART_PX,
			corner_radius = SIZE / 2,
		},
	},
})

local bracket = ui.add_bracket("spotify.bracket", { spotify }, {
	background = { color = colors.spotify.bracket_bg, corner_radius = colors.bracket.height / 2 },
}, BRACKET_PADDING)

local hit = ui.add_hit_region("spotify.hit", SIZE, 0, SIZE + 2 * BRACKET_PADDING, { position = "e" })

-- So as not to overlap the bracket or image, the popup's owner is the anchor of an empty item placed to the right of the bracket.
-- Same construction as the items/system.lua popup, using ui.add_popup_anchor.
-- The hit's padding_right is -2 * BRACKET_PADDING, so the item after the hit starts from the image position, inside the right edge of the bracket.
-- Measured on the q side, which is mirrored left to right. Without this, the popup would intrude 6 pt into the bracket.
-- Add that amount to the spacer as well, to separate by POPUP_GAP from the bracket's right edge.
-- background is the initial value right after startup, and once the image is read, apply_palette overwrites it for each color scheme.
ui.add_spacer("e", POPUP_GAP - 1 + 2 * BRACKET_PADDING)
local anchor = ui.add_popup_anchor("spotify.anchor", "e", {
	align = "left",
	height = POPUP_HEIGHT,
	background = {
		color = palette.default.bg,
		border_color = palette.default.border,
		border_width = colors.popup.border_width,
		corner_radius = colors.popup.corner_radius,
	},
})

-- For the text area, the title and artist items are given width = 0 and stacked at the same x, offset vertically by y_offset,
-- and spotify.viz, an empty item of TEXT_WIDTH, is placed to its right to reserve the width.
local popup_font = ui.popup_font

local function add_popup_spacer(name, width)
	return sbar.add("item", name, {
		position = "popup.spotify.anchor",
		width = width,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
	})
end

add_popup_spacer("spotify.pad.left", POPUP_PADDING)

-- y_offset is the distance from the vertical center of the popup, positive upward.
local ROWS = {
	{ key = "title", size = 13.0, y_offset = 8 },
	{ key = "artist", size = 8.0, y_offset = -3 },
}

-- The shadow color is bg of the palette (the popup's background color) with this opacity applied.
-- The text has the opposite brightness to the background: bright text on a dark background, dark text on a light background.
-- So the shadow blends the text's edge with a color close to the background, creating a boundary against the bar graph.
-- If fixed to black, dark text on a light background looks thick and dirty.
-- TEXT_SHADOW_COLOR is the initial value, and apply_palette updates it for each color scheme.
local TEXT_SHADOW_ALPHA = 0xb0
local TEXT_SHADOW_COLOR = with_alpha(palette.default.bg, TEXT_SHADOW_ALPHA)

-- The text sits on top of the bar graph, so give the label a shadow to bring out the outline.
local rows = {}
for _, row in ipairs(ROWS) do
	rows[row.key] = {
		size = row.size,
		item = sbar.add("item", "spotify." .. row.key, {
			position = "popup.spotify.anchor",
			drawing = false,
			width = 0,
			y_offset = row.y_offset,
			padding_left = 0,
			padding_right = 0,
			icon = { drawing = false },
			label = {
				font = popup_font(row.size),
				padding_left = 0,
				padding_right = 0,
				shadow = { drawing = true, color = TEXT_SHADOW_COLOR, distance = 1 },
			},
		}),
	}
end

-- Reference for the visualizer window's position, obtained from sketchybar --query's bounding_rects.
-- The rect is a band spanning the full height of the popup. It does not include y_offset.
-- An item that draws nothing may not give a position, so give it a transparent background.
sbar.add("item", "spotify.viz", {
	position = "popup.spotify.anchor",
	width = TEXT_WIDTH,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = { drawing = false },
	background = { drawing = true, color = colors.transparent },
})

add_popup_spacer("spotify.pad.right", POPUP_PADDING)

local function set_popup_info(meta)
	for key, row in pairs(rows) do
		local text = meta[key]
		if type(text) ~= "string" then
			text = ""
		end
		row.item:set({ drawing = text ~= "", label = { string = truncate(text, row.size, TEXT_WIDTH) } })
	end
end

-- Notifications arrive on pause, resume, and track change, but not on seek. Verified on the actual device.
-- So a seek while the popup is closed is fixed by the fetch at the moment it opens.
-- A seek while open is not fixed until the next notification or reopening. It does not fetch with osascript every second.
-- Decouple the advance of seconds from the position estimate. If it were built to wait for the estimate to catch up with the display,
-- seconds and rotation would stop when corrections continue, for example with repeated quick hovers.
-- If shown is nil, the position is not yet known. The unit of duration and SNAP_BACK is seconds.
local shown = nil
local duration = 0
local popup_open = false

-- Show the image only after it has been obtained. If switched before fetching, only a cover without an image would be visible.
-- The image is shown while playing and paused, which is while track info exists, and the popup can be shown.
local showing_art = false

-- begin at every open_popup. A marker to avoid opening another reopened popup with the result of an old fetch.
local open_session = ui.latest()
local SNAP_BACK = 1.5

-- When the position is unknown, i.e. shown is nil or the track length is 0, write 0. Do not leave the previous track's position.
local function write_progress()
	local progress = 0
	if shown ~= nil and duration > 0 then
		progress = math.min(1, shown / duration)
	end
	fs.write(VIZ_PROGRESS, string.format("%.4f", progress))
end

-- position is fractional seconds. If new_duration is nil, keep the previous value.
-- Do not move the display back on small corrections during playback. This keeps the bar color boundary from moving back.
local function rebase(position, new_duration, playing, force)
	duration = new_duration or duration
	if shown == nil or force or not playing or not popup_open or position >= shown or position < shown - SNAP_BACK then
		shown = math.floor(position)
	end
	if popup_open then
		write_progress()
	end
end

local function step_time()
	if shown == nil or shown >= math.floor(duration) then
		return
	end
	shown = shown + 1
	if popup_open then
		write_progress()
	end
end

-- done is called after the result is applied or has failed. It may be nil.
local function refresh_position(done)
	sbar.exec(script.POSITION_COMMAND, function(out)
		local state, timing = script.parse_position(out)
		if timing then
			rebase(timing.position, timing.duration, state == "Playing", false)
		end
		if done then
			done()
		end
	end)
end

-- cava records audio only while the tap exists. While paused, VIZ_AUDIO is set to "off" to release the tap,
-- the bars fall to 0, and only the playback position is shown by the color of the minimum-height bars. When playback starts it is set to "on" and the tap is recreated. write_audio does this.
-- The permission for the Core Audio tap that captures audio is attached to CavaViz.app, so launch it with open rather than as a child process of sketchybar.
-- See pkgs/cavaviz/default.nix.
-- If the background is made transparent when no window is shown, e.g. cava cannot start for lack of permission, the popup would have no background.
-- So only when both viz.ready (ready) and viz.shown (instruction to show the window) are set is it made transparent by viz_take_background.
local viz = {
	running = false,
	id = 0,
	cache = nil,
	ready = false,
	on_ready = nil,
	fg = palette.default.viz,
	played = palette.default.played,
	bg = hex(palette.default.bg),
	border = hex(palette.default.border),
	applied = nil,
	shown = false,
	drawing_bg = false,
}

-- The transparency of the whole popup window cannot be changed, so move each item's color alpha and y_offset.
-- cava's bar graph window is outside SketchyBar and cannot be moved. It is shown to match the end of the animation. open_popup does this.
-- FADE_IN_FRAMES: 60 frames per second. The length when there is no bar graph.
-- FADE_OUT_FRAMES is made shorter than when opening so it does not feel like waiting.
-- FADE_IN_FRAMES_VIZ matches the time from hover until cava is ready, about 0.4 seconds.
-- The unit of SLIDE_DISTANCE is pt. The popup is short, so keep it within a range where the text does not overflow and get cut off by the item's window.
-- current_palette is updated by apply_palette.
local FADE_IN_FRAMES = 10
local FADE_OUT_FRAMES = 8
local FADE_IN_FRAMES_VIZ = 24
local SLIDE_DISTANCE = 4
local current_palette = palette.default

local slide_items = {}
for _, row in ipairs(ROWS) do
	slide_items[#slide_items + 1] = { rows[row.key].item, row.y_offset }
end

local function popup_background(p)
	if viz.drawing_bg then
		return { color = with_alpha(p.bg, 0), border_color = with_alpha(p.border, 0) }
	end
	return { color = p.bg, border_color = p.border }
end

local function popup_look(visible)
	local p = current_palette
	local function color(c)
		return visible and c or with_alpha(c, 0)
	end
	local dy = visible and 0 or SLIDE_DISTANCE
	anchor:set({ popup = { background = popup_background(p) } })
	rows.title.item:set({ label = { color = color(p.text) } })
	rows.artist.item:set({ label = { color = color(p.subtext) } })
	for _, entry in ipairs(slide_items) do
		entry[1]:set({ y_offset = entry[2] + dy })
	end
end

local function popup_fade_in(frames)
	sbar.animate("sin", frames, function()
		popup_look(true)
	end)
end

local function popup_fade_out()
	sbar.animate("sin", FADE_OUT_FRAMES, function()
		popup_look(false)
	end)
end

-- A marker to avoid redoing when close_popup is called repeatedly.
local fading_out = false

-- When Spotify is frontmost, make the bracket's border thick and bright to create a ring around the image. The colors are the same as the pill in items/system.lua.
-- The bracket's background stays black, so there is a black gap of BRACKET_PADDING - RING_WIDTH between the ring and the image.
-- The same border is used as the pinned border, so when both apply it takes the pinned color. Currently it is the same color as the ring. The thickness changes only for the ring.
local RING_COLOR = colors.space.bg_focused
local RING_WIDTH = 3
local ring_active = false

local function update_border(pinned)
	local color = colors.bracket.border_color
	if pinned then
		color = colors.pinned_border
	elseif ring_active then
		color = RING_COLOR
	end
	bracket:set({
		background = { border_color = color, border_width = ring_active and RING_WIDTH or colors.bracket.border_width },
	})
end

-- When the popup closes because the track info is gone, also remove it in show_icon.
local pin = ui.pin(update_border)

-- ui.timer manages it by generation, so no old loop remains even if stop -> play follows in quick succession.
-- The angle is not reset on stop; the next playback continues from the stopped angle.
local angle = 0
local spinning = false
local spin_timer = ui.timer()

local function tick()
	step_time()
	angle = (angle + ROTATION_STEP) % 360
	spotify:set({ background = { image = { rotation = angle } } })
	spin_timer.start(TICK, tick)
end

-- Do not advance at the moment of start; wait one period and then advance the first step.
-- If it advanced immediately, rapidly repeating play and stop would advance the rotation each time.
local function set_spinning(on)
	if on == spinning then
		return
	end
	spinning = on
	if on then
		spin_timer.start(TICK, tick)
	else
		spin_timer.cancel()
	end
end

-- The initial color of the cover is on the dark side, so do nothing if the initial state is dark.
local lit = false

local function set_lit(on)
	if on == lit then
		return
	end
	lit = on
	local color = on and PLAYING_COLOR or PAUSED_COLOR
	sbar.animate("sin", FADE_FRAMES, function()
		spotify:set({ label = { background = { color = color } } })
	end)
end

-- Called by open_popup and close_popup for opening and closing the popup, so define it before them.
local function viz_look()
	return viz.fg .. viz.played .. viz.bg .. viz.border
end

-- nil if the template cannot be read.
-- The window position is placed at the off-screen VIZ_HIDDEN_POS on every launch. The actual position is instructed via the control file once ready.
local function viz_render_config()
	local template = fs.read(VIZ_TEMPLATE)
	if not template then
		return nil
	end
	return (template:gsub("@(%u+)@", {
		X = VIZ_HIDDEN_POS,
		Y = VIZ_HIDDEN_POS,
		W = VIZ_WIDTH,
		H = POPUP_BG_HEIGHT,
		FG = viz.fg,
		PLAYED = viz.played,
		BG = viz.bg,
		BORDER = viz.border,
	}))
end

-- Returns nil before the popup is drawn. The result of ui.visible_rect.
local function viz_slot()
	return ui.visible_rect("spotify.viz")
end

-- The popup may be drawn at a half-point position, with center alignment and the item's position at x.5. So pass it as a fraction without rounding.
local function viz_window_pos(rect)
	local x = rect.origin[1] - VIZ_LEFT
	local y = rect.origin[2] + rect.size[2] / 2 - POPUP_BG_HEIGHT / 2
	return x, y
end

-- If it gives up after VIZ_SLOT_RETRIES attempts without obtaining it, do nothing.
local function viz_find_slot(id, found, n)
	n = n or 0
	if id ~= viz.id then
		return
	end
	local rect = viz_slot()
	if rect then
		found(viz_window_pos(rect))
	elseif n < VIZ_SLOT_RETRIES then
		sbar.delay(VIZ_SLOT_INTERVAL, function()
			viz_find_slot(id, found, n + 1)
		end)
	end
end

local VIZ_OPEN = [[
open -n -a %q --env XDG_CONFIG_HOME=%q --env CAVAVIZ_CONTROL=%q --env CAVAVIZ_PROGRESS=%q --env CAVAVIZ_AUDIO=%q --env CAVAVIZ_READY_BIN="$(command -v sketchybar)" --env CAVAVIZ_READY_EVENT=%s --env CAVAVIZ_READY_ID=%d --stderr /dev/null --args -p %q
]]

-- cava checks every 100ms and creates or releases the tap.
local function write_audio(on)
	fs.write(VIZ_AUDIO, on and "on" or "off")
end

-- If writing the output or the control file fails, do not launch.
-- "show X Y" and "hide" in the control file are used after launch to instruct showing, moving, and hiding the window.
-- write_audio writes before launch. cava reads it at startup.
local function viz_launch(id)
	viz.applied = viz_look()
	write_audio(spinning)
	local config = viz_render_config()
	if not (config and fs.write(VIZ_CONFIG, config) and fs.write(VIZ_CONTROL, "hide")) then
		return
	end
	sbar.exec(
		string.format(
			VIZ_OPEN,
			VIZ_APP,
			VIZ_CONFIG_HOME,
			VIZ_CONTROL,
			VIZ_PROGRESS,
			VIZ_AUDIO,
			VIZ_READY_EVENT,
			id,
			VIZ_CONFIG
		)
	)
end

-- cava re-reads only the gradient colors on SIGUSR2. It rebuilds neither the window nor the audio capture.
-- foreground and background are not re-read, so the colors are specified with the gradient.
-- If cava is still preparing, i.e. before ready, there is no signal receiver and it would be terminated, so
-- do it after the ready event. At that point, fix the discrepancy with viz.applied.
local VIZ_RECOLOR = "pkill -USR2 -f '[C]avaViz.app/Contents/MacOS/cava'"

local function viz_apply_color()
	if not viz.running or not viz.ready or viz.applied == viz_look() then
		return
	end
	viz.applied = viz_look()
	local config = viz_render_config()
	if config and fs.write_atomic(VIZ_CONFIG, config) then
		sbar.exec(VIZ_RECOLOR)
	end
end

local function viz_control(text)
	sbar.exec(string.format("printf %%s %q > %q", text, VIZ_CONTROL))
end

local function viz_take_background()
	if viz.drawing_bg or not (viz.running and viz.ready and viz.shown) then
		return
	end
	viz.drawing_bg = true
	anchor:set({ popup = { background = popup_background(current_palette) } })
end

local function viz_take_background_later(id)
	sbar.delay(VIZ_HANDOVER_DELAY, function()
		if id == viz.id then
			viz_take_background()
		end
	end)
end

-- If use_cache is true and the previous position is known, first show it there without waiting for the popup to be drawn.
-- The popup's position normally does not change. Re-show only if it was off after the free position was obtained.
local function viz_show_at_slot(use_cache)
	if use_cache and viz.cache then
		viz_control(string.format("show %.2f %.2f", viz.cache.x, viz.cache.y))
	end
	local id = viz.id
	viz_find_slot(id, function(x, y)
		local c = viz.cache
		if not (use_cache and c and c.x == x and c.y == y) then
			viz.cache = { x = x, y = y }
			viz_control(string.format("show %.2f %.2f", x, y))
		end
		viz.shown = true
		viz_take_background_later(id)
	end)
end

-- viz.id is advanced in the re-stop after the previous viz_stop, to avoid stopping a cava that has just launched.
local function viz_ensure_hidden()
	if viz.running then
		return
	end
	viz.running = true
	viz.ready = false
	viz.shown = false
	viz.on_ready = nil
	viz.id = viz.id + 1
	viz_launch(viz.id)
end

-- When stopping, hide the window first. With pkill alone the window remains visible for about 0.1 to 0.2 seconds until the process ends. The popup disappears first.
-- Writing to the control file is done synchronously in Lua without waiting for a shell to launch.
-- cava wakes immediately on the write and hides the window. It disappears in about 0.02 seconds.
local function viz_hide_now()
	fs.write(VIZ_CONTROL, "hide")
end

-- Restore the popup's own background first. The window is hidden right after.
-- Restoring inside the animation would make it change smoothly from transparent, so do it outside the animation.
-- Advance viz.id to cancel the processing waiting for the position.
-- open takes about 0.3 seconds to launch. Stopping right after launch, pkill misses the window that does not yet exist, and the later-launched window would remain.
-- If it has not been launched again in the meantime, stop once more.
local function viz_stop()
	viz.drawing_bg = false
	anchor:set({ popup = { background = popup_background(current_palette) } })
	viz_hide_now()
	viz.id = viz.id + 1
	local id = viz.id
	viz.running = false
	viz.ready = false
	viz.shown = false
	viz.on_ready = nil
	sbar.exec(VIZ_STOP)
	sbar.delay(VIZ_KILL_AGAIN, function()
		if id == viz.id then
			sbar.exec(VIZ_STOP)
		end
	end)
end

-- Normally it has already been launched by viz_wait at the time of hover. When launched here, e.g. when returning from stopped to playing with the popup open,
-- the order of the "hide" written to the launch instruction's control file and the "show" written to the same file for the show-window instruction is not determined,
-- and if "hide" comes later the window would not appear. So wait for ready before showing.
local function viz_start()
	if not showing_art or not popup_open then
		return
	end
	local was_running = viz.running
	viz_ensure_hidden()
	if was_running then
		viz_show_at_slot(true)
	else
		viz.on_ready = function()
			viz_show_at_slot(false)
		end
	end
end

-- Returns true if on_ready will be called later, and false if not playing or already ready.
local function viz_wait(on_ready)
	if not showing_art then
		return false
	end
	viz_ensure_hidden()
	if viz.ready then
		return false
	end
	viz.on_ready = on_ready
	return true
end

-- Ignore launch events that were cancelled by stopping or relaunching.
-- viz_apply_color after ready is for when the color changed between launch and ready.
-- viz_take_background_later is for when the show-window instruction was issued before ready.
sbar.add("event", VIZ_READY_EVENT)
spotify:subscribe(VIZ_READY_EVENT, function(env)
	if not viz.running or tostring(env.ID) ~= tostring(viz.id) then
		return
	end
	viz.ready = true
	viz_apply_color()
	if viz.shown then
		viz_take_background_later(viz.id)
	end
	local on_ready = viz.on_ready
	viz.on_ready = nil
	if on_ready then
		on_ready()
	end
end)

os.execute(string.format("mkdir -p %q", VIZ_RUNTIME_DIR))
-- Stop any window left over from before the reload
viz_stop()

-- Align the actual position without animation as soon as it can be obtained. So that the bar does not stretch from the old position while open.
-- Even if it does not become ready, e.g. cava cannot start for lack of permission, issue the show-window instruction after VIZ_WAIT_TIMEOUT seconds.
local function open_popup()
	popup_open = true
	fading_out = false
	local is_current_open = open_session.begin()
	local viz_done = true
	local animation_done = false
	local viz_shown = false

	local function show_viz()
		if viz_shown or not (viz_done and animation_done) or not popup_open or not is_current_open() then
			return
		end
		viz_shown = true
		viz_start()
	end

	viz_done = not viz_wait(function()
		viz_done = true
		show_viz()
	end)
	local frames = viz_done and FADE_IN_FRAMES or FADE_IN_FRAMES_VIZ

	write_progress()
	popup_look(false)
	anchor:set({ popup = { drawing = true } })
	popup_fade_in(frames)
	sbar.delay(frames / 60, function()
		animation_done = true
		show_viz()
	end)
	sbar.delay(VIZ_WAIT_TIMEOUT, function()
		viz_done = true
		show_viz()
	end)
	refresh_position()
end

-- To avoid leftover remnants, immediately hide the bar graph window first. The window is outside SketchyBar so it cannot fade.
-- The hide-window instruction is a synchronous write to the control file, issued before the animation.
-- Even if mouse.exited and mouse.exited.global arrive in succession, do it only once.
local function close_popup()
	if pin.active then
		return
	end
	local was_open = popup_open
	popup_open = false
	viz_stop()
	if not was_open then
		if not fading_out then
			anchor:set({ popup = { drawing = false } })
		end
		return
	end
	fading_out = true
	local is_current_open = open_session.snapshot()
	popup_fade_out()
	sbar.delay(FADE_OUT_FRAMES / 60, function()
		if is_current_open() and not popup_open then
			fading_out = false
			anchor:set({ popup = { drawing = false } })
		end
	end)
end

-- The bar, background, and border colors change immediately via SIGUSR2 if cava is running. If stopped, they take effect at the next launch.
local function apply_palette(p)
	current_palette = p
	local shadow_color = with_alpha(p.bg, TEXT_SHADOW_ALPHA)
	anchor:set({ popup = { background = popup_background(p) } })
	rows.title.item:set({ label = { color = p.text, shadow = { color = shadow_color } } })
	rows.artist.item:set({ label = { color = p.subtext, shadow = { color = shadow_color } } })
	viz.fg = p.viz
	viz.played = p.played
	viz.bg = hex(p.bg)
	viz.border = hex(p.border)
	viz_apply_color()
end

-- Whether Spotify is frontmost is known from the INFO of front_app_switched, i.e. the name of the app brought to the front.
-- While the icon is shown, i.e. not running or stopped, do not make a ring so as not to change the icon's appearance.
local SPOTIFY_APP_NAME = "Spotify"
local spotify_front = false

local function update_ring()
	ring_active = spotify_front and showing_art
	update_border(pin.active)
end

local function show_art()
	showing_art = true
	update_ring()
	spotify:set({
		icon = { drawing = false },
		label = { drawing = true },
		background = { image = { drawing = true } },
	})
end

local function show_icon()
	showing_art = false
	update_ring()
	pin.set(false)
	popup_open = false
	viz_stop()
	spotify:set({
		icon = { drawing = true },
		label = { drawing = false },
		background = { image = { drawing = false } },
	})
	anchor:set({ popup = { drawing = false } })
end

local function on_artwork(files, histogram)
	spotify:set({ background = { image = { string = files.small } } })
	apply_palette(palette.from_histogram(histogram) or palette.default)
	show_art()
end

-- meta is { title, artist } and timing is { position, duration } in seconds.
-- nil if it could not be obtained, in which case the popup's track info and playback position are left as is.
-- write_audio releases the tap on pause and recreates it when playback starts.
-- The last viz_start is for when a track starts while the popup is open.
local function apply(state, track_id, meta, timing)
	local playing = state == "Playing"
	if playing or state == "Paused" then
		local changed = track_id ~= artwork.current()
		if changed then
			artwork.load(track_id, on_artwork)
		end
		if meta then
			set_popup_info(meta)
		end
		if timing then
			rebase(timing.position, timing.duration, playing, changed)
		end
		set_spinning(playing)
		set_lit(playing)
		write_audio(playing)
		viz_start()
	else
		set_spinning(false)
		set_lit(false)
		artwork.clear()
		show_icon()
	end
end

sbar.add("event", "spotify_change", "com.spotify.client.PlaybackStateChanged")

spotify:subscribe("spotify_change", function(env)
	local info = env.INFO
	if type(info) ~= "table" then
		return
	end
	apply(script.parse_notification(info))
end)

spotify:subscribe("front_app_switched", function(env)
	spotify_front = env.INFO == SPOTIFY_APP_NAME
	update_ring()
end)

-- Spotify's quitting does not necessarily produce a notification, so periodically check whether it is running only while the image is shown.
spotify:subscribe("routine", function()
	if not showing_art then
		return
	end
	sbar.exec("pgrep -x Spotify", function(out)
		if type(out) == "string" and out:find("%d") then
			return
		end
		apply(nil)
	end)
end)

-- While pinned it stays open, so do not reopen. Reopening would restart the fade-in.
hit:subscribe("mouse.entered", function()
	if showing_art and not popup_open then
		open_popup()
	end
end)

-- Also close on mouse.exited.global when leaving the bar.
hit:subscribe({ "mouse.exited", "mouse.exited.global" }, close_popup)

-- The display follows via the distributed notifications above, so here only send commands to Spotify.
local function spotify_command(command)
	sbar.exec(script.command(command))
end

-- The window is shown with open. It comes to the front even when hidden by the -g -j auto-launch, and reopens when only the window was closed.
-- Specify it by the Home Manager Apps path, not by name with open -a Spotify. By name it may resolve to a temporary copy for updating.
local SPOTIFY_APP = HOME .. "/Applications/Home Manager Apps/Spotify.app"

-- SketchyBar has no double-click event; two clicks just arrive, so
-- wait DOUBLE_CLICK_INTERVAL seconds on the first click's play/pause. So play/pause is delayed from the click by this many seconds.
-- The macOS default double-click interval is about 0.5 seconds, but it is shortened to reduce the play/pause delay.
local DOUBLE_CLICK_INTERVAL = 0.3
-- Workspace dedicated to Spotify. The destination to which on-window-detected in modules/aerospace.nix moves Spotify.
local SPOTIFY_WORKSPACE = "F"
local DOUBLE_CLICK_COMMAND = string.format(
	'[ "$(aerospace list-workspaces --focused)" = %q ] && aerospace workspace-back-and-forth || open %q',
	SPOTIFY_WORKSPACE,
	SPOTIFY_APP
)
local click_timer = ui.timer()

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		if click_timer.pending then
			click_timer.cancel()
			sbar.exec(DOUBLE_CLICK_COMMAND)
			return
		end
		click_timer.start(DOUBLE_CLICK_INTERVAL, function()
			spotify_command("playpause")
		end)
	elseif env.BUTTON == "right" then
		pin.toggle(popup_open)
	end
end)

-- A single trackpad swipe emits many events including inertial scrolling, so
-- once it reacts, ignore for SCROLL_COOLDOWN seconds so that one swipe moves only one track.
-- The sign of SCROLL_DELTA is positive for scroll up.
local SCROLL_COOLDOWN = 1.0
local PREVIOUS_REFRESH_DELAY = 0.4 -- seconds
local scroll_cooldown = ui.timer()

-- On previous track, if mid-song, Spotify seeks back to the start of the same song. A seek does not produce a distributed notification, so
-- wait a little for Spotify to move the position back, then re-sync to the actual position. If it went back to a different track, a notification arrives.
hit:subscribe("mouse.scrolled", function(env)
	local delta = tonumber(env.SCROLL_DELTA)
	if not delta or delta == 0 or scroll_cooldown.pending then
		return
	end
	scroll_cooldown.start(SCROLL_COOLDOWN, function() end)
	local previous = delta > 0
	spotify_command(previous and "previous track" or "next track")
	if previous then
		sbar.delay(PREVIOUS_REFRESH_DELAY, function()
			refresh_position()
		end)
	end
end)

-- On startup, including reload, fetch the current state once so that playback already in progress is picked up.
sbar.exec(script.SNAPSHOT_COMMAND, function(out)
	local state, track_id, meta, timing = script.parse_snapshot(out)
	if state then
		apply(state, track_id, meta, timing)
	end
end)
