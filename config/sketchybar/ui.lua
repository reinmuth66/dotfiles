-- item / bracket / spacer を追加するための薄いヘルパー。
-- 位置指定や余白の書き方をそろえ、各 item の定義から定型文を減らす。

local colors = require("colors")

local M = {}

-- bracket 同士の間隔。bracket の範囲は中の item の padding を含むため、
-- 何も挟まないと隣の bracket と背景が接してしまう。
M.bracket_gap = 6

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

-- position は "left" / "right" / "center" のいずれかを必ず指定する
-- (sketchybar の既定は left だが、呼び出し側で意図を明示させる)。
function M.add_item(name, position, props)
	return sbar.add("item", name, merge(props or {}, { position = position }))
end

-- members には item 名、または "/正規表現/" を渡す。
-- 背景は colors.bracket を既定にし、props.background で上書きできる。
-- 背景を描かず範囲の測定だけに使うときは { background = { drawing = false } } を渡す。
function M.add_bracket(name, members, props)
	props = props or {}
	return sbar.add(
		"bracket",
		name,
		members,
		merge(props, { background = merge(colors.bracket, props.background) })
	)
end

local spacer_count = 0

-- 幅 width の空白を作る item。name を省くと連番で命名する。
-- 幅を固定した(width を指定した) item は、負の padding_right が隣へ伝わらない
-- (実機検証)。後から padding_right を負にして隙間を詰められるよう、
-- 幅は自動のまま、空のラベルを持たせ padding_right で width を表す。
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

-- bounding_rects はディスプレイ名をキーにした表。先頭の 1 つを使う。
-- 非表示の item は origin が (-9999, -9999) になるので、画面外なら nil を返す。
local function visible_rect(name)
	local rects = sbar.query(name).bounding_rects
	for _, rect in pairs(rects or {}) do
		if rect.origin[1] >= 0 then
			return rect
		end
	end
	return nil
end

-- 隣り合う left (左) と right (右) の見た目上の隙間が spacing になるよう、
-- 2 つの間に置いた spacer (add_spacer で作ったもの) の padding_right を調整する。
-- left / right には bracket 名も渡せる。
-- 実測値に対する差分で更新するので、何度呼んでも収束する。
-- どちらかが非表示なら spacer を spacing (通常の間隔) に戻す。
-- レイアウトの反映は非同期なので、呼び出し側は変更の少し後に呼ぶこと。
function M.close_gap(opts)
	local spacer = opts.spacer
	local spacing = opts.spacing
	local left = visible_rect(opts.left)
	local right = visible_rect(opts.right)

	if left == nil or right == nil then
		spacer:set({ padding_right = spacing })
		return
	end

	local gap = right.origin[1] - (left.origin[1] + left.size[1])
	local current = sbar.query(spacer.name).geometry.padding_right
	spacer:set({ padding_right = current - (gap - spacing) })
end

return M
