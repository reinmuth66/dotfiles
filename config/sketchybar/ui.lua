-- item / bracket / spacer を追加するための薄いヘルパー。
-- 位置指定や余白の書き方をそろえ、各 item の定義から定型文を減らす。

local colors = require("colors")

local M = {}

-- bracket 同士の間隔。bracket の範囲は中の item の padding を含むため、
-- 何も挟まないと隣の bracket と背景が接してしまう。
M.bracket_gap = 6

-- bracket の背景の端から中身までの既定の余白。add_bracket の padding に渡す。
-- 端の item は、アイコンとラベルの内側の padding を 0 にしておくこと。
M.bracket_padding = 8

-- bracket の上下の端から、高さ content_height の中身までの余白 (px)。中身は縦中央に置かれる。
-- これを add_bracket の padding に渡すと、上下と左右の余白がそろう。
-- content_height には、見える字面の高さを使う (行の高さではない)。
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

-- position は "left" / "right" / "center" のいずれかを必ず指定する
-- (sketchybar の既定は left だが、呼び出し側で意図を明示させる)。
function M.add_item(name, position, props)
	return sbar.add("item", name, merge(props or {}, { position = position }))
end

-- members には item (add_item の戻り値)、item 名、"/正規表現/" のいずれかを並べる。
-- 背景は colors.bracket を既定にし、props.background で上書きできる。
-- 背景を描かず範囲の測定だけに使うときは { background = { drawing = false } } を渡す。
--
-- padding は bracket の背景の端から中身までの余白 (px)。数値なら左右同じ、
-- { left = n, right = n } なら片側だけ指定でき、省略した側は変更しない。
-- bracket の範囲は item の padding を含む (実機検証) ので、実際には端の item の
-- padding を設定している:
--   right: 最も右の item (members の先頭) の padding_right
--   left : 最も左の item (members の末尾) の padding_left
-- members は右から左の並び順で、item オブジェクトで渡すこと
-- (名前や正規表現では item を特定できないため、padding を指定するとエラーにする)。
-- 上下2段を重ねる zmk_battery のように、描画位置と並びの順序が一致しない item には使えない。
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

-- 操作 (ホバー・クリック・スクロール) を受けるための、透明で静的な item。
-- right の item (width を指定したもの) とその bracket の真上に重なり、bracket 全体で反応する。
--
-- マウスイベントは、カーソルの下にあるウィンドウに届く。SketchyBar は、マウスイベントを購読している
-- item が再描画されるたびに、その item のマウス追跡領域を張り直す。このとき mouse.exited が
-- 届かなくなることがあり (実機で再現)、ホバーで開いたポップアップが閉じなくなる。
-- 再描画される item に購読させず、この item に購読させれば、この item は再描画されないので起きない。
-- bracket の背景 (item の padding の部分) は item のウィンドウに含まれないが、この item は
-- padding まで覆うので、bracket 全体で反応する。
--
-- target_width は重ねる item の width、padding は add_bracket で item に付けた左右の padding。
-- 重ねる item より後に追加すること (ウィンドウは後に追加した item が上になる)。
-- 購読は呼び出し側で行う。作った後は背景などを変更しないこと (再描画されると上の問題が戻る)。
--
-- 位置は、自分の padding を負の値にして合わせる。実機検証した SketchyBar の配置の癖:
--   - width を指定した item の後は、配置が width の分しか進まない (padding は数えられない)。
--   - 自分の width を指定すると、負の padding が隣へ伝わらず隙間ができる。
-- そのため、この item は width を使わず icon.width で幅を確保し、右へ target_width、左へ
-- 2 * padding を戻して、隣の item の位置を変えない (padding_left + padding_right + 幅 = 0)。
function M.add_hit_layer(name, target_width, padding, props)
	return M.add_hit_layer_over(name, target_width, target_width + 2 * padding, props)
end

-- bracket の中に複数の item が並ぶ (幅が違う、または重なっている) ときの add_hit_layer。
-- 位置と幅は hit_layer_geometry で決める。
-- 重ねる item より後 (かつ bracket より後) に追加すること。
function M.add_hit_layer_over(name, chain_width, bracket_width, props)
	local layer = M.hit_layer_geometry(chain_width, bracket_width)
	layer.label = { drawing = false }
	layer.background = { drawing = true, color = 0x00000000 }
	return M.add_item(name, "right", merge(layer, props))
end

-- bracket 全体 (bracket_width) を覆い、隣の item の位置を変えない hit の padding と幅。
-- chain_width は、bracket の中の item が配置を右から左へ進める幅の合計。
-- width を指定した item は、後続の配置を width の分しか進めない (padding は数えられない) ので、
-- 幅を指定した item の width を合計する (幅が自動の item は含めない。実機で検証)。
-- bracket の右端から、hit を置く位置 (chain_width だけ進んだ所) までを負の padding_right で戻し、
-- padding_left で bracket の左端から配置の続きまで進めて、隣の位置を元に戻す。
-- (padding_left + padding_right + 幅 = 0)。幅が変わるときは、この値を set し直す。
function M.hit_layer_geometry(chain_width, bracket_width)
	return {
		padding_left = chain_width - bracket_width,
		padding_right = -chain_width,
		icon = { string = "", width = bracket_width, padding_left = 0, padding_right = 0 },
	}
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

-- add_spacer が描画する幅 (空のラベルが 1px の幅を持つ。実機で測定)。
-- spacer の padding_right を width にしても、見た目の隙間は width + 1 になる。
local SPACER_RENDERED_WIDTH = 1

-- 隣り合う left (左) と right (右) の見た目上の隙間が、通常の spacer (add_spacer の
-- width が spacing のもの) を挟んだときと同じになるよう、2 つの間に置いた spacer の
-- padding_right を調整する。見た目の隙間は spacing + SPACER_RENDERED_WIDTH。
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
	spacer:set({ padding_right = current - (gap - (spacing + SPACER_RENDERED_WIDTH)) })
end

return M
