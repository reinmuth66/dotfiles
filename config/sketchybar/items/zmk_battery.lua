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
-- central/peripheralのうち桁数が大きい方に合わせて、ラベル幅を2段(2桁/3桁)で共有する。
-- 100%のときだけ幅が変わり、他のレベルでは変わらない。
-- 各値は実機で"45%"/"100%"をwidth=1(意図的に不足させる)に設定し、
-- bounding_rectsのsize(sketchybarが自動的に上書きして広げた実際の幅)を
-- 確認して実測した値(label内側のpadding左右4pxずつを含む)から、
-- add_labelでpadding_rightを0にした分の4pxを引いている。
-- LABEL.font_sizeを変更した場合は再測定が必要。
-- ラベルはalign="right"なので、幅を増やした分はバーとテキストの間隔になる。
local LABEL_GAP_EXTRA = 1
local LABEL_WIDTH_BY_DIGITS = {
	[2] = 25 + LABEL_GAP_EXTRA, -- "45%"実測28px - padding_right 4px + 余裕1px
	[3] = 32 + LABEL_GAP_EXTRA, -- "100%"実測35px - padding_right 4px + 余裕1px
}
local MAX_LABEL_WIDTH = LABEL_WIDTH_BY_DIGITS[3]

-- LABEL.font_size(9→11pt)に比例させた見積もり値。フォント実寸の目視確認が
-- できていないため、上下2段が重ならないか実機で要確認。
local ROW_OFFSET = 7

-- 未接続のときの色。spotifyの未起動アイコンと同じ濃さ(0x99、約60%)の白。
local DIM_COLOR = 0x99ffffff

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
			color = 0x00000000,
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
-- ラベル幅が桁数によって変わるようになったため、group_offset以下の値は
-- 毎回layout_for()で計算し直す必要がある(以前のような不変の定数ではない)。
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

-- データ取得前の初期状態は、最も広い(3桁)レイアウトを仮定しておく。
local initial_layout = layout_for(MAX_LABEL_WIDTH)

local central_label = add_label("central", MAX_LABEL_WIDTH, LABEL.central_padding_right, ROW_OFFSET)
local central_nub = add_nub("central_nub", NUB.gap, ROW_OFFSET)
local central_outline = add_outline("central_outline", NUB.gap, ROW_OFFSET)

local peripheral_label =
	add_label("peripheral", MAX_LABEL_WIDTH, LABEL.central_padding_right - initial_layout.group_offset, -ROW_OFFSET)
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

-- bracket全体でクリックを受ける透明なitem。位置と幅は、表示内容(桁数・塗りバーの幅)に
-- 応じてapply_hit()が毎回set()し直す。bracketより後に作ること(メンバーに含めない)。
local hit = ui.add_hit_layer_over("zmk_battery.hit", 0, 0, { drawing = false })

local gap_spacer = ui.add_spacer("right", ui.bracket_gap, "zmk_battery_gap")

-- 連続して呼ばれたときは最後の1回だけ測る
local gap_generation = 0

local function settle_gap()
	gap_generation = gap_generation + 1
	local id = gap_generation
	sbar.delay(GAP_SETTLE_DELAY, function()
		if id ~= gap_generation then
			return
		end
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

-- 1桁は0埋めして2桁として扱うので、返すのは2か3のみ(100%のときだけ3)。
-- levelがnil(値が一度も取れていない/非表示)の場合は最小の2を返し、共有幅を無駄に広げないようにする。
local function digit_count(level)
	if level ~= nil and level >= 100 then
		return 3
	end
	return 2
end

-- central/peripheralの桁数のうち大きい方に合わせて共有レイアウトを適用する。
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
-- ("--%"は"05%"と同じ3文字なので、2桁用の幅に収まる)。
-- fill_padding_right_forには「fill_widthを受け取ってpadding_rightを返す関数」を渡す
-- (central/peripheralで塗りバーの位置計算だけが異なるため)。
local function apply_group(group, state, fill_padding_right_for, label_width)
	local color = state.current and colors.white or DIM_COLOR
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
	group.label:set({ drawing = true, label = { string = text, color = color } })

	-- hit layerの位置計算に使う、このグループがsketchybarの配置を進める幅
	-- (width指定のitemはwidthの分だけ進む。ui.hit_layer_geometry)。
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
	local geometry = ui.hit_layer_geometry(chain_width, bracket_width)
	geometry.drawing = true
	hit:set(geometry)
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
		.. "$d.batteryParts[] | [.id, (.levelPercent | tostring), (.valueStatus // \"unavailable\")] | @tsv end' "
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
		local digits = math.max(digit_count(central_state.level), digit_count(peripheral_state.level))
		local layout = apply_shared_layout(LABEL_WIDTH_BY_DIGITS[digits])

		-- peripheral_fillの計算がcentral_fillのpadding_rightに依存するため、
		-- 必ずcentralを先に処理する(centralは常に表示する)
		local chain_width = apply_central(central_state, layout)

		if peripheral_fields then
			chain_width = chain_width + apply_peripheral(peripheral_state, layout)
		else
			hide_group(peripheral)
		end

		apply_hit(chain_width, layout)
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
