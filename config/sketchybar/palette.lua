-- アルバム画像の代表色から、Spotify のポップアップの配色を決める。
-- 入力は ImageMagick の色の頻度表を "個数,R,G,B;個数,R,G,B;..." にした文字列 (items/spotify.lua の FETCH_ARTWORK)。
-- 画像から取る色はアクセント 1 色だけで、背景と文字はその色相から作る (統一感を出すため)。
--   accent : 彩度 x 明るさ x sqrt(占有率) が最大の色。背景とのコントラストが足りなければ明るくする
--   bg     : アクセントの色相を暗くした色 (ポップアップの背景。透過させない)
--   text   : 同じ色相を薄く載せた白 (曲名、アーティスト)
-- 無彩色の画像 (アクセントが見つからない) では nil を返す。呼び出し側は default に戻す。

local colors = require("colors")

local M = {}

-- 調整用の定数
local MIN_SATURATION = 0.25 -- これより彩度が低い色は、アクセントにしない
local MIN_VALUE = 0.25 -- これより暗い色も、アクセントにしない
local BG_VALUE = 0.18 -- 背景の明るさ (HSV の V)
local BG_MAX_SATURATION = 0.5 -- 背景の彩度の上限 (派手になりすぎないように)
local BG_ALPHA = 0xff -- 背景の不透明度 (透過させない)
local BORDER_ALPHA = 0xff -- 枠線の不透明度 (アクセントの色で引く。透過させない)
local ACCENT_CONTRAST = 4.5 -- アクセントと背景のコントラスト比の下限
local TEXT_SATURATION = 0.12
local TEXT_VALUE = 0.96
local SUBTEXT_SATURATION = 0.15 -- アルバム名と時刻 (colors の既定は無彩色の 0xaaaaaa)
local SUBTEXT_VALUE = 0.70
local TRACK_SATURATION = 0.3 -- 再生位置のバーの、進んでいない部分
local TRACK_VALUE = 0.3

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

-- 戻り値は 0〜255 の整数 3 つ
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

-- WCAG の相対輝度とコントラスト比
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

-- ARGB の整数 (sketchybar の色)
local function argb(alpha, r, g, b)
	return alpha * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- "個数,R,G,B;..." を { {n, r, g, b}, ... } にする。読めない部分は捨てる。
local function parse(text)
	local list = {}
	for n, r, g, b in text:gmatch("(%d+),(%d+),(%d+),(%d+)") do
		list[#list + 1] = { tonumber(n), tonumber(r), tonumber(g), tonumber(b) }
	end
	return list
end

-- 色の頻度表から、アクセントにする色を選ぶ。なければ nil。
local function pick_accent(list)
	local total = 0
	for _, c in ipairs(list) do
		total = total + c[1]
	end
	if total == 0 then
		return nil
	end
	local best, best_score
	for _, c in ipairs(list) do
		local h, s, v = rgb_to_hsv(c[2], c[3], c[4])
		if s >= MIN_SATURATION and v >= MIN_VALUE then
			local score = s * v * math.sqrt(c[1] / total)
			if not best_score or score > best_score then
				best, best_score = { h = h, s = s, v = v }, score
			end
		end
	end
	return best
end

-- 背景とのコントラストが足りなければ、明るさを上げ、それでも足りなければ彩度を下げる (白に近づける)
local function fit_accent(accent, bg)
	local s, v = accent.s, accent.v
	while true do
		local c = { hsv_to_rgb(accent.h, s, v) }
		if contrast(c, bg) >= ACCENT_CONTRAST then
			return c
		end
		if v < 1 then
			v = math.min(1, v + 0.02)
		elseif s > 0 then
			s = math.max(0, s - 0.05)
		else
			return c
		end
	end
end

local function hex(c)
	return string.format("#%02x%02x%02x", c[1], c[2], c[3])
end

-- 画像から色が取れなかったとき (と、無彩色のとき) の配色。
-- 背景と枠線は透過させない (colors.popup の半透明の枠 0x44ffffff を、黒の上に重ねた色 0x444444 にしてある)。
M.default = {
	bg = 0xff000000,
	border = 0xff444444,
	accent = colors.white,
	text = colors.white,
	subtext = 0xffaaaaaa,
	track = 0xff444444,
	viz = "#ffffff",
}

-- histogram: "個数,R,G,B;..." の文字列 (nil や空でもよい)。配色の表を返す。無彩色なら nil。
function M.from_histogram(histogram)
	if type(histogram) ~= "string" then
		return nil
	end
	local accent = pick_accent(parse(histogram))
	if not accent then
		return nil
	end
	local bg = { hsv_to_rgb(accent.h, math.min(accent.s, BG_MAX_SATURATION), BG_VALUE) }
	local a = fit_accent(accent, bg)
	local function tint(s, v)
		return { hsv_to_rgb(accent.h, s, v) }
	end
	local text, subtext, track = tint(TEXT_SATURATION, TEXT_VALUE), tint(SUBTEXT_SATURATION, SUBTEXT_VALUE), tint(TRACK_SATURATION, TRACK_VALUE)
	return {
		bg = argb(BG_ALPHA, bg[1], bg[2], bg[3]),
		border = argb(BORDER_ALPHA, a[1], a[2], a[3]),
		accent = argb(0xff, a[1], a[2], a[3]),
		text = argb(0xff, text[1], text[2], text[3]),
		subtext = argb(0xff, subtext[1], subtext[2], subtext[3]),
		track = argb(0xff, track[1], track[2], track[3]),
		viz = hex(a),
	}
end

return M
