-- item / bracket / spacer を追加するための薄いヘルパー。
-- 位置指定や余白の書き方をそろえ、各 item の定義から定型文を減らす。

local colors = require("colors")

local M = {}

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

-- 幅だけを持つ空の item。padding は 0 に固定し、width と後から設定する padding_right
-- だけで間隔を決められるようにする。name を省くと連番で命名する。
function M.add_spacer(position, width, name)
	if name == nil then
		spacer_count = spacer_count + 1
		name = "spacer." .. spacer_count
	end
	return M.add_item(name, position, {
		width = width,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
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

local base_padding = {}

local function set_padding_right(name, value)
	sbar.exec(string.format("sketchybar --set %s padding_right=%.0f", name, value))
end

-- 隣り合う left (左) と right (右) の見た目上の隙間が spacing になるよう、
-- left の padding_right を調整する。left とその左のアイテムがまとめて動く。
-- (実機検証: 幅0のspacerのpadding_rightはspacer自身しか動かさず、隙間は変わらなかった。
--  アイテム自身のpadding_rightだけが、そのアイテムと左側のアイテムを動かす。)
-- right には、複数 item の範囲を測れる bracket を渡せる。
-- 実測値に対する差分で更新するので、何度呼んでも収束する。
-- どちらかが非表示なら、最初に読み取った padding_right に戻す。
-- レイアウトの反映は非同期なので、呼び出し側は変更の少し後に呼ぶこと。
function M.close_gap(opts)
	local name = opts.left
	local current = sbar.query(name).geometry.padding_right
	base_padding[name] = base_padding[name] or current

	local left = visible_rect(name)
	local right = visible_rect(opts.right)
	if left == nil or right == nil then
		set_padding_right(name, base_padding[name])
		return
	end

	local gap = right.origin[1] - (left.origin[1] + left.size[1])
	set_padding_right(name, current - (gap - (opts.spacing or 0)))
end

return M
