-- item / bracket / spacer を追加するための薄いヘルパー。
-- 位置指定や余白の書き方をそろえ、各 item の定義から定型文を減らす。

local colors = require("colors")

local M = {}

-- bracket の範囲は中の item の padding を含むため、
-- 何も挟まないと隣の bracket と背景が接してしまう。
M.bracket_gap = 6

-- 端の item は、アイコンとラベルの内側の padding を 0 にしておくこと。
M.bracket_padding = 8

-- これを add_bracket の padding に渡すと、上下と左右の余白がそろう。
-- content_height には、見える字面の高さを使う。行の高さではない。
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

-- position は "left"、"right"、"center"、"q"、"e" のいずれかを必ず指定する。q はノッチの左、e はノッチの右。
-- sketchybar の既定は left だが、呼び出し側で意図を明示させる。
function M.add_item(name, position, props)
	return sbar.add("item", name, merge(props or {}, { position = position }))
end

-- 背景を描かず範囲の測定だけに使うときは { background = { drawing = false } } を渡す。
--
-- bracket の範囲は item の padding を含むことを実機で検証したので、padding は端の item の padding として設定する。
-- members は右から左の並び順で、item オブジェクトで渡すこと。
-- 名前や正規表現では item を特定できないため、padding を指定するとエラーにする。
-- 上下 2 段を重ねる zmk_battery のように、描画位置と並びの順序が一致しない item には使えない。
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

-- 空のラベルが 1px の幅を持つことを実機で測定した。
-- spacer の padding_right を width にしても、見た目の隙間は width + 1 になる。
local SPACER_RENDERED_WIDTH = 1

local spacer_count = 0

-- width を指定した item は、負の padding_right が隣へ伝わらないことを実機で検証した。
-- 後から padding_right を負にして隙間を詰められるよう、幅は自動のまま、空のラベルを持たせ padding_right で width を表す。
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

-- bar.lua の notch_width と items/wallpaper.lua に使う。
-- 実測は NSScreen の frame 幅 - auxiliaryTopLeftArea 幅 - auxiliaryTopRightArea 幅 で、1710 - 751 - 750。
M.notch_width = 209

-- bar.lua の height に使う。ノッチとの間隔もここから決める。
M.bar_height = 40

-- ノッチと bracket の間隔は、bracket の上下の余白と同じにする。余白は (バーの高さ - bracket の高さ) / 2。
local NOTCH_GAP = (M.bar_height - colors.bracket.height) / 2

-- position が "q" と "e" の起点を SketchyBar が求める位置の、実測したノッチの縁からのずれで、単位は pt。
-- ノッチの外側が正、内側が負。ノッチが画面の中心より 0.5 pt 右にあり、SketchyBar の対称の前提と合わない。
-- bar.c は左の起点を (画面幅 - notch_width) / 2 の切り捨てで求める。整数に丸めた結果、左右で逆向きにずれる。
-- 実測は bar.lua で、notch_width が 209 のとき、左の起点が 750 pt で実測の左端が 751 pt、右の起点が 959 pt で実測の右端が 960 pt。
local NOTCH_ORIGIN_OFFSET = { q = 1, e = -1 }

-- ノッチに最も近い位置に置くので、その側の item より先に追加すること。
-- 見た目の隙間は 幅 + SPACER_RENDERED_WIDTH + 起点のずれ になるので、上のずれを幅から引いて実測のノッチの縁からの間隔をそろえる。
-- 結果は "q" が NOTCH_GAP - 2、"e" が NOTCH_GAP。
function M.add_notch_spacer(position, name)
	local offset = NOTCH_ORIGIN_OFFSET[position]
	assert(offset ~= nil, 'add_notch_spacer: position must be "q" or "e"')
	return M.add_spacer(position, NOTCH_GAP - SPACER_RENDERED_WIDTH - offset, name)
end

-- マウスイベントは、カーソルの下にあるウィンドウに届く。SketchyBar は、マウスイベントを購読している
-- item が再描画されるたびに、その item のマウス追跡領域を張り直す。
-- このとき mouse.exited が届かなくなることがあり、ホバーで開いたポップアップが閉じなくなる。実機で再現した。
-- 再描画される item に購読させず、この item に購読させれば、この item は再描画されないので起きない。
-- bracket の背景、つまり item の padding の部分は item のウィンドウに含まれないが、この item は padding まで覆うので、bracket 全体で反応する。
--
-- 位置は、自分の padding を負の値にして合わせる。SketchyBar の配置の癖を実機で検証した。
--   - width を指定した item の後は、配置が width の分しか進まない。padding は数えられない。
--   - 自分の width を指定すると、負の padding が隣へ伝わらず隙間ができる。
-- そのため、この item は width を使わず icon.width で幅を確保し、padding で隣の item の位置を変えない。
-- padding_left + padding_right + 幅 = 0 になり、hit_region_geometry が計算する。
--
-- bracket の中の item が分かれていて、範囲ごとに別の操作を受けたいときは、範囲ごとに作る。items/network.lua を参照。
-- 重ねる item より後で、かつ bracket より後に追加すること。ウィンドウは後に追加した item が上になる。
-- 重ねる item が "q" のノッチの左のときは props.position = "q" を渡す。配置は right と同じ右から左で、端は右端。
-- "e" のノッチの右のときは props.position = "e" を渡す。配置は left と同じ左から右で、端は左端。
-- 購読は呼び出し側で行う。作った後は背景などを変更しないこと。再描画されると上の問題が戻る。
-- "e" は左から右へ並ぶので、戻す向きと進める向きが逆になる。そのため padding の左右を入れ替える。
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

-- bracket の右端から from〜to px の範囲を覆い、隣の item の位置を変えない hit の padding と幅。
-- bracket 全体なら from = 0、to = bracket の幅。
-- chain_width は、bracket の中の item が配置を右から左へ進める幅の合計。
-- width を指定した item は、後続の配置を width の分しか進めない。padding は数えられない。
-- そのため width を指定した item の width を合計する。幅が自動の item は含めない。実機で検証した。
-- padding_left + padding_right + 幅 = 0 になる。幅が変わるときは、この値を set し直す。
function M.hit_region_geometry(chain_width, from, to)
	return {
		padding_left = chain_width - to,
		padding_right = -(chain_width - from),
		icon = { string = "", width = to - from, padding_left = 0, padding_right = 0 },
	}
end

-- アイコンや隣の item に被らない位置の空の item、anchor を、ポップアップの持ち主にする。
-- opts.align が "left" なら持ち主の左端にそろって右へ伸び、"right" なら右端にそろって左へ伸びる。伸びる先の他の item は覆う。
-- ポップアップは既定でバーの下端から下に出る。y_offset を負にして上へ戻し、バーの縦の中央に置く。
-- 上端は (バーの高さ - opts.height) / 2 になる。
-- ポップアップの枠線 opts.background.border_width の分だけ中身が下にずれるので、その分も上げる。
-- 実機で、枠線 1 のとき中身の上端が 5 pt、枠線 0 のとき 4 pt だった。
-- opts.height は中身の高さ、opts.background は popup の背景で border_width を含める。
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

-- ポップアップの文字は、メニューバーと同じシステムフォントにする。
-- ファミリに ".AppleSystemUIFont" を指定すると、欧文は SF になり、日本語は自動でメニューバーと同じ
-- ".Hiragino Kaku Gothic Interface" の W4 に切り替わる。CoreText で確認した。
-- "SF Pro" などの名前は、SF Pro が入っていないと Helvetica に解決されてしまう。
-- スタイルを Bold にすると、欧文は System Font Bold、日本語は W6 になる。Regular なら W4。
local POPUP_FONT_FAMILY = ".AppleSystemUIFont"
local POPUP_FONT_STYLE = "Bold"

function M.popup_font(size, features)
	return { family = POPUP_FONT_FAMILY, style = POPUP_FONT_STYLE, size = size, features = features }
end

-- 非表示の item は origin が -9999, -9999 になるので、画面外なら nil を返す。
function M.visible_rect(name)
	local rects = sbar.query(name).bounding_rects
	for _, rect in pairs(rects or {}) do
		if rect.origin[1] >= 0 then
			return rect
		end
	end
	return nil
end

-- 見た目の隙間が、通常の spacer を挟んだときの spacing + SPACER_RENDERED_WIDTH と同じになるよう、
-- 間に置いた spacer の padding_right を調整する。
-- 実測値に対する差分で更新するので、何度呼んでも収束する。
-- レイアウトの反映は非同期なので、呼び出し側は変更の少し後に呼ぶこと。
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

-- 非同期の部品は ui/async.lua、入力まわりの部品は ui/interaction.lua に分けてある。
-- 呼び出し側は、従来どおり ui.latest などで使える。
local async = require("ui.async")
local interaction = require("ui.interaction")

M.latest = async.latest
M.timer = async.timer
M.scroll_accumulator = interaction.scroll_accumulator
M.pin = interaction.pin
M.toggle_settings = interaction.toggle_settings

return M
