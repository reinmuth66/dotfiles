local colors = require("colors")
local ui = require("ui")

local snapshot_path = os.getenv("HOME")
	.. "/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json"

local LABEL = {
	font_size = 11,
	-- bracketの右端からテキストまでの余白。他のbracketと同じ値にそろえる。
	-- 右端のitemなのでlabel自身のpadding_rightは0にし(add_label)、余白はここだけで決める。
	central_padding_right = ui.bracket_padding,
}

local NUB = {
	width = 1,
	height = 4,
	corner_radius = 1,
	-- sketchybarは、nubをラベルのpadding_rightの分だけ右へずらして配置する
	-- (実機検証: central_padding_rightを5から8にするとnubも3px右へ寄った)。
	-- その分を引き、central_padding_right=5のときに実機で校正したgap=2と同じ見た目にする。
	gap = LABEL.central_padding_right - 3,
}

local BAR = {
	width = 18,
	height = 10,
	border_width = 1,
	corner_radius = 2,
	inset = 1,
}

-- outlineとnubは、互いのpadding_rightが同じ値のときに隙間なく隣接する
-- (sketchybarの実機検証で確認した挙動)。outline側はNUB.gapをそのまま使う。

-- batteryと同じく、1桁は"05%"のように0埋めして2桁として扱う。
-- ラベル幅は"100%"が収まる3桁用に常に固定する(central/peripheralで共有)。
-- 幅が桁数で変わると左隣のitemが動き、右隣のSpotifyのポップアップとの隙間(items/spotify.lua)が
-- 変わるため、桁数にかかわらず固定する。
-- 値は実機で"45%"/"100%"をwidth=1(意図的に不足させる)に設定し、
-- bounding_rectsのsize(sketchybarが自動的に上書きして広げた実際の幅)を
-- 確認して実測した値(label内側のpadding左右4pxずつを含む)から、
-- add_labelでpadding_rightを0にした分の4pxを引いている。
-- LABEL.font_sizeを変更した場合は再測定が必要。
-- ラベルはalign="right"なので、2桁のときに余る分はバーとテキストの間隔になる。
--
-- 数字の位置は、右揃えのまま label.padding_right (px、整数) で動かす。大きくすると左へ、小さく(負に)すると右へ動く。
-- padding_right を変えても label の幅は変わない(実機で確認)。sketchybar の label には x_offset がない。
-- 桁数ごとに指定する(キーは桁数)。3桁("100%")は幅いっぱいなので、0 から大きくはできない。
local LABEL_PADDING_RIGHT = { [2] = 2, [3] = 0 }
local LABEL_GAP_EXTRA = 1
local LABEL_WIDTH = 32 + LABEL_GAP_EXTRA -- "100%"実測35px - padding_right 4px + 余裕1px

-- LABEL.font_size(9→11pt)に比例させた見積もり値。フォント実寸の目視確認が
-- できていないため、上下2段が重ならないか実機で要確認。
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
		-- bracketの左端に来るitemなので、bracketの左端からバーまでの余白をここで決める
		-- (central/peripheralのoutlineは同じ位置に重なるので、両方に同じ値を入れる)。
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

-- sketchybarはposition="right"のアイテムを追加順に右→左へ並べ、各アイテムの
-- 座標は「自分のpadding_right」でのみ制御できる(padding_leftは配置に効かず、
-- bracketの範囲にだけ含まれる。add_outlineはそれを左余白に使う)。
-- ここではcentralのlabel/nub/outlineを先に追加し、そのすぐ後ろに
-- peripheralのlabel/nub/outlineを差し込むことで、peripheral側は
-- 「centralグループの合計幅(group_offset)ぶんpadding_rightを引くだけ」で
-- centralの真下に重なる。
-- group_offset以下の値はラベル幅(LABEL_WIDTH)から導く。
local function layout_for(label_width)
	local group_offset = label_width + NUB.width + BAR.width
	local peripheral_outline_padding_right = NUB.gap - group_offset
	-- central_fillはperipheral_outlineの直後に追加されるので、その値を基準に計算する。
	-- この値自体はinsetに依存しない構造上の絶対基準(0%位置)。
	local central_fill_base_padding_right = peripheral_outline_padding_right - BAR.border_width
	-- 実際に描画するcentral_fillの0%位置。左右均等にinset分内側へ後退させる
	-- (上下のheight計算と同じ考え方)。
	local central_fill_draw_base_padding_right = central_fill_base_padding_right - BAR.inset
	return {
		label_width = label_width,
		group_offset = group_offset,
		peripheral_outline_padding_right = peripheral_outline_padding_right,
		central_fill_base_padding_right = central_fill_base_padding_right,
		central_fill_draw_base_padding_right = central_fill_draw_base_padding_right,
	}
end

local initial_layout = layout_for(LABEL_WIDTH)

local central_label = add_label("central", LABEL_WIDTH, LABEL.central_padding_right, ROW_OFFSET)
local central_nub = add_nub("central_nub", NUB.gap, ROW_OFFSET)
local central_outline = add_outline("central_outline", NUB.gap, ROW_OFFSET)

local peripheral_label =
	add_label("peripheral", LABEL_WIDTH, LABEL.central_padding_right - initial_layout.group_offset, -ROW_OFFSET)
local peripheral_nub = add_nub("peripheral_nub", NUB.gap - initial_layout.group_offset, -ROW_OFFSET)
local peripheral_outline =
	add_outline("peripheral_outline", initial_layout.peripheral_outline_padding_right, -ROW_OFFSET)

local central_fill = add_fill("central_fill", initial_layout.central_fill_draw_base_padding_right, ROW_OFFSET)
local peripheral_fill = add_fill("peripheral_fill", -BAR.border_width - BAR.inset, -ROW_OFFSET)

local central = { label = central_label, nub = central_nub, outline = central_outline, fill = central_fill }
local peripheral =
	{ label = peripheral_label, nub = peripheral_nub, outline = peripheral_outline, fill = peripheral_fill }

-- 上下2段を重ねるための負のpadding_rightを使う都合で、左隣のアイテムとの間に
-- 見た目より広い隙間ができる。bracketの左に置いたspacerのpadding_rightを調整し、
-- 左隣のbracket(ime)との実測の隙間が、他のbracket間と同じ(通常のspacerを挟んだとき)に
-- なるよう詰める(ui.close_gap)。
-- spacerはbracketより後に作ること(実機検証。幅は自動にしないと効かない: ui.add_spacer)。
local GAP_SETTLE_DELAY = 0.3 -- レイアウト反映を待つ秒数

ui.add_bracket("zmk_battery.bracket", { "/zmk_battery\\..*/" })

-- bracket全体でクリックを受ける透明なitem。位置と幅は、表示内容(塗りバーの幅)に
-- 応じてapply_hit()が毎回set()し直す。bracketより後に作ること(メンバーに含めない)。
local hit = ui.add_hit_region("zmk_battery.hit", 0, 0, 0, { drawing = false })

local gap_spacer = ui.add_spacer("right", ui.bracket_gap, "zmk_battery_gap")

-- 連続して呼ばれたときは最後の1回だけ測る
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

-- スナップショットにペリフェラルがないとき(片側だけのキーボードなど)にだけ使う。
-- 未接続のときは隠さず、暗い色で表示する(apply_group)。
local function hide_group(group)
	group.nub:set({ drawing = false })
	group.outline:set({ drawing = false })
	group.fill:set({ drawing = false })
	group.label:set({ drawing = false })
end

-- sketchybarはwidth/padding_rightをそれぞれ独立に0方向へ切り捨てて保持する
-- (実機検証で確認)。端数を残したまま渡すと「width+padding_right」の合計が
-- 想定とズレることがあるため、fill_widthは先にこちらで切り捨てておく。
-- こうすれば整数の基準値からの引き算も整数のまま保たれ、
-- sketchybar側の丸めによる誤差が生じない。
local function trunc(x)
	return x >= 0 and math.floor(x) or math.ceil(x)
end

local function fill_width_for(level)
	local inner_width = BAR.width - BAR.border_width * 2 - BAR.inset * 2
	local clamped_level = math.max(0, math.min(100, level))
	return trunc(inner_width * clamped_level / 100)
end

-- central/peripheralで共有するレイアウトを適用する。
-- centralラベルはwidthのみ(padding_rightは外部アイテムとの間隔なので不変)、
-- peripheral側はlabel/nub/outlineのpadding_right(いずれもgroup_offset依存)を
-- 都度書き換える。central_nub/central_outlineはcentral_labelのwidth変化に
-- sketchybarが自動追従するため、明示的な更新は不要。
local function apply_shared_layout(label_width)
	local layout = layout_for(label_width)

	central_label:set({ width = label_width })
	peripheral_label:set({
		width = label_width,
		padding_right = LABEL.central_padding_right - layout.group_offset,
	})
	peripheral_nub:set({ padding_right = NUB.gap - layout.group_offset })
	peripheral_outline:set({ padding_right = layout.peripheral_outline_padding_right })

	return layout
end

-- グループを表示状態にし、塗りバーの幅/padding_rightを反映する共通処理。
-- 値が最新でないとき(state.currentがfalse)は、スナップショットに残っている
-- 最後のレベルのまま暗い色にする。
-- levelがnil(一度も値が取れていない)ときは、塗りバーを空にしてラベルを"--%"にする
-- ("--%"は"05%"と同じ3文字なので、固定幅に収まる)。
-- fill_padding_right_forには「fill_widthを受け取ってpadding_rightを返す関数」を渡す
-- (central/peripheralで塗りバーの位置計算だけが異なるため)。
local function apply_group(group, state, fill_padding_right_for, label_width)
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
	-- 1桁のときだけ0埋めして、9%と10%で幅が変わらないようにする(batteryと同じ)
	local text = state.level and string.format("%02d%%", trunc(state.level)) or "--%"
	group.label:set({
		drawing = true,
		label = { string = text, color = color, padding_right = LABEL_PADDING_RIGHT[#text - 1] },
	})

	-- hit layerの位置計算に使う、このグループがsketchybarの配置を進める幅
	-- (width指定のitemはwidthの分だけ進む。ui.hit_region_geometry)。
	local chain_width = label_width + NUB.width + BAR.width + fill_width

	return fill_padding_right, chain_width
end

-- central_fillの直近のpadding_right。peripheral_fillの位置合わせに使う。
-- (centralは常に表示するので、更新のたびに計算し直される。)
local last_central_fill_padding_right = initial_layout.central_fill_draw_base_padding_right

-- apply_central/apply_peripheralは、そのグループのchain_widthを返す。
local function apply_central(state, layout)
	local fill_padding_right, chain_width = apply_group(central, state, function(fill_width)
		return layout.central_fill_draw_base_padding_right - fill_width
	end, layout.label_width)
	last_central_fill_padding_right = fill_padding_right
	return chain_width
end

local function apply_peripheral(state, layout)
	local _, chain_width = apply_group(peripheral, state, function(fill_width)
		return last_central_fill_padding_right - fill_width
	end, layout.label_width)
	return chain_width
end

-- hit layerをbracket全体に合わせる。bracketの幅は、左端のoutlineの左余白から
-- 右端(ラベルの右余白の外側)までで、central_padding_rightには依らない。
local function apply_hit(chain_width, layout)
	local bracket_width = layout.label_width + NUB.width + NUB.gap + BAR.width + ui.bracket_padding
	local geometry = ui.hit_region_geometry(chain_width, 0, bracket_width)
	geometry.drawing = true
	hit:set(geometry)
	return bracket_width
end

-- 直近に反映したときのchain_widthとbracket_width。apply_gapが前回との差分を取るための基準。
-- 最初のupdateより前は、itemが全て非表示で比べる基準がないのでnil
-- (その間のずれはsettle_gapが測って詰める)。
local last_chain_width, last_bracket_width

-- 左隣との隙間を、測定を待たずに保つ。
-- 隣のitemの位置は、このbracketの中でsketchybarが配置を進めた幅(chain_width)と、
-- bracketの背景の幅(bracket_width)の差で決まる。バーが変わると両者は別々に変わるので、
-- 隙間は「chain_widthの増分 - bracket_widthの増分」だけ変わる(実機で確認。fillを1px細くすると
-- 左隣が1px右へずれる)。同じだけspacerのpadding_rightを動かせば隙間は変わらない。
-- settle_gapの測り直しだけに頼ると、その間(GAP_SETTLE_DELAY)は左隣の位置がずれたままになる。
-- settle_gapは、このモデルで拾えない誤差(ペリフェラルの有無の切り替えなど)を直す役に回る。
-- ui.close_gapと同じく、spacerの現在値に対する差分で更新するので、
-- settle_gapが先に補正していても二重にならない。
-- current_padding_rightは、バッチを始める前に問い合わせたspacerの現在値
-- (バッチの途中では問い合わせられない)。
local function apply_gap(chain_width, bracket_width, current_padding_right)
	if last_chain_width ~= nil then
		local delta = (chain_width - last_chain_width) - (bracket_width - last_bracket_width)
		gap_spacer:set({ padding_right = current_padding_right - delta })
	end
	last_chain_width, last_bracket_width = chain_width, bracket_width
end

-- fields(snapshotの1行 = {id, levelPercent, valueStatus}。なければnil)から、表示に使う状態を作る。
-- zmk-battery-centerは、未接続のときもlevelPercentに最後のレベルを残し、valueStatusを
-- "stale"にする(connectionStatusがunknown/disconnected、または直近の読み取りが失敗したとき)。
-- 値がまだ一度も取れていなければlevelPercentがnullで、valueStatusは"unavailable"になる。
-- "current"のときだけ通常の白で表示し、それ以外は暗くする。
local function state_from(fields)
	if fields == nil then
		return { level = nil, current = false }
	end
	return { level = tonumber(fields[2]), current = fields[3] == "current" }
end

local function update()
	local cmd = "jq -r '.devices[0] as $d | if $d == null then empty else "
		.. '$d.batteryParts[] | [.id, (.levelPercent | tostring), (.valueStatus // "unavailable")] | @tsv end\' '
		.. '"'
		.. snapshot_path
		.. '" 2>/dev/null'

	sbar.exec(cmd, function(result)
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

		-- 以降のsetを1つのメッセージにまとめる。別々に送ると、sketchybarがその間の
		-- 中途半端なレイアウトを1フレーム描画し、左隣のitemが一瞬ずれる(実機で確認。
		-- fillとspacerを別々にsetすると1フレームだけ1px動き、1回のメッセージなら動かない)。
		-- バッチの中では問い合わせられないので、spacerの現在値は先に取っておく。
		local gap_padding_right = sbar.query(gap_spacer.name).geometry.padding_right
		sbar.begin_config()
		local layout = apply_shared_layout(LABEL_WIDTH)

		-- peripheral_fillの計算がcentral_fillのpadding_rightに依存するため、
		-- 必ずcentralを先に処理する(centralは常に表示する)
		local chain_width = apply_central(central_state, layout)

		if peripheral_fields then
			chain_width = chain_width + apply_peripheral(peripheral_state, layout)
		else
			hide_group(peripheral)
		end

		local bracket_width = apply_hit(chain_width, layout)
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

-- クリックはbracket全体を覆うhit layerで受ける(各itemには購読させない)。
hit:subscribe("mouse.clicked", toggle_main_window)
