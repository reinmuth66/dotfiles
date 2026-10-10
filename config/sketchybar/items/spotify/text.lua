-- Truncate the popup's text, the title and artist, where it fits within the given width. Used by items/spotify.lua.
-- Width is measured with a per-character estimate in em.

-- Character widths are in em. Per-character values for ASCII, measured by CoreText at 12pt with the same system font Bold as the menu bar.
-- Full-width kana, kanji and the like are uniformly 0.923, and half-width non-ASCII characters such as accented letters and Cyrillic use the average EM_OTHER.
-- Note: this font's letter spacing varies with size. The smaller the size the wider: 11pt is about 1% and 14pt about 2% narrower than 12pt.
-- Measuring at a large value such as 100pt gives a result more than 10% narrower than the actual 11 to 14pt display. Always measure near the display size.
-- Across 38 samples of track and artist names, the difference from the measured 11, 12 and 14pt is -3.9% to +4.8%, with averages of -0.2% to +2.3%.
-- The underestimated part is absorbed by TEXT_MARGIN.
-- EM_PER_PT is the rate at which the width increases when the size is 1pt smaller.
local EM_WIDE = 0.923
local EM_OTHER = 0.6
local EM_REF_SIZE = 12
local EM_PER_PT = 0.01

-- 95 characters from the space at 0x20 to ~ at 0x7E.
-- It is a string rather than a list of numbers so that the formatter stylua does not expand it to one per line.
local EM_ASCII_TEXT = [[
0.258 0.356 0.569 0.671 0.671 1.036 0.744 0.348 0.429 0.429
0.484 0.671 0.348 0.484 0.348 0.334 0.685 0.512 0.643 0.669
0.687 0.663 0.684 0.604 0.694 0.684 0.348 0.348 0.671 0.671
0.671 0.557 0.927 0.732 0.693 0.741 0.747 0.622 0.597 0.760
0.783 0.318 0.601 0.709 0.595 0.906 0.768 0.786 0.674 0.786
0.694 0.675 0.660 0.760 0.721 1.009 0.729 0.708 0.676 0.375
0.334 0.375 0.671 0.627 0.500 0.590 0.651 0.587 0.651 0.601
0.408 0.645 0.632 0.287 0.287 0.601 0.295 0.932 0.627 0.620
0.647 0.647 0.435 0.566 0.413 0.627 0.583 0.847 0.581 0.597
0.566 0.429 0.299 0.429 0.671
]]

local EM_ASCII = {}
for value in EM_ASCII_TEXT:gmatch("%S+") do
	EM_ASCII[#EM_ASCII + 1] = tonumber(value)
end

local EM_ELLIPSIS = 3 * EM_ASCII[string.byte(".") - 31]

-- Subtract from the width by the estimation error. The unit is pt. The maximum underestimate is about 4%.
local TEXT_MARGIN = 8

local function char_em(code)
	if code >= 0x2E80 then
		return EM_WIDE
	end
	return EM_ASCII[code - 31] or EM_OTHER
end

local M = {}

-- If utf8.len is nil it is an invalid byte sequence, so use it as is.
-- The correction for the change in spacing due to the size differing from the reference EM_REF_SIZE is applied only to half-width characters. The smaller the size, the wider the width per 1em.
-- Full-width characters are uniformly EM_WIDE regardless of size. The values CoreText measured at 8pt and 12pt are the same.
function M.truncate(text, size, width)
	if utf8.len(text) == nil then
		return text
	end
	local spacing = 1 + EM_PER_PT * (EM_REF_SIZE - size)
	local limit = (width - TEXT_MARGIN) / size
	local total = 0
	local cut = 1 -- byte position
	for pos, code in utf8.codes(text) do
		if total + EM_ELLIPSIS * spacing <= limit then
			cut = pos
		end
		total = total + char_em(code) * (code >= 0x2E80 and 1 or spacing)
	end
	if total <= limit then
		return text
	end
	return (text:sub(1, cut - 1):gsub("%s+$", "")) .. "..."
end

return M
