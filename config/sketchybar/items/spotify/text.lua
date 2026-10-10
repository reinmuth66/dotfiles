-- Spotify のポップアップの文字 (曲名、アーティスト) を、指定の幅に収まる所で切る (items/spotify.lua が使う)。
-- 幅は、文字ごとの em 換算の見積もりで測る。

-- 文字の幅 (em 換算)。メニューバーと同じシステムフォント Bold を、12pt で CoreText が測った値 (ASCII の 1 文字ごと)。
-- 全角 (かな・漢字など) は一律 0.923、ASCII 以外の半角 (アクセント付きの文字、キリル文字など) は平均の EM_OTHER にする。
-- 注意: このフォントは文字の間隔が大きさで変わり (小さいほど広い。11pt は 12pt より約 1%、14pt は約 2% 狭い)、
-- 100pt などの大きな値で測ると、実際の表示 (11〜14pt) より 1 割以上狭く出る。必ず表示と同じ大きさ付近で測ること。
-- 曲名・アーティスト名のサンプル 38 件で、実測 (11、12、14pt) との差は -3.9%〜+4.8% (平均 -0.2%〜+2.3%)。
-- 過小な見積もりの分は TEXT_MARGIN で吸収する。
local EM_WIDE = 0.923
local EM_OTHER = 0.6
local EM_REF_SIZE = 12
local EM_PER_PT = 0.01 -- 大きさが 1pt 小さいと、幅が増える割合

-- 0x20 (空白) から 0x7E (~) までの 95 個。
-- 数値のリストにせず文字列にしているのは、フォーマッタ (stylua) に 1 個 1 行へ展開されないため。
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
local TEXT_MARGIN = 8 -- 見積もりの誤差 (過小に見積もる最大 約 4%) の分、幅から引く (pt)

local function char_em(code)
	if code >= 0x2E80 then
		return EM_WIDE
	end
	return EM_ASCII[code - 31] or EM_OTHER
end

local M = {}

-- utf8.len が nil なら不正なバイト列なのでそのまま使う
-- 大きさが基準 (EM_REF_SIZE) と違う分の、間隔の変化の補正 (size が小さいほど、1em あたりの幅が広い) は、半角だけにかける。
-- 全角は大きさによらず一律 EM_WIDE (8pt と 12pt で CoreText が測った値が同じ)。
function M.truncate(text, size, width)
	if utf8.len(text) == nil then
		return text
	end
	local spacing = 1 + EM_PER_PT * (EM_REF_SIZE - size)
	local limit = (width - TEXT_MARGIN) / size
	local total = 0
	local cut = 1 -- バイト位置
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
