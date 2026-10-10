-- Clicking position "center" right under the notch lines up wallpaper thumbnails in a popup, and the chosen image becomes the wallpaper.
-- Confirmed on the actual device that an item can be placed under the notch and receive clicks.
-- The notch item is transparent and the same width as the notch. The popup opens downward from the bottom edge of the bar, aligned to the notch's center.
-- The wallpapers are the jpg, jpeg and png files in WALLPAPER_DIR, sorted by file name. They are kept outside the repository so that images are not put into git.
-- At most VISIBLE images are shown in the popup at once. If there are more, scrolling over the popup
-- shifts the displayed range one image at a time. On reaching the end it wraps to the other side.
-- When opening the popup, if there are more than VISIBLE images, adjust the range so the current wallpaper is at the center.
-- When the mouse is no longer over the notch or any thumbnail, wait CLOSE_DELAY and close automatically.
-- Thumbnails are made with imagemagick from extraPackages and placed in CACHE_DIR. They are not regenerated if newer than the source image.
-- The wallpaper is set via osascript with System Events. The first time, sketchybar needs permission to control System Events.
-- The same image is set for all desktops and Spaces.

local ui = require("ui")
local colors = require("colors")
local paths = require("paths")

local WALLPAPER_DIR = paths.home .. "/Pictures/wallpaper"
local CACHE_DIR = paths.cache .. "/wallpaper"

-- The display size is in pt. The cache is made in px at 2x resolution.
local THUMB_WIDTH = 128
local THUMB_HEIGHT = 72
local THUMB_SCALE = 0.5
local VISIBLE = 5

-- A single trackpad swipe emits many events, so accumulate the scroll amount. Uses ui.scroll_accumulator.
-- With scroll up delta > 0 the previous image is shown, and with scroll down delta < 0 the next image. To reverse, set SCROLL_DIRECTION to -1.
local SCROLL_THRESHOLD = 5
local SCROLL_IDLE = 0.3
local SCROLL_DIRECTION = 1

local POPUP_PADDING = 6
-- The item's top and bottom are also this height, so it receives the mouse even in the margins
local POPUP_HEIGHT = THUMB_HEIGHT + 2 * POPUP_PADDING
local POPUP_BORDER = colors.popup.border_width

local notch = ui.add_item("wallpaper", "center", {
	icon = { drawing = false },
	label = { string = "", width = ui.notch_width, padding_left = 0, padding_right = 0 },
	padding_left = 0,
	padding_right = 0,
	background = { drawing = true, color = colors.transparent, height = ui.bar_height },
	popup = {
		align = "center",
		horizontal = true,
		height = POPUP_HEIGHT,
		y_offset = 2,
		background = {
			color = colors.popup.bg,
			border_color = colors.popup.border,
			border_width = POPUP_BORDER,
			corner_radius = colors.popup.corner_radius,
		},
	},
})

-- If there are no images, output nothing and leave the popup empty.
local LIST_COMMAND = string.format(
	[[mkdir -p "%s"
for f in "%s"/*.jpg "%s"/*.jpeg "%s"/*.png; do
	[ -e "$f" ] || continue
	t="%s/$(basename "$f").jpg"
	if [ ! -e "$t" ] || [ "$f" -nt "$t" ]; then
		magick "$f[0]" -auto-orient -thumbnail %dx%d^ -gravity center -extent %dx%d "$t" || continue
	fi
	printf '%%s\t%%s\n' "$f" "$t"
done]],
	CACHE_DIR,
	WALLPAPER_DIR,
	WALLPAPER_DIR,
	WALLPAPER_DIR,
	CACHE_DIR,
	THUMB_WIDTH * 2,
	THUMB_HEIGHT * 2,
	THUMB_WIDTH * 2,
	THUMB_HEIGHT * 2
)

-- It goes into an AppleScript string, so escape " and \.
local function set_wallpaper(path)
	local escaped = path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local script = 'tell application "System Events" to tell every desktop to set picture to "' .. escaped .. '"'
	sbar.exec("osascript -e '" .. script:gsub("'", "'\\''") .. "'")
end

local popup_open = false

-- When the mouse moves from the notch to a popup thumbnail, for a moment it is not over any item. exited arrives before entered,
-- so do not close right away on exited but wait CLOSE_DELAY seconds. If it enters another item in the meantime, entered cancels the close.
local CLOSE_DELAY = 0.25
local close_timer = ui.timer()

local function close()
	close_timer.cancel()
	popup_open = false
	notch:set({ popup = { drawing = false } })
end

local function cancel_close()
	close_timer.cancel()
end

local function schedule_close()
	close_timer.start(CLOSE_DELAY, function()
		if popup_open then
			close()
		end
	end)
end

local function watch_hover(item)
	item:subscribe("mouse.entered", cancel_close)
	item:subscribe("mouse.exited", schedule_close)
end

local entries = {}
local slots = {}

-- first is the index into the list of images shown at the far left, 0-based. The i-th item shows image number first + i - 1.
local first = 0

-- Path of the last chosen image. Used as a substitute when the current wallpaper's path could not be obtained from System Events, i.e. is not in the list.
local chosen_path = nil

local function entry_at(slot_index)
	return entries[(first + slot_index - 1) % #entries + 1]
end

local function render()
	for i, slot in ipairs(slots) do
		slot:set({ background = { image = { string = entry_at(i).thumb } } })
	end
end

-- On reaching the end, return to the start. Same in the other direction.
local scroll_by_ticks = ui.scroll_accumulator(SCROLL_THRESHOLD, SCROLL_IDLE, function(sign, ticks)
	first = (first - SCROLL_DIRECTION * sign * ticks) % #entries
	render()
end)

-- When everything fits in the popup, there is no need to shift.
local function scroll(delta)
	if #entries <= VISIBLE then
		return
	end
	scroll_by_ticks(delta)
end

-- Fill the gaps between thumbnails and at both ends with transparent items, not padding. Padding does not receive mouse events,
-- but items do, so scrolling works over the margins too and counts as being over the popup.
-- Do not modify the margin items after creating them. They are not redrawn, so mouse.exited is less likely to be dropped.
local function add_pad(index)
	local pad = sbar.add("item", "wallpaper.pad." .. index, {
		position = "popup.wallpaper",
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { string = "", width = POPUP_PADDING, padding_left = 0, padding_right = 0 },
		background = { drawing = true, color = colors.transparent, height = POPUP_HEIGHT },
	})
	pad:subscribe("mouse.scrolled", function(env)
		scroll(env.INFO.delta)
	end)
	watch_hover(pad)
end

local function add_slot(index)
	local slot = sbar.add("item", "wallpaper.thumb." .. index, {
		position = "popup.wallpaper",
		width = THUMB_WIDTH,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			drawing = true,
			color = colors.transparent,
			height = THUMB_HEIGHT,
			image = { string = entry_at(index).thumb, scale = THUMB_SCALE, corner_radius = colors.popup.corner_radius },
		},
	})
	slot:subscribe("mouse.clicked", function()
		chosen_path = entry_at(index).path
		set_wallpaper(chosen_path)
		close()
	end)
	slot:subscribe("mouse.scrolled", function(env)
		scroll(env.INFO.delta)
	end)
	watch_hover(slot)
	slots[index] = slot
end

sbar.exec(LIST_COMMAND, function(output)
	for line in (output or ""):gmatch("[^\n]+") do
		local path, thumb = line:match("^(.-)\t(.+)$")
		if path then
			entries[#entries + 1] = { path = path, thumb = thumb }
		end
	end
	for i = 1, math.min(VISIBLE, #entries) do
		add_pad(i - 1)
		add_slot(i)
	end
	if #entries > 0 then
		add_pad(math.min(VISIBLE, #entries))
	end
end)

-- The current desktop of the main display
local CURRENT_COMMAND = [[osascript -e 'tell application "System Events" to get picture of current desktop']]
-- The position of the center item counted from the left, 0-based.
local CENTER = math.floor((VISIBLE - 1) / 2)

local function index_of(path)
	for i, entry in ipairs(entries) do
		if entry.path == path then
			return i
		end
	end
	return nil
end

-- The range is adjusted before opening, so the images are never seen being swapped after opening.
local function open()
	sbar.exec(CURRENT_COMMAND, function(output)
		if #entries > VISIBLE then
			local current = tostring(output or ""):match("^%s*(.-)%s*$")
			local index = index_of(current) or index_of(chosen_path)
			if index then
				first = (index - 1 - CENTER) % #entries
				render()
			end
		end
		popup_open = true
		notch:set({ popup = { drawing = true } })
	end)
end

notch:subscribe("mouse.clicked", function()
	if popup_open then
		close()
	else
		open()
	end
end)

-- Treat mouse.exited.global on leaving the bar the same as leaving the notch and popup.
watch_hover(notch)
notch:subscribe("mouse.exited.global", schedule_close)
