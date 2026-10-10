local colors = require("colors")
local paths = require("paths")
local ui = require("ui")

local snapshot_path = paths.home
	.. "/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json"

local LABEL = {
	font_size = 11,
	-- 右端の item なので label 自身の padding_right は 0 にし(add_label)、余白はここだけで決める。
	central_padding_right = ui.bracket_padding,
}

local NUB = {
	width = 1,
	height = 4,
	corner_radius = 1,
	-- sketchybar は、nub をラベルの padding_right の分だけ右へずらして配置する
	-- (実機検証: central_padding_right を 5 から 8 にすると nub も 3px 右へ寄った)。
	-- その分を引き、central_padding_right=5 のときに実機で校正した gap=2 と同じ見た目にする。
	gap = LABEL.central_padding_right - 3,
}

local BAR = {
	width = 18,
	height = 10,
	border_width = 1,
	corner_radius = 2,
	inset = 1,
}

-- outline と nub は、互いの padding_right が同じ値のときに隙間なく隣接する
-- (sketchybar の実機検証で確認した挙動)。outline 側は NUB.gap をそのまま使う。

-- ラベル幅は "100%" が収まる 3 桁用に常に固定する(central/peripheral で共有)。
-- 幅が桁数で変わると左隣の item が動き、右隣の Spotify のポップアップとの隙間(items/spotify.lua)が
-- 変わるため、桁数にかかわらず固定する。
-- 値は実機で "45%"/"100%" を width=1(意図的に不足させる)に設定し、
-- bounding_rects の size(sketchybar が自動的に上書きして広げた実際の幅)を
-- 確認して実測した値(label 内側の padding 左右 4px ずつを含む)から、
-- add_label で padding_right を 0 にした分の 4px を引いている。
-- LABEL.font_size を変更した場合は再測定が必要。
-- ラベルは align="right" なので、2 桁のときに余る分はバーとテキストの間隔になる。
--
-- 数字の位置は、右揃えのまま label.padding_right (px、整数) で動かす。大きくすると左へ、小さく(負に)すると右へ動く。
-- padding_right を変えても label の幅は変わない(実機で確認)。sketchybar の label には x_offset がない。
-- 桁数ごとに指定する(キーは桁数)。3 桁("100%")は幅いっぱいなので、0 から大きくはできない。
local LABEL_PADDING_RIGHT = { [2] = 2, [3] = 0 }
local LABEL_GAP_EXTRA = 1
local LABEL_WIDTH = 32 + LABEL_GAP_EXTRA -- "100%" 実測 35px - padding_right 4px + 余裕 1px

-- LABEL.font_size(9→11pt)に比例させた見積もり値。フォント実寸の目視確認が
-- できていないため、上下 2 段が重ならないか実機で要確認。
local ROW_OFFSET = 7

sbar.add("event", "zmk_battery_update")

local function add_label(name, width, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = width,
		padding_right = padding_right,
		icon = { drawing = false },
		label = {
			font = { size = LABEL.font_size },
			y_offset = row_offset,
			align = "right",
			padding_right = 0,
		},
	})
end

local function add_nub(name, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = NUB.width,
		padding_right = padding_right,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.white,
			corner_radius = NUB.corner_radius,
			height = NUB.height,
			y_offset = row_offset,
			drawing = true,
		},
	})
end

local function add_outline(name, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = BAR.width,
		padding_right = padding_right,
		-- bracket の左端に来る item なので、bracket の左端からバーまでの余白をここで決める
		-- (central/peripheral の outline は同じ位置に重なるので、両方に同じ値を入れる)。
		padding_left = ui.bracket_padding,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.transparent,
			border_color = colors.white,
			border_width = BAR.border_width,
			corner_radius = BAR.corner_radius,
			height = BAR.height,
			y_offset = row_offset,
			drawing = true,
		},
	})
end

local function add_fill(name, padding_right, row_offset)
	return ui.add_item("zmk_battery." .. name, "right", {
		drawing = false,
		width = 0,
		padding_right = padding_right,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.white,
			corner_radius = math.max(BAR.corner_radius - BAR.inset, 0),
			height = BAR.height - BAR.border_width * 2 - BAR.inset * 2,
			y_offset = row_offset,
			drawing = true,
		},
	})
end

-- sketchybar は position="right" のアイテムを追加順に右→左へ並べ、各アイテムの
-- 座標は「自分の padding_right」でのみ制御できる(padding_left は配置に効かず、
-- bracket の範囲にだけ含まれる。add_outline はそれを左余白に使う)。
-- ここでは central の label/nub/outline を先に追加し、そのすぐ後ろに
-- peripheral の label/nub/outline を差し込むことで、peripheral 側は
-- 「central グループの合計幅(group_offset)ぶん padding_right を引くだけ」で
-- central の真下に重なる。
-- central_nub/central_outline は central_label の幅に合わせて sketchybar が配置する。
local GROUP_OFFSET = LABEL_WIDTH + NUB.width + BAR.width
local PERIPHERAL_OUTLINE_PADDING_RIGHT = NUB.gap - GROUP_OFFSET
-- central_fill は peripheral_outline の直後に追加されるので、その値を基準に計算する。
local CENTRAL_FILL_BASE_PADDING_RIGHT = PERIPHERAL_OUTLINE_PADDING_RIGHT - BAR.border_width
-- 左右均等に inset 分内側へ後退させる (上下の height 計算と同じ考え方)。
local CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT = CENTRAL_FILL_BASE_PADDING_RIGHT - BAR.inset

local central_label = add_label("central", LABEL_WIDTH, LABEL.central_padding_right, ROW_OFFSET)
local central_nub = add_nub("central_nub", NUB.gap, ROW_OFFSET)
local central_outline = add_outline("central_outline", NUB.gap, ROW_OFFSET)

local peripheral_label =
	add_label("peripheral", LABEL_WIDTH, LABEL.central_padding_right - GROUP_OFFSET, -ROW_OFFSET)
local peripheral_nub = add_nub("peripheral_nub", NUB.gap - GROUP_OFFSET, -ROW_OFFSET)
local peripheral_outline = add_outline("peripheral_outline", PERIPHERAL_OUTLINE_PADDING_RIGHT, -ROW_OFFSET)

local central_fill = add_fill("central_fill", CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT, ROW_OFFSET)
local peripheral_fill = add_fill("peripheral_fill", -BAR.border_width - BAR.inset, -ROW_OFFSET)

local central = { label = central_label, nub = central_nub, outline = central_outline, fill = central_fill }
local peripheral =
	{ label = peripheral_label, nub = peripheral_nub, outline = peripheral_outline, fill = peripheral_fill }

-- 上下 2 段を重ねるための負の padding_right を使う都合で、左隣のアイテムとの間に
-- 見た目より広い隙間ができる。bracket の左に置いた spacer の padding_right を調整し、
-- 左隣の bracket(ime)との実測の隙間が、他の bracket 間と同じ(通常の spacer を挟んだとき)に
-- なるよう詰める(ui.close_gap)。
-- spacer は bracket より後に作ること(実機検証。幅は自動にしないと効かない: ui.add_spacer)。
local GAP_SETTLE_DELAY = 0.3

ui.add_bracket("zmk_battery.bracket", { "/zmk_battery\\..*/" })

-- bracket より後に作ること(メンバーに含めない)。
local hit = ui.add_hit_region("zmk_battery.hit", 0, 0, 0, { drawing = false })

local gap_spacer = ui.add_spacer("right", ui.bracket_gap, "zmk_battery_gap")

local gap_timer = ui.timer()

local function settle_gap()
	gap_timer.start(GAP_SETTLE_DELAY, function()
		ui.close_gap({
			left = "ime.bracket",
			right = "zmk_battery.bracket",
			spacer = gap_spacer,
			spacing = ui.bracket_gap,
		})
	end)
end

-- 未接続のときは隠さず、暗い色で表示する(apply_group)。
local function hide_group(group)
	group.nub:set({ drawing = false })
	group.outline:set({ drawing = false })
	group.fill:set({ drawing = false })
	group.label:set({ drawing = false })
end

-- sketchybar は width/padding_right をそれぞれ独立に 0 方向へ切り捨てて保持する
-- (実機検証で確認)。端数を残したまま渡すと「width+padding_right」の合計が
-- 想定とズレることがあるため、fill_width は先にこちらで切り捨てておく。
-- こうすれば整数の基準値からの引き算も整数のまま保たれ、
-- sketchybar 側の丸めによる誤差が生じない。
local function trunc(x)
	return x >= 0 and math.floor(x) or math.ceil(x)
end

local function fill_width_for(level)
	local inner_width = BAR.width - BAR.border_width * 2 - BAR.inset * 2
	local clamped_level = math.max(0, math.min(100, level))
	return trunc(inner_width * clamped_level / 100)
end

-- "--%" は "05%" と同じ 3 文字なので、固定幅に収まる。
-- central/peripheral で塗りバーの位置計算だけが異なるため、fill_padding_right_for で渡す。
local function apply_group(group, state, fill_padding_right_for)
	local color = state.current and colors.white or colors.dim
	local fill_width = state.level and fill_width_for(state.level) or 0
	local fill_padding_right = fill_padding_right_for(fill_width)

	group.nub:set({ drawing = true, background = { color = color } })
	group.outline:set({ drawing = true, background = { border_color = color } })
	group.fill:set({
		drawing = true,
		width = fill_width,
		padding_right = fill_padding_right,
		background = { color = color },
	})
	-- 1 桁のときだけ 0 埋めして、9%と 10%で幅が変わらないようにする(battery と同じ)
	local text = state.level and string.format("%02d%%", trunc(state.level)) or "--%"
	group.label:set({
		drawing = true,
		label = { string = text, color = color, padding_right = LABEL_PADDING_RIGHT[#text - 1] },
	})

	-- width 指定の item は width の分だけ配置が進む (ui.hit_region_geometry)。
	local chain_width = LABEL_WIDTH + NUB.width + BAR.width + fill_width

	return fill_padding_right, chain_width
end

local last_central_fill_padding_right = CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT

local function apply_central(state)
	local fill_padding_right, chain_width = apply_group(central, state, function(fill_width)
		return CENTRAL_FILL_DRAW_BASE_PADDING_RIGHT - fill_width
	end)
	last_central_fill_padding_right = fill_padding_right
	return chain_width
end

local function apply_peripheral(state)
	local _, chain_width = apply_group(peripheral, state, function(fill_width)
		return last_central_fill_padding_right - fill_width
	end)
	return chain_width
end

local function apply_hit(chain_width)
	local bracket_width = LABEL_WIDTH + NUB.width + NUB.gap + BAR.width + ui.bracket_padding
	local geometry = ui.hit_region_geometry(chain_width, 0, bracket_width)
	geometry.drawing = true
	hit:set(geometry)
	return bracket_width
end

-- 最初の update より前は、item が全て非表示で比べる基準がないので nil
-- (その間のずれは settle_gap が測って詰める)。
local last_chain_width, last_bracket_width

-- 隣の item の位置は、この bracket の中で sketchybar が配置を進めた幅(chain_width)と、
-- bracket の背景の幅(bracket_width)の差で決まる。バーが変わると両者は別々に変わるので、
-- 隙間は「chain_width の増分 - bracket_width の増分」だけ変わる(実機で確認。fill を 1px 細くすると
-- 左隣が 1px 右へずれる)。同じだけ spacer の padding_right を動かせば隙間は変わらない。
-- settle_gap の測り直しだけに頼ると、その間(GAP_SETTLE_DELAY)は左隣の位置がずれたままになる。
-- settle_gap は、このモデルで拾えない誤差(ペリフェラルの有無の切り替えなど)を直す役に回る。
-- ui.close_gap と同じく、spacer の現在値に対する差分で更新するので、
-- settle_gap が先に補正していても二重にならない。
local function apply_gap(chain_width, bracket_width, current_padding_right)
	if last_chain_width ~= nil then
		local delta = (chain_width - last_chain_width) - (bracket_width - last_bracket_width)
		gap_spacer:set({ padding_right = current_padding_right - delta })
	end
	last_chain_width, last_bracket_width = chain_width, bracket_width
end

-- zmk-battery-center は、未接続のときも levelPercent に最後のレベルを残し、valueStatus を
-- "stale" にする(connectionStatus が unknown/disconnected、または直近の読み取りが失敗したとき)。
-- 値がまだ一度も取れていなければ levelPercent が null で、valueStatus は "unavailable" になる。
-- "current" のときだけ通常の白で表示し、それ以外は暗くする。
local function state_from(fields)
	if fields == nil then
		return { level = nil, current = false }
	end
	return { level = tonumber(fields[2]), current = fields[3] == "current" }
end

local SNAPSHOT_COMMAND = "jq -r '.devices[0] as $d | if $d == null then empty else "
	.. '$d.batteryParts[] | [.id, (.levelPercent | tostring), (.valueStatus // "unavailable")] | @tsv end\' '
	.. '"'
	.. snapshot_path
	.. '" 2>/dev/null'

local function update()
	sbar.exec(SNAPSHOT_COMMAND, function(result)
		local central_fields, peripheral_fields
		for line in (result or ""):gmatch("[^\r\n]+") do
			local fields = {}
			for field in line:gmatch("([^\t]+)") do
				table.insert(fields, field)
			end

			if fields[1] == "central" then
				central_fields = fields
			elseif not peripheral_fields then
				peripheral_fields = fields
			end
		end

		local central_state = state_from(central_fields)
		local peripheral_state = state_from(peripheral_fields)

		-- 以降の set を 1 つのメッセージにまとめる。別々に送ると、sketchybar がその間の
		-- 中途半端なレイアウトを 1 フレーム描画し、左隣の item が一瞬ずれる(実機で確認。
		-- fill と spacer を別々に set すると 1 フレームだけ 1px 動き、1 回のメッセージなら動かない)。
		-- バッチの中では問い合わせられないので、spacer の現在値は先に取っておく。
		local gap_padding_right = sbar.query(gap_spacer.name).geometry.padding_right
		sbar.begin_config()

		-- peripheral_fill の計算が central_fill の padding_right に依存するため、
		-- 必ず central を先に処理する(central は常に表示する)
		local chain_width = apply_central(central_state)

		if peripheral_fields then
			chain_width = chain_width + apply_peripheral(peripheral_state)
		else
			hide_group(peripheral)
		end

		local bracket_width = apply_hit(chain_width)
		apply_gap(chain_width, bracket_width, gap_padding_right)
		sbar.end_config()
		settle_gap()
	end)
end

central.label:subscribe({ "forced", "system_woke", "zmk_battery_update" }, update)

local function toggle_main_window()
	local script = [[
tell application "System Events"
	if (count of windows of process "zmk-battery-center") > 0 then
		activate
	else
		tell process "zmk-battery-center"
			perform action "AXPress" of menu item "Show" of menu 1 of menu bar item 1 of menu bar 2
		end tell
	end if
end tell
]]

	sbar.exec("osascript -e '" .. script .. "' 2>/dev/null")
end

-- クリックは bracket 全体を覆う hit layer で受ける(各 item には購読させない)。
hit:subscribe("mouse.clicked", toggle_main_window)
