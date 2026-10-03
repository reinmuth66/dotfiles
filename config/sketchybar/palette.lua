-- アルバム画像の代表色から、Spotify のポップアップの配色を決める。
-- 入力は ImageMagick の色の頻度表を "個数,R,G,B;個数,R,G,B;..." にした文字列 (items/spotify.lua の FETCH_ARTWORK)。
-- 画像から色を 3 つ取り、反映先を分ける (再生バーは背景から離れた色、棒グラフは背景に近い色相)。
--   base   : 有彩色のうち占有率が最大の色。その色相を暗くしたものが bg (ポップアップの背景。透過させない)、
--            薄く載せた白が text (曲名、アーティスト)、暗くしたものが track (再生バーの進んでいない部分)
--   accent : base から色相が ACCENT_MIN_HUE_GAP 以上離れた色のうち、彩度 x 明るさ x 占有率^SHARE_POWER x
--            (base からの色相の離れ具合) が最大の色 (なければ制限なしで選ぶ)。最も目立ち、背景から離れた色。
--            白系の色 (彩度が低く明るい) も候補で、色相は最も離れているものとして採点する
--            再生バーの進んだ部分の色。彩度は上限で抑え、背景とのコントラストが足りなければ明るくする
--   border : accent と同じ色相の、暗く彩度の低い色
--   viz    : base と色相が近い (背景と同系統の) 色の中で、同じスコアが最大の色 (棒グラフ)。背景より鮮やかで明るい
-- 無彩色の画像 (アクセントが見つからない) では nil を返す。呼び出し側は default に戻す。

local colors = require("colors")

local M = {}

-- 調整用の定数
local MIN_SATURATION = 0.3 -- これより彩度が低い色は、アクセントにしない
local MIN_VALUE = 0.25 -- これより暗い色も、アクセントにしない
local BASE_MIN_SATURATION = 0.15 -- 背景の色相にする色の条件 (アクセントより緩くする)
local BASE_MIN_VALUE = 0.1 -- 暗い空や夜の画像でも、その色を背景に使えるようにする
local SHARE_POWER = 0.25 -- アクセントのスコアでの占有率の効き方 (小さいほど、面積の小さい鮮やかな色が選ばれやすい)
local HUE_BONUS = 2.0 -- 背景と色相が正反対の色は、アクセントのスコアが (1 + この値) 倍になる
local ACCENT_MIN_HUE_GAP = 0.15 -- 再生バーの色は、まず背景の色相からこれ以上 (0.15 = 54 度) 離れた色から選ぶ
local WHITE_MIN_VALUE = 0.8 -- 彩度が MIN_SATURATION 未満でも、これ以上明るい色は、再生バーの候補にする (白系)
local WHITE_VIVIDNESS = 0.1 -- 白系の色を、彩度がこの値の色として採点する (大きいほど、白系が選ばれやすい)
local MIN_SHARE = 0.003 -- アクセントにする色の占有率の下限 (数 px だけの色を拾わない)
local VIZ_MAX_HUE_GAP = 0.12 -- 棒グラフの色は、背景の色相からこの範囲 (0.12 = 約 43 度) の色から選ぶ
local VIZ_FALLBACK_VALUE = 0.85 -- 範囲内に候補がないとき、背景の色相で作る棒グラフの色の明るさ
local ACCENT_MAX_SATURATION = 0.7 -- アクセント (再生バー、棒グラフ) の彩度の上限 (派手になりすぎないように)
local BG_VALUE = 0.16 -- 背景の明るさ (HSV の V)
local BG_MAX_SATURATION = 0.28 -- 背景の彩度の上限
local BG_ALPHA = 0xff -- 背景の不透明度 (透過させない)
local BORDER_ALPHA = 0xff -- 枠線の不透明度 (透過させない)
local BORDER_SATURATION = 0.22 -- 枠線 (アクセントより控えめにする)
local BORDER_VALUE = 0.42
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

-- 色相 (0〜1 の輪) の距離。0〜0.5。
local function hue_distance(a, b)
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

-- 頻度表の各色を { h, s, v, share } にする (share は占有率)。画像が空なら nil。
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
		out[#out + 1] = { h = h, s = s, v = v, share = c[1] / total }
	end
	return out
end

-- 背景の色相にする色を選ぶ: 有彩色のうち、占有率が最大のもの。なければ nil。
local function pick_base(swatches)
	local best
	for _, c in ipairs(swatches) do
		if c.s >= BASE_MIN_SATURATION and c.v >= BASE_MIN_VALUE and (not best or c.share > best.share) then
			best = c
		end
	end
	return best
end

-- アクセントにする色を選ぶ。なければ nil。
-- スコアは彩度 x 明るさ x 占有率^SHARE_POWER (白系は彩度を WHITE_VIVIDNESS とする) で、refs (すでに選んだ色) のどれからも色相が離れているほど
-- 最大 (1 + HUE_BONUS) 倍まで高くする (反映先ごとに同じ色相ばかりにならないように)。
-- min_gap を渡すと、refs のどれかと色相の距離が min_gap 未満の色は候補から外す。
local function pick_accent(swatches, refs, min_gap)
	local best, best_score
	for _, c in ipairs(swatches) do
		local white = c.s < MIN_SATURATION and c.v >= WHITE_MIN_VALUE -- 白系 (色相に意味がないので、最も離れた色として扱う)
		if (white or (c.s >= MIN_SATURATION and c.v >= MIN_VALUE)) and c.share >= MIN_SHARE then
			local gap = 0.5
			if not white then
				for _, r in ipairs(refs) do
					gap = math.min(gap, hue_distance(c.h, r.h))
				end
			end
			if not min_gap or gap >= min_gap then
				local vividness = white and WHITE_VIVIDNESS or c.s
				local score = vividness * c.v * c.share ^ SHARE_POWER * (1 + HUE_BONUS * gap / 0.5)
				if not best_score or score > best_score then
					best, best_score = c, score
				end
			end
		end
	end
	return best
end

-- 棒グラフの色を選ぶ: base と色相が近い (VIZ_MAX_HUE_GAP 以内の) 色のうち、彩度 x 明るさ x 占有率^SHARE_POWER が最大のもの。
-- 背景と同系統だが、背景より鮮やかで明るい別の色になる。候補がなければ、base の色相で明るくした色にする。
local function pick_viz(swatches, base)
	local best, best_score
	for _, c in ipairs(swatches) do
		if c.s >= MIN_SATURATION and c.v >= MIN_VALUE and hue_distance(c.h, base.h) <= VIZ_MAX_HUE_GAP then
			local score = c.s * c.v * c.share ^ SHARE_POWER
			if not best_score or score > best_score then
				best, best_score = c, score
			end
		end
	end
	return best or { h = base.h, s = math.max(base.s, MIN_SATURATION), v = VIZ_FALLBACK_VALUE }
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
	local swatches = analyze(parse(histogram))
	if not swatches then
		return nil
	end
	local base = pick_base(swatches)
	-- 再生バーの色: base から色相が離れた色 (ACCENT_MIN_HUE_GAP 以上) を優先する。なければ制限なしで選ぶ。
	local refs = base and { base } or {}
	local accent = pick_accent(swatches, refs, ACCENT_MIN_HUE_GAP) or pick_accent(swatches, refs)
	if not accent or (not base and accent.s < MIN_SATURATION) then
		return nil -- 有彩色がない (白系だけ) 画像は、default に戻す
	end
	base = base or accent
	local viz = pick_viz(swatches, base)
	local function limit(c)
		return { h = c.h, s = math.min(c.s, ACCENT_MAX_SATURATION), v = c.v }
	end
	accent, viz = limit(accent), limit(viz)
	local bg = { hsv_to_rgb(base.h, math.min(base.s, BG_MAX_SATURATION), BG_VALUE) }
	local a, vz = fit_accent(accent, bg), fit_accent(viz, bg)
	-- 背景と同じ色相で、文字と再生バーの進んでいない部分を作る
	local function tint(s, v)
		return { hsv_to_rgb(base.h, s, v) }
	end
	local border = { hsv_to_rgb(accent.h, math.min(accent.s, BORDER_SATURATION), BORDER_VALUE) }
	local text, subtext, track =
		tint(TEXT_SATURATION, TEXT_VALUE), tint(SUBTEXT_SATURATION, SUBTEXT_VALUE), tint(TRACK_SATURATION, TRACK_VALUE)
	return {
		bg = argb(BG_ALPHA, bg[1], bg[2], bg[3]),
		border = argb(BORDER_ALPHA, border[1], border[2], border[3]),
		accent = argb(0xff, a[1], a[2], a[3]),
		text = argb(0xff, text[1], text[2], text[3]),
		subtext = argb(0xff, subtext[1], subtext[2], subtext[3]),
		track = argb(0xff, track[1], track[2], track[3]),
		viz = hex(vz),
	}
end

return M
