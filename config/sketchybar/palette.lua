-- Decides the Spotify popup's colors from the album art's representative colors.
-- The input is ImageMagick's color frequency table as a string "count,R,G,B;count,R,G,B;...", made by download_command in items/spotify/artwork.lua.
-- The background hue is the chromatic hues weighted and averaged on the circle, so as not to be dragged by just the single largest color.
-- The background brightness is decided by whether the image's brightness L* is closer to the dark or the light background. No threshold is set; it is judged by equal distance from both sides.
-- The bar graph's accent hue does not take whitish colors as candidates. It would be the same family as the text color, making the text over the bars unreadable.
-- The played and unplayed bars share a hue so they look like one bar. They need not be the same family as the background.
-- The title and artist overlap the bars, so the played bar is kept as far from the background as possible while the text stays readable. bar_luminances decides this.
-- The unplayed bar is placed between the background and the played one. Both are opaque, and the bar opacity on the items side is 1.
-- Returns nil when no accent is found, as with an achromatic image. The caller falls back to default.

local colors = require("colors")

local M = {}

-- Constants for tuning.
-- Lower bounds of saturation and brightness for color candidates. The two BASE_ ones are for background hue candidates and are looser than the accent.
-- BASE_MIN_VALUE is the value that lets even dark sky or night images use that color as the background.
local MIN_SATURATION = 0.3
local MIN_VALUE = 0.25
local BASE_MIN_SATURATION = 0.15
local BASE_MIN_VALUE = 0.1

-- The bar graph's color score uses the same method as Android's Palette API Target. Share is the ratio to the most frequent color, a value from 0 to 1. The target is 1.
-- Unlike Palette's default VIBRANT, the weights emphasize saturation so as not to lean toward pale colors.
-- Share is also weighted heavily so colors that affect the image's look are chosen. Picking a small accent color would look unnatural.
-- ACCENT_TARGET_LIGHTNESS is the value that avoids whitish and blackish colors. The actual brightness is decided by bar_luminances.
-- ACCENT_MIN_HUE_GAP of 0.15 is 54 degrees. MIN_SHARE is the lower bound so that small accent colors are not picked up.
-- ACCENT_MAX_SATURATION is the upper bound so that it does not become too flashy.
-- HUE_MIN_CONCENTRATION: complementary colors cancel out and the average becomes undefined, so below this use the hue of the largest color.
local ACCENT_WEIGHT_SATURATION = 0.4
local ACCENT_WEIGHT_LIGHTNESS = 0.2
local ACCENT_WEIGHT_POPULATION = 0.4
local ACCENT_TARGET_SATURATION = 1.0
local ACCENT_TARGET_LIGHTNESS = 0.5
local ACCENT_MIN_HUE_GAP = 0.15
local MIN_SHARE = 0.02
local ACCENT_MAX_SATURATION = 0.7
local ACCENT_FALLBACK_SATURATION = 0.5
local HUE_MIN_CONCENTRATION = 0.3

-- The background and border are not made transparent. BORDER_SATURATION is more subdued than the accent.
local BG_ALPHA = 0xff
local BORDER_ALPHA = 0xff
local BORDER_SATURATION = 0.22

local TEXT_CONTRAST = 7
local SUBTEXT_CONTRAST = 4.5

-- The text overlaps the bars, so make the bars as bright as possible within the range where the text does not get buried.
-- PLAYED_MIN_SATURATION is the value that makes the difference from the unplayed bar appear in vividness as well as brightness.
-- BAR_MIN_STEP is the value that keeps the text condition from collapsing the difference between the background and the played bar.
local PLAYED_TEXT_CONTRAST = 4.5
local PLAYED_SUBTEXT_CONTRAST = 3
local UNPLAYED_STEP = 0.35
local PLAYED_MIN_SATURATION = 0.45
local UNPLAYED_SATURATION_SCALE = 0.6
local BAR_MIN_STEP = 1.5

-- A background of intermediate brightness would not show the accent color, so push it toward either dark or light.
local THEMES = {
	dark = {
		bg_saturation = { scale = 0.6, min = 0.05, max = 0.35 },
		bg_luminance = { scale = 0.25, min = 0.012, max = 0.06 },
		text = { s = 0.12, v = 0.96 },
		subtext = { s = 0.15, v = 0.70 }, -- the default of colors is the achromatic 0xaaaaaa
		border_value = 0.42,
	},
	light = {
		bg_saturation = { scale = 0.5, min = 0.04, max = 0.25 },
		bg_luminance = { scale = 1, min = 0.6, max = 0.85 },
		text = { s = 0.3, v = 0.1 },
		subtext = { s = 0.25, v = 0.3 },
		border_value = 0.62,
	},
}

local function rgb_to_hsv(r, g, b)
	r, g, b = r / 255, g / 255, b / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h / 6
	end
	return h, max == 0 and 0 or d / max, max
end

-- The return value is three integers from 0 to 255
local function hsv_to_rgb(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b
	i = i % 6
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

-- WCAG relative luminance and contrast ratio
local function luminance(r, g, b)
	local function f(c)
		c = c / 255
		return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
end

local function contrast(a, b)
	local la, lb = luminance(a[1], a[2], a[3]), luminance(b[1], b[2], b[3])
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

local function argb(alpha, r, g, b)
	return alpha * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- Discard the unreadable parts.
local function parse(text)
	local list = {}
	for n, r, g, b in text:gmatch("(%d+),(%d+),(%d+),(%d+)") do
		list[#list + 1] = { tonumber(n), tonumber(r), tonumber(g), tonumber(b) }
	end
	return list
end

-- Distance of hues on a 0 to 1 wheel. 0 to 0.5.
local function hue_distance(a, b)
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

-- HSL lightness and saturation obtained from 0 to 255 RGB.
local function rgb_to_hsl(r, g, b)
	r, g, b = r / 255, g / 255, b / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local l = (max + min) / 2
	local d = max - min
	return l, d == 0 and 0 or d / (1 - math.abs(2 * l - 1))
end

-- share is the occupancy. nil if the image is empty.
local function analyze(list)
	local total = 0
	for _, c in ipairs(list) do
		total = total + c[1]
	end
	if total == 0 then
		return nil
	end
	local out = {}
	for _, c in ipairs(list) do
		local h, s, v = rgb_to_hsv(c[2], c[3], c[4])
		local l, hsl_s = rgb_to_hsl(c[2], c[3], c[4])
		out[#out + 1] = { r = c[2], g = c[3], b = c[4], h = h, s = s, v = v, l = l, hsl_s = hsl_s, share = c[1] / total }
	end
	return out
end

local function clamp(x, min, max)
	return math.max(min, math.min(max, x))
end

-- Returns { s = saturation, lum = relative luminance }.
local function average(swatches)
	local r, g, b = 0, 0, 0
	for _, c in ipairs(swatches) do
		r, g, b = r + c.r * c.share, g + c.g * c.share, b + c.b * c.share
	end
	local _, s = rgb_to_hsv(r, g, b)
	return { s = s, lum = luminance(r, g, b) }
end

-- nil if there is no chromatic color.
local function pick_hue(swatches)
	local x, y, total = 0, 0, 0
	local largest
	for _, c in ipairs(swatches) do
		if c.s >= BASE_MIN_SATURATION and c.v >= BASE_MIN_VALUE then
			local w = c.s * c.v * c.share
			x, y, total = x + w * math.cos(c.h * 2 * math.pi), y + w * math.sin(c.h * 2 * math.pi), total + w
			if not largest or c.share > largest.share then
				largest = c
			end
		end
	end
	if not largest then
		return nil
	end
	if math.sqrt(x * x + y * y) / total < HUE_MIN_CONCENTRATION then
		return largest.h
	end
	return ((math.atan2 or math.atan)(y, x) / (2 * math.pi)) % 1
end

local function max_share(swatches)
	local max = 0
	for _, c in ipairs(swatches) do
		max = math.max(max, c.share)
	end
	return max
end

local function score(c, top_share)
	return ACCENT_WEIGHT_SATURATION * (1 - math.abs(c.hsl_s - ACCENT_TARGET_SATURATION))
		+ ACCENT_WEIGHT_LIGHTNESS * (1 - math.abs(c.l - ACCENT_TARGET_LIGHTNESS))
		+ ACCENT_WEIGHT_POPULATION * c.share / top_share
end

-- nil if none. If min_gap is passed, colors whose hue distance to any of the already chosen colors passed in refs is less than min_gap are excluded from the candidates.
local function pick_accent(swatches, refs, min_gap)
	local top_share = max_share(swatches)
	local best, best_score
	for _, c in ipairs(swatches) do
		if c.s >= MIN_SATURATION and c.v >= MIN_VALUE and c.share >= MIN_SHARE then
			local gap = 0.5
			for _, r in ipairs(refs) do
				gap = math.min(gap, hue_distance(c.h, r.h))
			end
			if not min_gap or gap >= min_gap then
				local sc = score(c, top_share)
				if not best_score or sc > best_score then
					best, best_score = c, sc
				end
			end
		end
	end
	return best
end

-- Perceived brightness by CIE L*. 0 to 100.
local function lightness(lum)
	return lum > 0.008856 and 116 * lum ^ (1 / 3) - 16 or 903.3 * lum
end

-- If it is not reached even with V of HSV brightness at its maximum, lower the saturation toward white until it is reached.
local function at_luminance(h, s, target)
	while true do
		local lo, hi = 0, 1
		for _ = 1, 16 do
			local mid = (lo + hi) / 2
			if luminance(hsv_to_rgb(h, s, mid)) < target then
				lo = mid
			else
				hi = mid
			end
		end
		local c = { hsv_to_rgb(h, s, hi) }
		if s <= 0 or luminance(c[1], c[2], c[3]) >= target * 0.95 then
			return c
		end
		s = math.max(0, s - 0.05)
	end
end

local function fit_contrast(color, bg, ratio, light)
	local s, v = color.s, color.v
	while true do
		local c = { hsv_to_rgb(color.h, s, v) }
		if contrast(c, bg) >= ratio then
			return c
		end
		if light then
			if v <= 0 then
				return c
			end
			v = math.max(0, v - 0.02)
		elseif v < 1 then
			v = math.min(1, v + 0.02)
		elseif s > 0 then
			s = math.max(0, s - 0.05)
		else
			return c
		end
	end
end

-- Discard alpha. Used for cava's config colors. Also used by items/spotify.lua.
local function hex(color)
	return string.format("#%06x", color % 0x1000000)
end
M.hex = hex

-- Returns the relative luminance of unplayed and played. UNPLAYED_STEP is the position from the background, seen on the logarithm of the contrast ratio between the background and the played one.
local function bar_luminances(bg, text, subtext, light)
	local lb, lt, ls = luminance(bg[1], bg[2], bg[3]) + 0.05, luminance(text[1], text[2], text[3]) + 0.05, luminance(subtext[1], subtext[2], subtext[3]) + 0.05
	local lp
	if light then
		lp = math.min(math.max(PLAYED_TEXT_CONTRAST * lt, PLAYED_SUBTEXT_CONTRAST * ls), lb / BAR_MIN_STEP)
	else
		lp = math.max(math.min(lt / PLAYED_TEXT_CONTRAST, ls / PLAYED_SUBTEXT_CONTRAST), lb * BAR_MIN_STEP)
	end
	local lu = lb * (lp / lb) ^ UNPLAYED_STEP
	return lu - 0.05, lp - 0.05
end

-- The background and border are not made transparent. colors.popup is the semi-transparent border 0x44ffffff composited over black, giving 0x444444.
M.default = {
	bg = colors.popup.bg,
	border = colors.popup.border,
	text = colors.white,
	subtext = 0xffaaaaaa,
	viz = "#2e2e2e",
	played = "#5c5c5c",
}

-- histogram may be nil or empty. Returns nil for an achromatic image.
function M.from_histogram(histogram)
	if type(histogram) ~= "string" then
		return nil
	end
	local swatches = analyze(parse(histogram))
	if not swatches then
		return nil
	end
	local avg = average(swatches)
	local function theme_luminance(t)
		return clamp(avg.lum * t.bg_luminance.scale, t.bg_luminance.min, t.bg_luminance.max)
	end
	local target = lightness(avg.lum)
	local light = math.abs(lightness(theme_luminance(THEMES.light)) - target)
		< math.abs(lightness(theme_luminance(THEMES.dark)) - target)
	local theme = light and THEMES.light or THEMES.dark
	local hue = pick_hue(swatches)
	local refs = hue and { { h = hue } } or {}
	local accent = pick_accent(swatches, refs, ACCENT_MIN_HUE_GAP) or pick_accent(swatches, refs, nil)
	if not accent and not hue then
		return nil
	end
	hue = hue or accent.h
	accent = accent or { h = hue, s = ACCENT_FALLBACK_SATURATION, v = 1 }
	local function limit(c)
		return { h = c.h, s = math.min(c.s, ACCENT_MAX_SATURATION), v = c.v }
	end
	accent = limit(accent)
	local bg_s = clamp(avg.s * theme.bg_saturation.scale, theme.bg_saturation.min, theme.bg_saturation.max)
	local bg_lum = theme_luminance(theme)
	local bg = at_luminance(hue, bg_s, bg_lum)
	local function tint(spec, ratio)
		return fit_contrast({ h = hue, s = spec.s, v = spec.v }, bg, ratio, light)
	end
	local border = { hsv_to_rgb(accent.h, math.min(accent.s, BORDER_SATURATION), theme.border_value) }
	local text, subtext = tint(theme.text, TEXT_CONTRAST), tint(theme.subtext, SUBTEXT_CONTRAST)
	local unplayed_lum, played_lum = bar_luminances(bg, text, subtext, light)
	local played_s = clamp(accent.s, PLAYED_MIN_SATURATION, ACCENT_MAX_SATURATION)
	local unplayed = at_luminance(accent.h, played_s * UNPLAYED_SATURATION_SCALE, unplayed_lum)
	local played = at_luminance(accent.h, played_s, played_lum)
	return {
		bg = argb(BG_ALPHA, bg[1], bg[2], bg[3]),
		border = argb(BORDER_ALPHA, border[1], border[2], border[3]),
		text = argb(0xff, text[1], text[2], text[3]),
		subtext = argb(0xff, subtext[1], subtext[2], subtext[3]),
		viz = hex(argb(0xff, unplayed[1], unplayed[2], unplayed[3])),
		played = hex(argb(0xff, played[1], played[2], played[3])),
	}
end

return M
