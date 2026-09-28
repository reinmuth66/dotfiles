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
	width = 20,
	height = 8,
	border_width = 1,
	corner_radius = 2,
	inset = 1,
}

-- outlineとnubは、互いのpadding_rightが同じ値のときに隙間なく隣接する
-- (sketchybarの実機検証で確認した挙動)。outline側はNUB.gapをそのまま使う。

-- central/peripheralのラベルは残量の桁数で幅が変わらないよう固定幅にする
-- (そうしないと "9%" と "100%" でperipheralとの重ね位置がズレる)。
-- widthは実際の最大幅("100%"をfont_sizeで描画した幅、実機計測)以上にする。
-- これより小さいとcontentがwidthを上書きして位置ズレが復活するので注意。
local LABEL = {
	width = 31, -- Bold体の"100%"実測30px + 1pxの余裕
	font_size = 9,
	central_padding_right = 5, -- ラベル自身の右隣アイテムとの間隔
}

-- sketchybarはposition="right"のアイテムを追加順に右→左へ並べ、各アイテムの
-- 座標は「自分のpadding_right」でのみ制御できる(padding_leftは効かない)。
-- ここではcentralのlabel/nub/outlineを先に追加し、そのすぐ後ろに
-- peripheralのlabel/nub/outlineを差し込むことで、peripheral側は
-- 「centralグループの合計幅(GROUP_OFFSET)ぶんpadding_rightを引くだけ」で
-- centralの真下に重なる。この値は残量に一切依存しない固定値。
-- central_fillだけは(その後ろに追加する都合上)このoffsetを考慮した式になる。
-- peripheral_fillのみ、central_fillの実際の残量(幅)に依存する
-- 唯一のズレ得る要素だが、central_fillのpadding_rightをそのまま使って
-- 計算するので端数が生じない。
local GROUP_OFFSET = LABEL.width + NUB.width + BAR.width

local ROW_OFFSET = 7

sbar.add("event", "zmk_battery_update")

local function add_label(name, padding_right, row_offset)
	return sbar.add("item", "zmk_battery." .. name, {
		position = "right",
		drawing = false,
		width = LABEL.width,
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

-- 追加順がそのまま位置を決める:
-- central(label→nub→outline) → peripheral(label→nub→outline) → central_fill → peripheral_fill
local PERIPHERAL_OUTLINE_PADDING_RIGHT = NUB.gap - GROUP_OFFSET
-- central_fillはperipheral_outlineの直後に追加されるので、その値を基準に計算する
local CENTRAL_FILL_BASE_PADDING_RIGHT = PERIPHERAL_OUTLINE_PADDING_RIGHT - BAR.border_width - BAR.inset

local central_label = add_label("central", LABEL.central_padding_right, ROW_OFFSET)
local central_nub = add_nub("central_nub", NUB.gap, ROW_OFFSET)
local central_outline = add_outline("central_outline", NUB.gap, ROW_OFFSET)

local peripheral_label = add_label("peripheral", LABEL.central_padding_right - GROUP_OFFSET, -ROW_OFFSET)
local peripheral_nub = add_nub("peripheral_nub", NUB.gap - GROUP_OFFSET, -ROW_OFFSET)
local peripheral_outline = add_outline("peripheral_outline", PERIPHERAL_OUTLINE_PADDING_RIGHT, -ROW_OFFSET)

local central_fill = add_fill("central_fill", CENTRAL_FILL_BASE_PADDING_RIGHT, ROW_OFFSET)
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
-- こうすればCENTRAL_FILL_BASE_PADDING_RIGHT(整数)からの引き算も整数のまま
-- 保たれ、sketchybar側の丸めによる誤差が生じない。
local function trunc(x)
	return x >= 0 and math.floor(x) or math.ceil(x)
end

local function fill_width_for(level)
	local inner_width = BAR.width - BAR.border_width * 2 - BAR.inset * 2
	local clamped_level = math.max(0, math.min(100, level))
	return trunc(inner_width * clamped_level / 100)
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
local last_central_fill_padding_right = CENTRAL_FILL_BASE_PADDING_RIGHT

local function apply_central(connection_status, level_str)
	local fill_padding_right = apply_group(central, connection_status, level_str, function(fill_width)
		return CENTRAL_FILL_BASE_PADDING_RIGHT - fill_width
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

		-- peripheral_fillの計算がcentral_fillのpadding_rightに依存するため、
		-- 必ずcentralを先に処理する
		if central_fields then
			apply_central(central_fields[1], central_fields[3])
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
