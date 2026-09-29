local colors = require("colors")

local snapshot_path = os.getenv("HOME")
	.. "/Library/Application Support/com.zmk-battery-center.app/external/battery-state-v1.json"

local NUB = {
	width = 1,
	height = 4,
	corner_radius = 1,
	-- ラベルのpadding_right(LABEL.central_padding_right)を基準に、
	-- nubがラベルの左に隙間なく来るよう実機で校正した値。
	gap = 2,
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

local LABEL = {
	font_size = 11,
	central_padding_right = 5, -- ラベル自身の右隣アイテムとの間隔
}

-- zmk-battery-center本家のdigit_count()/pct_col_wと同じ考え方:
-- central/peripheralのうち桁数が大きい方に合わせて、ラベル幅を2段で共有する。
-- そうすることで、両方が1桁の時はアイコンとの間隔が詰まり、
-- 片方だけ桁数が多い時だけ、短い方の数字の左に余白ができる。
-- 各値は実機で"5%"/"45%"/"100%"をwidth=1(意図的に不足させる)に設定し、
-- bounding_rectsのsize(sketchybarが自動的に上書きして広げた実際の幅)を
-- 確認して実測した値。LABEL.font_sizeを変更した場合は再測定が必要。
-- ラベルはalign="right"なので、幅を増やした分はバーとテキストの間隔になる。
local LABEL_GAP_EXTRA = 1
local LABEL_WIDTH_BY_DIGITS = {
	[1] = 22 + LABEL_GAP_EXTRA, -- "5%"実測21px + 余裕1px
	[2] = 29 + LABEL_GAP_EXTRA, -- "45%"実測28px + 余裕1px
	[3] = 36 + LABEL_GAP_EXTRA, -- "100%"実測35px + 余裕1px
}
local MAX_LABEL_WIDTH = LABEL_WIDTH_BY_DIGITS[3]

-- LABEL.font_size(9→11pt)に比例させた見積もり値。フォント実寸の目視確認が
-- できていないため、上下2段が重ならないか実機で要確認。
local ROW_OFFSET = 7

sbar.add("event", "zmk_battery_update")

local function add_label(name, width, padding_right, row_offset)
	return sbar.add("item", "zmk_battery." .. name, {
		position = "right",
		drawing = false,
		width = width,
		padding_right = padding_right,
		icon = { drawing = false },
		label = {
			font = { style = "Bold", size = LABEL.font_size },
			y_offset = row_offset,
			align = "right",
		},
	})
end

local function add_nub(name, padding_right, row_offset)
	return sbar.add("item", "zmk_battery." .. name, {
		position = "right",
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
	return sbar.add("item", "zmk_battery." .. name, {
		position = "right",
		drawing = false,
		width = BAR.width,
		padding_right = padding_right,
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
	return sbar.add("item", "zmk_battery." .. name, {
		position = "right",
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
-- 座標は「自分のpadding_right」でのみ制御できる(padding_leftは効かない)。
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

-- zmk-battery-center本家のdigit_count()と同じロジック。
-- levelがnil(未接続/非表示)の場合は1を返し、共有幅を無駄に広げないようにする
-- (本家はunwrap_or(2)だが、本実装ではhide_group時に幅が意味を持たないため
-- 最小値でよい)。
local function digit_count(level)
	if level == nil then
		return 1
	end
	local clamped = math.min(level, 100)
	if clamped >= 100 then
		return 3
	elseif clamped >= 10 then
		return 2
	else
		return 1
	end
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
-- fill_padding_right_forには「fill_widthを受け取ってpadding_rightを返す関数」を渡す
-- (central/peripheralで塗りバーの位置計算だけが異なるため)。
local function apply_group(group, connection_status, level_str, fill_padding_right_for)
	local level = tonumber(level_str)
	if connection_status ~= "connected" or level == nil then
		hide_group(group)
		return nil
	end

	local fill_width = fill_width_for(level)
	local fill_padding_right = fill_padding_right_for(fill_width)

	group.nub:set({ drawing = true })
	group.outline:set({ drawing = true })
	group.fill:set({ drawing = true, width = fill_width, padding_right = fill_padding_right })
	group.label:set({ drawing = true, label = level .. "%" })

	return fill_padding_right
end

-- central_fillの直近のpadding_right。peripheral_fillの位置合わせに使う。
-- central未接続時は最後に計算した値を使い続ける。
local last_central_fill_padding_right = initial_layout.central_fill_draw_base_padding_right

local function apply_central(connection_status, level_str, layout)
	local fill_padding_right = apply_group(central, connection_status, level_str, function(fill_width)
		return layout.central_fill_draw_base_padding_right - fill_width
	end)
	if fill_padding_right then
		last_central_fill_padding_right = fill_padding_right
	end
end

local function apply_peripheral(connection_status, level_str)
	apply_group(peripheral, connection_status, level_str, function(fill_width)
		return last_central_fill_padding_right - fill_width
	end)
end

local function update()
	local cmd = "jq -r '.devices[0] as $d | if $d == null then empty else "
		.. "$d.connectionStatus as $cs | $d.batteryParts[] | [$cs, .id, (.levelPercent | tostring)] | @tsv end' "
		.. '"'
		.. snapshot_path
		.. '" 2>/dev/null'

	sbar.exec(cmd, function(result)
		if result == nil or result == "" then
			hide_group(central)
			hide_group(peripheral)
			return
		end

		local central_fields, peripheral_fields
		for line in result:gmatch("[^\r\n]+") do
			local fields = {}
			for field in line:gmatch("([^\t]+)") do
				table.insert(fields, field)
			end

			if fields[2] == "central" then
				central_fields = fields
			elseif not peripheral_fields then
				peripheral_fields = fields
			end
		end

		local central_level = central_fields and tonumber(central_fields[3]) or nil
		local peripheral_level = peripheral_fields and tonumber(peripheral_fields[3]) or nil
		local digits = math.max(digit_count(central_level), digit_count(peripheral_level))
		local layout = apply_shared_layout(LABEL_WIDTH_BY_DIGITS[digits])

		-- peripheral_fillの計算がcentral_fillのpadding_rightに依存するため、
		-- 必ずcentralを先に処理する
		if central_fields then
			apply_central(central_fields[1], central_fields[3], layout)
		else
			hide_group(central)
		end

		if peripheral_fields then
			apply_peripheral(peripheral_fields[1], peripheral_fields[3])
		else
			hide_group(peripheral)
		end
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

for _, group in pairs({ central, peripheral }) do
	group.nub:subscribe("mouse.clicked", toggle_main_window)
	group.outline:subscribe("mouse.clicked", toggle_main_window)
	group.fill:subscribe("mouse.clicked", toggle_main_window)
	group.label:subscribe("mouse.clicked", toggle_main_window)
end
