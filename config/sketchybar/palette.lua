-- アルバム画像の代表色から、Spotify のポップアップの配色を決める。
-- 入力は ImageMagick の色の頻度表を "個数,R,G,B;個数,R,G,B;..." にした文字列 (items/spotify.lua の FETCH_ARTWORK)。
-- 画像から次の 3 つを取り、反映先を分ける (再生バーは背景から離れた色、棒グラフは背景に近い色相)。
--   hue    : 背景の色相。有彩色の色相を、彩度 x 明るさ x 占有率で重み付けして円周上で平均する (最大の 1 色だけに引きずられない)。
--            補色どうしが混ざって平均が定まらないときは、有彩色のうち占有率が最大の色の色相にする
--   avg    : 画像全体の平均色 (頻度表の加重平均)。背景の彩度と明るさ (知覚輝度) の目安。
--            画像の明るさ (L*) が、dark の背景と light の背景のどちらに近いかで、背景の明るさを決める (閾値を置かず、両側から等距離)
--   accent : hue から色相が ACCENT_MIN_HUE_GAP 以上離れた色のうち、彩度 x 明るさ x 占有率^SHARE_POWER x
--            (hue からの色相の離れ具合) が最大の色 (なければ制限なしで選ぶ)。最も目立ち、背景から離れた色。
--            白系の色 (彩度が低く明るい) も候補で、色相は最も離れているものとして採点する
--            再生バーの進んだ部分の色。彩度は上限で抑え、背景とのコントラストが足りなければ補正する
-- 反映先:
--   bg      : hue の色相で、avg の彩度と明るさから作る (ポップアップの背景。透過させない)
--   text, subtext, track : bg と同じ色相で、dark なら明るく、light なら暗く作る。bg とのコントラストが足りなければ補正する
--   border  : accent と同じ色相の、彩度の低い色
--   viz     : hue と色相が近い (背景と同系統の) 色の中で、同じスコアが最大の色 (棒グラフ)
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
local VIZ_FALLBACK_SATURATION = 0.5 -- 同じ場合の、棒グラフの色の彩度 (範囲内に候補がないとき)
local HUE_MIN_CONCENTRATION = 0.3 -- 色相の平均の信頼度 (0〜1) の下限。これ未満 (補色どうしが打ち消し合う) なら、最大の色の色相にする
local BG_ALPHA = 0xff -- 背景の不透明度 (透過させない)
local BORDER_ALPHA = 0xff -- 枠線の不透明度 (透過させない)
local BORDER_SATURATION = 0.22 -- 枠線 (アクセントより控えめにする)
local ACCENT_CONTRAST = 4.5 -- アクセントと背景のコントラスト比の下限
local TEXT_CONTRAST = 7 -- 曲名とアーティストの文字と背景のコントラスト比の下限
local SUBTEXT_CONTRAST = 4.5 -- アルバム名と時刻の文字
local TRACK_CONTRAST = 1.5 -- 再生位置のバーの、進んでいない部分

-- 背景の明るさに合わせた設定。dark と light のどちらにするかは、画像の平均色の明るさに近いほう (中間の明るさの背景は、
-- アクセントの色が出ないので、どちらかに寄せる)。
--   bg_*  : 背景の彩度 (平均色の彩度 x saturation_scale を min〜max に収める) と、相対輝度 (平均色の輝度 x luminance_scale を同様に収める)
--   text, subtext, track : 背景と同じ色相で作る色 (HSV の S と V)。コントラストが足りなければ補正される
--   border_value : 枠線の明るさ (HSV の V)
local THEMES = {
	dark = {
		bg_saturation = { scale = 0.6, min = 0.05, max = 0.35 },
		bg_luminance = { scale = 0.25, min = 0.012, max = 0.06 },
		text = { s = 0.12, v = 0.96 },
		subtext = { s = 0.15, v = 0.70 }, -- colors の既定は無彩色の 0xaaaaaa
		track = { s = 0.3, v = 0.3 },
		border_value = 0.42,
	},
	light = {
		bg_saturation = { scale = 0.5, min = 0.04, max = 0.25 },
		bg_luminance = { scale = 1, min = 0.6, max = 0.85 },
		text = { s = 0.3, v = 0.1 },
		subtext = { s = 0.25, v = 0.3 },
		track = { s = 0.2, v = 0.72 },
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

-- 頻度表の各色を { r, g, b, h, s, v, share } にする (share は占有率)。画像が空なら nil。
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
		out[#out + 1] = { r = c[2], g = c[3], b = c[4], h = h, s = s, v = v, share = c[1] / total }
	end
	return out
end

local function clamp(x, min, max)
	return math.max(min, math.min(max, x))
end

-- 画像全体の平均色 (占有率で重み付け)。{ s = 彩度, lum = 相対輝度 } を返す。
local function average(swatches)
	local r, g, b = 0, 0, 0
	for _, c in ipairs(swatches) do
		r, g, b = r + c.r * c.share, g + c.g * c.share, b + c.b * c.share
	end
	local _, s = rgb_to_hsv(r, g, b)
	return { s = s, lum = luminance(r, g, b) }
end

-- 背景の色相を決める: 有彩色の色相を、彩度 x 明るさ x 占有率で重み付けして、円周上で平均する。
-- 平均の信頼度 (重みに対する合成ベクトルの長さ) が HUE_MIN_CONCENTRATION 未満 (補色どうしが打ち消し合う) なら、
-- 有彩色のうち占有率が最大の色の色相にする。有彩色がなければ nil。
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

-- 棒グラフの色を選ぶ: hue (背景の色相) と近い (VIZ_MAX_HUE_GAP 以内の) 色のうち、彩度 x 明るさ x 占有率^SHARE_POWER が最大のもの。
-- 背景と同系統だが、背景より鮮やかで明るい別の色になる。候補がなければ、hue で作った色にする。
local function pick_viz(swatches, hue)
	local best, best_score
	for _, c in ipairs(swatches) do
		if c.s >= MIN_SATURATION and c.v >= MIN_VALUE and hue_distance(c.h, hue) <= VIZ_MAX_HUE_GAP then
			local score = c.s * c.v * c.share ^ SHARE_POWER
			if not best_score or score > best_score then
				best, best_score = c, score
			end
		end
	end
	return best or { h = hue, s = VIZ_FALLBACK_SATURATION, v = VIZ_FALLBACK_VALUE }
end

-- 相対輝度を、CIE L* (知覚の明るさ。0〜100) にする
local function lightness(lum)
	return lum > 0.008856 and 116 * lum ^ (1 / 3) - 16 or 903.3 * lum
end

-- 色 ({ h, s, v }) を、相対輝度が target になる明るさにして返す (RGB)。
-- 明るさ (HSV の V) を最大にしても届かないときは、届くまで彩度を下げる (白に近づける)。
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

-- 背景とのコントラストが ratio に足りなければ、dark の背景なら明るさを上げ (それでも足りなければ彩度を下げて白に近づける)、
-- light の背景なら明るさを下げる (黒に近づける)
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
	local hue = pick_hue(swatches)
	-- 再生バーの色: 背景の色相から離れた色 (ACCENT_MIN_HUE_GAP 以上) を優先する。なければ制限なしで選ぶ。
	local refs = hue and { { h = hue } } or {}
	local accent = pick_accent(swatches, refs, ACCENT_MIN_HUE_GAP) or pick_accent(swatches, refs)
	if not accent or (not hue and accent.s < MIN_SATURATION) then
		return nil -- 有彩色がない (白系だけ) 画像は、default に戻す
	end
	hue = hue or accent.h
	local viz = pick_viz(swatches, hue)
	local function limit(c)
		return { h = c.h, s = math.min(c.s, ACCENT_MAX_SATURATION), v = c.v }
	end
	accent, viz = limit(accent), limit(viz)
	-- 背景: 彩度と相対輝度を、画像全体の平均色から作る。dark と light は、作った背景の L* が平均色の L* に近いほう (同じなら dark)
	local avg = average(swatches)
	local function theme_luminance(t)
		return clamp(avg.lum * t.bg_luminance.scale, t.bg_luminance.min, t.bg_luminance.max)
	end
	local target = lightness(avg.lum)
	local light = math.abs(lightness(theme_luminance(THEMES.light)) - target)
		< math.abs(lightness(theme_luminance(THEMES.dark)) - target)
	local theme = light and THEMES.light or THEMES.dark
	local bg_s = clamp(avg.s * theme.bg_saturation.scale, theme.bg_saturation.min, theme.bg_saturation.max)
	local bg_lum = theme_luminance(theme)
	local bg = at_luminance(hue, bg_s, bg_lum)
	local a, vz = fit_contrast(accent, bg, ACCENT_CONTRAST, light), fit_contrast(viz, bg, ACCENT_CONTRAST, light)
	-- 背景と同じ色相で、文字と再生バーの進んでいない部分を作る (背景とのコントラストを確保する)
	local function tint(spec, ratio)
		return fit_contrast({ h = hue, s = spec.s, v = spec.v }, bg, ratio, light)
	end
	local border = { hsv_to_rgb(accent.h, math.min(accent.s, BORDER_SATURATION), theme.border_value) }
	local text, subtext, track =
		tint(theme.text, TEXT_CONTRAST), tint(theme.subtext, SUBTEXT_CONTRAST), tint(theme.track, TRACK_CONTRAST)
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
