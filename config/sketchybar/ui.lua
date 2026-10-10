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

-- position は "left" / "right" / "center" / "q" (ノッチの左) / "e" (ノッチの右) のいずれかを必ず指定する
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

-- add_spacer が描画する幅 (空のラベルが 1px の幅を持つ。実機で測定)。
-- spacer の padding_right を width にしても、見た目の隙間は width + 1 になる。
local SPACER_RENDERED_WIDTH = 1

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

-- 内蔵ディスプレイのノッチの幅 (pt)。bar.lua の notch_width と items/wallpaper.lua に使う。
-- NSScreen の frame 幅 - auxiliaryTopLeftArea 幅 - auxiliaryTopRightArea 幅 (1710 - 751 - 750) で実測した。
M.notch_width = 209

-- バーの高さ。bar.lua の height に使う (ノッチとの間隔もここから決める)。
M.bar_height = 40

-- ノッチと bracket の間隔は、bracket の上下の余白 (バーの高さ - bracket の高さ) / 2 と同じにする。
local NOTCH_GAP = (M.bar_height - colors.bracket.height) / 2

-- SketchyBar が position "q" / "e" の起点を求める位置の、実測したノッチの縁からのずれ (pt)。
-- ノッチの外側が正、内側が負。ノッチが画面の中心より 0.5 pt 右にあり、SketchyBar の対称の前提
-- (bar.c は左の起点を (画面幅 - notch_width) / 2 の切り捨てで求める) と合わないため、整数に丸めた結果、
-- 左右で逆向きにずれる (実測は bar.lua。notch_width = 209 で、左の起点 750 pt / 実測の左端 751 pt、
-- 右の起点 959 pt / 実測の右端 960 pt)。
local NOTCH_ORIGIN_OFFSET = { q = 1, e = -1 }

-- ノッチの脇 (position "q" = 左、"e" = 右) の item とノッチの間隔 (NOTCH_GAP) を作る spacer。
-- ノッチに最も近い位置に置くので、その側の item より先に追加すること。
-- 見た目の隙間は 幅 + SPACER_RENDERED_WIDTH + 起点のずれ になるので、上のずれを幅から引いて
-- 実測のノッチの縁からの間隔をそろえる ("q" は NOTCH_GAP - 2、"e" は NOTCH_GAP)。
function M.add_notch_spacer(position, name)
	local offset = NOTCH_ORIGIN_OFFSET[position]
	assert(offset ~= nil, 'add_notch_spacer: position must be "q" or "e"')
	return M.add_spacer(position, NOTCH_GAP - SPACER_RENDERED_WIDTH - offset, name)
end

-- 操作 (ホバー・クリック・スクロール) を受けるための、透明で静的な item。
-- right (または q、e) の item とその bracket の真上に重なり、bracket 全体、またはその一部の範囲で反応する。
--
-- マウスイベントは、カーソルの下にあるウィンドウに届く。SketchyBar は、マウスイベントを購読している
-- item が再描画されるたびに、その item のマウス追跡領域を張り直す。このとき mouse.exited が
-- 届かなくなることがあり (実機で再現)、ホバーで開いたポップアップが閉じなくなる。
-- 再描画される item に購読させず、この item に購読させれば、この item は再描画されないので起きない。
-- bracket の背景 (item の padding の部分) は item のウィンドウに含まれないが、この item は
-- padding まで覆うので、bracket 全体で反応する。
--
-- 位置は、自分の padding を負の値にして合わせる。実機検証した SketchyBar の配置の癖:
--   - width を指定した item の後は、配置が width の分しか進まない (padding は数えられない)。
--   - 自分の width を指定すると、負の padding が隣へ伝わらず隙間ができる。
-- そのため、この item は width を使わず icon.width で幅を確保し、padding で隣の item の位置を変えない
-- (padding_left + padding_right + 幅 = 0。hit_region_geometry)。
--
-- bracket の端から from〜to (px) の範囲を覆う。bracket 全体なら from = 0、to = bracket の幅。
-- bracket の中の item が分かれていて、範囲ごとに別の操作を受けたいときは、範囲ごとに作る (items/network.lua)。
-- chain_width は、bracket の中の item が配置を進める幅の合計 (hit_region_geometry)。
-- 重ねる item より後 (かつ bracket より後) に追加すること (ウィンドウは後に追加した item が上になる)。
-- 重ねる item が "q" (ノッチの左) のときは props.position = "q" を渡す (配置は right と同じ右から左で、端は右端)。
-- "e" (ノッチの右) のときは props.position = "e" を渡す (配置は left と同じ左から右で、端は左端)。
-- 購読は呼び出し側で行う。作った後は背景などを変更しないこと (再描画されると上の問題が戻る)。
function M.add_hit_region(name, chain_width, from, to, props)
	local layer = M.hit_region_geometry(chain_width, from, to)
	layer.label = { drawing = false }
	layer.background = { drawing = true, color = colors.transparent }
	local position = props and props.position or "right"
	if position == "e" then
		-- "e" (ノッチの右) は左から右へ並ぶので、戻す向きと進める向きが逆になる
		layer.padding_left, layer.padding_right = layer.padding_right, layer.padding_left
	end
	return M.add_item(name, position, merge(layer, props))
end

-- bracket の右端から from〜to (px) の範囲を覆い、隣の item の位置を変えない hit の padding と幅。
-- bracket 全体なら from = 0、to = bracket の幅。
-- chain_width は、bracket の中の item が配置を右から左へ進める幅の合計。
-- width を指定した item は、後続の配置を width の分しか進めない (padding は数えられない) ので、
-- 幅を指定した item の width を合計する (幅が自動の item は含めない。実機で検証)。
-- bracket の右端から範囲の右端 (from) の位置までを負の padding_right で戻し、
-- padding_left で範囲の左端 (to) から配置の続き (chain_width) まで進めて、隣の位置を元に戻す。
-- (padding_left + padding_right + 幅 = 0)。幅が変わるときは、この値を set し直す。
function M.hit_region_geometry(chain_width, from, to)
	return {
		padding_left = chain_width - to,
		padding_right = -(chain_width - from),
		icon = { string = "", width = to - from, padding_left = 0, padding_right = 0 },
	}
end

-- バーの中にポップアップを出すための、空の item (anchor)。ポップアップの持ち主を、アイコンや隣の item に被らない
-- 位置の空の item にする。opts.align は、持ち主のどちら側の端にポップアップをそろえるか
-- ("left" なら持ち主の左端にそろって右へ伸び、"right" なら右端にそろって左へ伸びる。伸びる先の他の item は覆う)。
-- ポップアップは既定でバーの下端から下に出る。y_offset を負にして上へ戻し、バーの縦の中央に置く
-- (上端が (バーの高さ - opts.height) / 2 になる)。ポップアップの枠線 (opts.background.border_width) の分だけ
-- 中身が下にずれる (実機で、枠線 1 のとき中身の上端が 5 pt、枠線 0 のとき 4 pt) ので、その分も上げる。
-- opts.height は中身の高さ、opts.background は popup の背景 (border_width を含める)。
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
-- ファミリに ".AppleSystemUIFont" を指定すると欧文は SF になり、日本語は自動で
-- メニューバーと同じ ".Hiragino Kaku Gothic Interface" (W4) に切り替わる (CoreText で確認)。
-- "SF Pro" などの名前は、SF Pro が入っていないと Helvetica に解決されてしまう。
local POPUP_FONT_FAMILY = ".AppleSystemUIFont"
local POPUP_FONT_STYLE = "Bold" -- 欧文は System Font Bold、日本語は W6 になる (Regular なら W4)

-- features は OpenType の機能タグ (カンマ区切り)。時刻には等幅数字の "tnum" を渡す
function M.popup_font(size, features)
	return { family = POPUP_FONT_FAMILY, style = POPUP_FONT_STYLE, size = size, features = features }
end

-- システム設定の画面を開く。その画面がすでに前面に出ているときは、閉じる (トグル)。
-- 前面かどうかは、System Settings のウィンドウ (最前面の 1 枚) のタイトルが title_pattern を含むかで見る
-- (アクセシビリティ。実機で、タイトルが "Wi‑Fi" / "Bluetooth" で取れることを確認)。
-- タイトルは表示言語に依存するので、取れない・一致しないときは、閉じずに開く (前面へ出す) だけにする。
-- 最後のウィンドウを閉じるとシステム設定のアプリ自体が終了する (実機で確認)。
function M.toggle_settings(url, title_pattern)
	local check = string.format(
		[[tell application "System Events"
if not (exists process "System Settings") then return "open"
tell process "System Settings"
if (count of windows) = 0 then return "open"
if frontmost and (name of window 1) contains "%s" then return "close"
return "open"
end tell
end tell]],
		title_pattern
	)
	local close = [[tell application "System Events" to tell process "System Settings" to click (value of attribute "AXCloseButton" of window 1)]]
	-- 起動していないときの確認 (osascript) は約 1.6 秒かかるので、pgrep (約 0.02 秒) で先に見て、
	-- 起動していなければ確認せずにすぐ開く (起動中の確認は約 0.13 秒)
	local command = string.format(
		"if pgrep -qx 'System Settings' && [ \"$(osascript -e '%s' 2>/dev/null)\" = close ]; then osascript -e '%s' >/dev/null 2>&1; else open '%s'; fi",
		check,
		close,
		url
	)
	sbar.exec(command)
end

-- bounding_rects はディスプレイ名をキーにした表。先頭の 1 つを使う。
-- 非表示の item は origin が (-9999, -9999) になるので、画面外なら nil を返す。
function M.visible_rect(name)
	local rects = sbar.query(name).bounding_rects
	for _, rect in pairs(rects or {}) do
		if rect.origin[1] >= 0 then
			return rect
		end
	end
	return nil
end

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

-- 「最後の呼び出しだけ有効」にするための札。非同期の処理 (遅延実行、シェルの実行結果の受け取りなど) の
-- 完了時に、その間に別の呼び出しが来ていないかを確かめるのに使う。
-- begin は、前の呼び出しを無効にして新しい呼び出しを始め、その呼び出しがまだ最後かを返す関数 (valid) を返す。
-- snapshot は、前の呼び出しを無効にせず、いまの呼び出しがまだ最後かを返す関数を返す。
-- cancel は、これまでの呼び出しをすべて無効にする。
function M.latest()
	local generation = 0
	local latest = {}

	function latest.begin()
		generation = generation + 1
		return latest.snapshot()
	end

	function latest.snapshot()
		local id = generation
		return function()
			return id == generation
		end
	end

	function latest.cancel()
		generation = generation + 1
	end

	return latest
end

-- 取り消せる遅延実行。start は前の予約を取り消して新しく予約する (連続して呼ばれたときは最後の 1 回だけ実行される)。
-- cancel は予約を取り消す。pending は、予約が残っている (まだ実行も取り消しもされていない) 間 true。
function M.timer()
	local latest = M.latest()
	local timer = { pending = false }

	function timer.start(delay, fn)
		local valid = latest.begin()
		timer.pending = true
		sbar.delay(delay, function()
			if not valid() then
				return
			end
			timer.pending = false
			fn()
		end)
	end

	function timer.cancel()
		latest.cancel()
		timer.pending = false
	end

	return timer
end

-- スクロールの量 (delta) を足し合わせ、threshold に達するごとに on_ticks(sign, ticks, ...) を呼ぶ関数を返す。
-- sign は向き (上スクロールが正の delta)、ticks は達した目盛りの数。返した関数の delta 以外の引数は、そのまま
-- on_ticks に渡る。トラックパッドは 1 回のスワイプで多数のイベントが出る (慣性スクロール含む) ので、
-- イベントごとには反応せず、目盛りに達するまでは何もしない。
-- 向きが変わったら、逆向きの分は持ち越さない。idle 秒スクロールが止まったら、足し合わせた量を捨てる
-- (次の操作に持ち越さない)。量 0 のイベントは無視する。
function M.scroll_accumulator(threshold, idle, on_ticks)
	local sum = 0
	local idle_timer = M.timer()

	return function(delta, ...)
		delta = tonumber(delta)
		if not delta or delta == 0 then
			return
		end

		if sum * delta < 0 then
			sum = 0
		end
		sum = sum + delta

		idle_timer.start(idle, function()
			sum = 0
		end)

		local ticks = math.floor(math.abs(sum) / threshold)
		if ticks == 0 then
			return
		end
		local sign = sum > 0 and 1 or -1
		sum = sum - sign * ticks * threshold

		on_ticks(sign, ticks, ...)
	end
end

-- 右クリックでのピン留め。ピン留め中は、マウスが外れてもポップアップを閉じない (閉じる側が pin.active を見る)。
-- もう一度右クリックすると外す (toggle)。on_change(active) は、状態が変わったときに呼ぶ
-- (ピン留め中を bracket の枠線の色などで示す)。
function M.pin(on_change)
	local pin = { active = false }

	function pin.set(active)
		pin.active = active
		on_change(active)
	end

	-- 右クリックの処理。ポップアップが開いていないときは、ピン留めしない。外すのはいつでもできる
	function pin.toggle(popup_open)
		if pin.active then
			pin.set(false)
		elseif popup_open then
			pin.set(true)
		end
	end

	return pin
end

return M
