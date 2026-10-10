-- Thin helpers for adding items / brackets / spacers.
-- They unify how position and padding are written and reduce boilerplate in each item's definition.

local colors = require("colors")

local M = {}

-- A bracket's extent includes the padding of the items inside it,
-- so with nothing between, adjacent brackets' backgrounds would touch.
M.bracket_gap = 6

-- For edge items, set the inner padding of the icon and label to 0.
M.bracket_padding = 8

-- Passing this as add_bracket's padding makes the top/bottom and left/right margins equal.
-- For content_height, use the height of the visible glyph, not the line height.
function M.vertical_margin(content_height)
	return math.floor((colors.bracket.height - content_height) / 2 + 0.5)
end

local function merge(base, extra)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- position must be specified as one of "left", "right", "center", "q", "e". q is left of the notch, e is right of the notch.
-- SketchyBar's default is left, but make the caller state its intent explicitly.
function M.add_item(name, position, props)
	return sbar.add("item", name, merge(props or {}, { position = position }))
end

-- To use it only to measure the extent without drawing a background, pass { background = { drawing = false } }.
--
-- Verified on the actual device that a bracket's extent includes item padding, so padding is set as the edge item's padding.
-- members must be passed as item objects, in right-to-left order.
-- Items cannot be identified by name or regex, so specifying padding is an error.
-- It cannot be used for items like zmk_battery whose drawing position and order differ, as it stacks two rows vertically.
function M.add_bracket(name, members, props, padding)
	props = props or {}

	local names = {}
	for i, member in ipairs(members) do
		names[i] = type(member) == "table" and member.name or member
	end

	if padding ~= nil then
		if type(padding) == "number" then
			padding = { left = padding, right = padding }
		end
		local first, last = members[1], members[#members]
		assert(type(first) == "table" and type(last) == "table", "add_bracket: padding requires item objects as members")
		if padding.right ~= nil then
			first:set({ padding_right = padding.right })
		end
		if padding.left ~= nil then
			last:set({ padding_left = padding.left })
		end
	end

	return sbar.add(
		"bracket",
		name,
		names,
		merge(props, { background = merge(colors.bracket, props.background) })
	)
end

-- Measured on the actual device that an empty label has a width of 1px.
-- Even if the spacer's padding_right is set to width, the visual gap is width + 1.
local SPACER_RENDERED_WIDTH = 1

local spacer_count = 0

-- Verified on the actual device that for an item with width specified, a negative padding_right does not propagate to the neighbor.
-- So that the gap can later be closed with a negative padding_right, keep the width automatic, give it an empty label, and express width with padding_right.
function M.add_spacer(position, width, name)
	if name == nil then
		spacer_count = spacer_count + 1
		name = "spacer." .. spacer_count
	end
	return M.add_item(name, position, {
		padding_left = 0,
		padding_right = width,
		icon = { drawing = false },
		label = { string = "", padding_left = 0, padding_right = 0 },
	})
end

-- Used for bar.lua's notch_width and items/wallpaper.lua.
-- Measured as NSScreen's frame width - auxiliaryTopLeftArea width - auxiliaryTopRightArea width: 1710 - 751 - 750.
M.notch_width = 209

-- Used for bar.lua's height. The distance to the notch is also decided from here.
M.bar_height = 40

-- The distance between the notch and the bracket is the same as the bracket's top/bottom margin. The margin is (bar height - bracket height) / 2.
local NOTCH_GAP = (M.bar_height - colors.bracket.height) / 2

-- The offset, in pt, from the measured notch edge of the position where SketchyBar computes the origin for positions "q" and "e".
-- Positive outside the notch, negative inside. The notch is 0.5 pt right of the screen center, which does not match SketchyBar's symmetric assumption.
-- bar.c computes the left origin as (screen width - notch_width) / 2 truncated. Rounded to integers, it shifts in opposite directions left and right.
-- Measured in bar.lua: with notch_width 209, the left origin is 750 pt and the measured left edge is 751 pt, and the right origin is 959 pt and the measured right edge is 960 pt.
local NOTCH_ORIGIN_OFFSET = { q = 1, e = -1 }

-- Placed at the position closest to the notch, so add it before the items on that side.
-- The visual gap is width + SPACER_RENDERED_WIDTH + origin offset, so subtract the offset above from the width to even out the distance from the measured notch edge.
-- The result is NOTCH_GAP - 2 for "q" and NOTCH_GAP for "e".
function M.add_notch_spacer(position, name)
	local offset = NOTCH_ORIGIN_OFFSET[position]
	assert(offset ~= nil, 'add_notch_spacer: position must be "q" or "e"')
	return M.add_spacer(position, NOTCH_GAP - SPACER_RENDERED_WIDTH - offset, name)
end

-- Mouse events go to the window under the cursor. SketchyBar re-establishes an item's mouse tracking area
-- every time an item that subscribes to mouse events is redrawn.
-- At that point mouse.exited may stop arriving, and a popup opened by hover no longer closes. Reproduced on the actual device.
-- If this item subscribes instead of the redrawn items, this item is not redrawn, so it does not happen.
-- The bracket's background, i.e. the padding part of items, is not included in an item's window, but this item covers up to the padding, so the whole bracket responds.
--
-- Position is matched by making its own padding negative. Verified on the actual device against SketchyBar's placement quirks.
--   - After an item with width specified, placement advances only by width. Padding is not counted.
--   - Specifying its own width prevents negative padding from propagating to the neighbor and leaves a gap.
-- So this item does not use width but reserves its width with icon.width, and does not change the neighbor item's position with padding.
-- padding_left + padding_right + width = 0, which hit_region_geometry computes.
--
-- When items inside a bracket are separate and each range should receive a different action, create one per range. See items/network.lua.
-- Add after the item to overlay and after the bracket. Later-added items' windows are on top.
-- When the item to overlay is at "q", left of the notch, pass props.position = "q". Placement goes right to left, the same as right, and the edge is the right edge.
-- When it is at "e", right of the notch, pass props.position = "e". Placement goes left to right, the same as left, and the edge is the left edge.
-- Subscription is done by the caller. Do not change the background and so on after creating it. Redrawing would bring back the problem above.
-- "e" is laid out left to right, so the directions for stepping back and advancing are opposite. So swap left and right padding.
function M.add_hit_region(name, chain_width, from, to, props)
	local layer = M.hit_region_geometry(chain_width, from, to)
	layer.label = { drawing = false }
	layer.background = { drawing = true, color = colors.transparent }
	local position = props and props.position or "right"
	if position == "e" then
		layer.padding_left, layer.padding_right = layer.padding_right, layer.padding_left
	end
	return M.add_item(name, position, merge(layer, props))
end

-- The hit padding and width that cover the range from from to to px from the bracket's right edge without changing the neighbor items' positions.
-- For the whole bracket, from = 0 and to = the bracket's width.
-- chain_width is the total width by which the items in the bracket advance placement from right to left.
-- An item with width specified advances subsequent placement only by width. Padding is not counted.
-- So sum the widths of the items with width specified. Items with automatic width are not included. Verified on the actual device.
-- padding_left + padding_right + width = 0. When the width changes, set this value again.
function M.hit_region_geometry(chain_width, from, to)
	return {
		padding_left = chain_width - to,
		padding_right = -(chain_width - from),
		icon = { string = "", width = to - from, padding_left = 0, padding_right = 0 },
	}
end

-- The popup's owner is an empty item, the anchor, placed at a position that does not overlap icons or neighbor items.
-- If opts.align is "left", it aligns with the owner's left edge and extends right; if "right", it aligns with the right edge and extends left. It covers other items in the direction it extends.
-- By default the popup appears below the bottom edge of the bar. Make y_offset negative to bring it back up and place it at the vertical center of the bar.
-- The top edge is (bar height - opts.height) / 2.
-- The contents shift down by the popup's border opts.background.border_width, so raise by that amount too.
-- Measured on the actual device: the top edge of the contents was 5 pt with a border of 1 and 4 pt with a border of 0.
-- opts.height is the height of the contents, and opts.background is the popup's background, including border_width.
function M.add_popup_anchor(name, position, opts)
	return M.add_item(name, position, {
		width = 1,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
		popup = {
			align = opts.align,
			horizontal = true,
			height = opts.height,
			y_offset = -(M.bar_height + opts.height) / 2 - opts.background.border_width,
			background = opts.background,
		},
	})
end

-- Make the popup text the same system font as the menu bar.
-- Specifying ".AppleSystemUIFont" as the family gives SF for Latin text and automatically switches Japanese to the same
-- ".Hiragino Kaku Gothic Interface" W4 as the menu bar. Confirmed with CoreText.
-- Names such as "SF Pro" resolve to Helvetica if SF Pro is not installed.
-- With the Bold style, Latin becomes System Font Bold and Japanese becomes W6. Regular gives W4.
local POPUP_FONT_FAMILY = ".AppleSystemUIFont"
local POPUP_FONT_STYLE = "Bold"

function M.popup_font(size, features)
	return { family = POPUP_FONT_FAMILY, style = POPUP_FONT_STYLE, size = size, features = features }
end

-- A hidden item has origin -9999, -9999, so return nil if it is off-screen.
function M.visible_rect(name)
	local rects = sbar.query(name).bounding_rects
	for _, rect in pairs(rects or {}) do
		if rect.origin[1] >= 0 then
			return rect
		end
	end
	return nil
end

-- Adjust the padding_right of the spacer placed between so that the visual gap is the same as
-- spacing + SPACER_RENDERED_WIDTH when a normal spacer is placed between them.
-- It updates by the difference from the measured value, so it converges no matter how many times it is called.
-- Applying layout is asynchronous, so the caller should call it a little after the change.
function M.close_gap(opts)
	local spacer = opts.spacer
	local spacing = opts.spacing
	local left = M.visible_rect(opts.left)
	local right = M.visible_rect(opts.right)

	if left == nil or right == nil then
		spacer:set({ padding_right = spacing })
		return
	end

	local gap = right.origin[1] - (left.origin[1] + left.size[1])
	local current = sbar.query(spacer.name).geometry.padding_right
	spacer:set({ padding_right = current - (gap - (spacing + SPACER_RENDERED_WIDTH)) })
end

-- Asynchronous components are split into ui/async.lua, and input-related components into ui/interaction.lua.
-- Callers can still use them as ui.latest and so on, as before.
local async = require("ui.async")
local interaction = require("ui.interaction")

M.latest = async.latest
M.timer = async.timer
M.scroll_accumulator = interaction.scroll_accumulator
M.pin = interaction.pin
M.toggle_settings = interaction.toggle_settings

return M
