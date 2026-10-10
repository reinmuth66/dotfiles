-- ノッチの真下、position "center" をクリックすると、壁紙のサムネイルをポップアップで並べ、選んだ画像を壁紙にする。
-- ノッチの下にも item を置け、クリックを受けられることを実機で確認した。
-- ノッチの item は透明で、ノッチと同じ幅。ポップアップはバーの下端から下へ、ノッチの中央にそろえて開く。
-- 壁紙は WALLPAPER_DIR の jpg、jpeg、png をファイル名順に並べる。画像を git に入れないため、リポジトリの外に置く。
-- ポップアップに同時に出すのは VISIBLE 枚まで。それより多いときは、ポップアップの上でスクロールすると、
-- 表示する範囲が 1 枚ずつずれる。端まで行ったら反対側へ回る。
-- ポップアップを開くときは、画像が VISIBLE 枚より多ければ、いまの壁紙が中央に来るように範囲を合わせる。
-- ノッチとサムネイルのどれの上にもマウスがなくなったら、CLOSE_DELAY だけ待って自動で閉じる。
-- サムネイルは extraPackages の imagemagick で作り、CACHE_DIR に置く。元の画像より新しければ作り直さない。
-- 壁紙の設定は System Events の osascript で行う。初回は、sketchybar に System Events の操作の許可が要る。
-- すべてのデスクトップ、Space に同じ画像を設定する。

local ui = require("ui")
local colors = require("colors")
local paths = require("paths")

local WALLPAPER_DIR = paths.home .. "/Pictures/wallpaper"
local CACHE_DIR = paths.cache .. "/wallpaper"

-- 表示サイズは pt。キャッシュは 2 倍の解像度の px で作る。
local THUMB_WIDTH = 128
local THUMB_HEIGHT = 72
local THUMB_SCALE = 0.5
local VISIBLE = 5

-- トラックパッドは 1 回のスワイプで多数のイベントが出るため、スクロールの量を足し合わせる。ui.scroll_accumulator を使う。
-- 上スクロールの delta > 0 で前の画像、下スクロールの delta < 0 で次の画像が見える。逆にするなら SCROLL_DIRECTION を -1 にする。
local SCROLL_THRESHOLD = 5
local SCROLL_IDLE = 0.3
local SCROLL_DIRECTION = 1

local POPUP_PADDING = 6
-- item の上下もこの高さになり、余白でもマウスを受ける
local POPUP_HEIGHT = THUMB_HEIGHT + 2 * POPUP_PADDING
local POPUP_BORDER = colors.popup.border_width

local notch = ui.add_item("wallpaper", "center", {
	icon = { drawing = false },
	label = { string = "", width = ui.notch_width, padding_left = 0, padding_right = 0 },
	padding_left = 0,
	padding_right = 0,
	background = { drawing = true, color = colors.transparent, height = ui.bar_height },
	popup = {
		align = "center",
		horizontal = true,
		height = POPUP_HEIGHT,
		y_offset = 2,
		background = {
			color = colors.popup.bg,
			border_color = colors.popup.border,
			border_width = POPUP_BORDER,
			corner_radius = colors.popup.corner_radius,
		},
	},
})

-- 画像がなければ何も出力せず、ポップアップは空のまま。
local LIST_COMMAND = string.format(
	[[mkdir -p "%s"
for f in "%s"/*.jpg "%s"/*.jpeg "%s"/*.png; do
	[ -e "$f" ] || continue
	t="%s/$(basename "$f").jpg"
	if [ ! -e "$t" ] || [ "$f" -nt "$t" ]; then
		magick "$f[0]" -auto-orient -thumbnail %dx%d^ -gravity center -extent %dx%d "$t" || continue
	fi
	printf '%%s\t%%s\n' "$f" "$t"
done]],
	CACHE_DIR,
	WALLPAPER_DIR,
	WALLPAPER_DIR,
	WALLPAPER_DIR,
	CACHE_DIR,
	THUMB_WIDTH * 2,
	THUMB_HEIGHT * 2,
	THUMB_WIDTH * 2,
	THUMB_HEIGHT * 2
)

-- AppleScript の文字列に入れるので、" と \ をエスケープする。
local function set_wallpaper(path)
	local escaped = path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local script = 'tell application "System Events" to tell every desktop to set picture to "' .. escaped .. '"'
	sbar.exec("osascript -e '" .. script:gsub("'", "'\\''") .. "'")
end

local popup_open = false

-- マウスがノッチからポップアップのサムネイルへ渡るとき、一瞬どの item の上にもない。entered の前に exited が来るため、
-- exited ですぐには閉じず、CLOSE_DELAY 秒待つ。その間に別の item に入ったら entered で、閉じるのをやめる。
local CLOSE_DELAY = 0.25
local close_timer = ui.timer()

local function close()
	close_timer.cancel()
	popup_open = false
	notch:set({ popup = { drawing = false } })
end

local function cancel_close()
	close_timer.cancel()
end

local function schedule_close()
	close_timer.start(CLOSE_DELAY, function()
		if popup_open then
			close()
		end
	end)
end

local function watch_hover(item)
	item:subscribe("mouse.entered", cancel_close)
	item:subscribe("mouse.exited", schedule_close)
end

local entries = {}
local slots = {}

-- first は、いちばん左に出す画像の一覧の添字で、0 始まり。i 番目の item は first + i - 1 番目の画像を出す。
local first = 0

-- 最後に選んだ画像のパス。System Events から、いまの壁紙のパスが取れなかった、つまり一覧にないときの代わりにする。
local chosen_path = nil

local function entry_at(slot_index)
	return entries[(first + slot_index - 1) % #entries + 1]
end

local function render()
	for i, slot in ipairs(slots) do
		slot:set({ background = { image = { string = entry_at(i).thumb } } })
	end
end

-- 最後まで行ったら最初へ戻る。逆向きも同じ。
local scroll_by_ticks = ui.scroll_accumulator(SCROLL_THRESHOLD, SCROLL_IDLE, function(sign, ticks)
	first = (first - SCROLL_DIRECTION * sign * ticks) % #entries
	render()
end)

-- 全部がポップアップに収まるときは、ずらす必要がない。
local function scroll(delta)
	if #entries <= VISIBLE then
		return
	end
	scroll_by_ticks(delta)
end

-- サムネイルの間と両端の余白は、padding ではなく透明な item で埋める。padding はマウスイベントを受けないが、
-- item は受けるので、余白の上でもスクロールでき、ポップアップの上にいる判定になる。
-- 余白の item は作った後に変更しない。再描画されないので、mouse.exited が落ちにくい。
local function add_pad(index)
	local pad = sbar.add("item", "wallpaper.pad." .. index, {
		position = "popup.wallpaper",
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { string = "", width = POPUP_PADDING, padding_left = 0, padding_right = 0 },
		background = { drawing = true, color = colors.transparent, height = POPUP_HEIGHT },
	})
	pad:subscribe("mouse.scrolled", function(env)
		scroll(env.INFO.delta)
	end)
	watch_hover(pad)
end

local function add_slot(index)
	local slot = sbar.add("item", "wallpaper.thumb." .. index, {
		position = "popup.wallpaper",
		width = THUMB_WIDTH,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			drawing = true,
			color = colors.transparent,
			height = THUMB_HEIGHT,
			image = { string = entry_at(index).thumb, scale = THUMB_SCALE, corner_radius = colors.popup.corner_radius },
		},
	})
	slot:subscribe("mouse.clicked", function()
		chosen_path = entry_at(index).path
		set_wallpaper(chosen_path)
		close()
	end)
	slot:subscribe("mouse.scrolled", function(env)
		scroll(env.INFO.delta)
	end)
	watch_hover(slot)
	slots[index] = slot
end

sbar.exec(LIST_COMMAND, function(output)
	for line in (output or ""):gmatch("[^\n]+") do
		local path, thumb = line:match("^(.-)\t(.+)$")
		if path then
			entries[#entries + 1] = { path = path, thumb = thumb }
		end
	end
	for i = 1, math.min(VISIBLE, #entries) do
		add_pad(i - 1)
		add_slot(i)
	end
	if #entries > 0 then
		add_pad(math.min(VISIBLE, #entries))
	end
end)

-- メインのディスプレイの現在のデスクトップ
local CURRENT_COMMAND = [[osascript -e 'tell application "System Events" to get picture of current desktop']]
-- 中央の item の、左から数えた位置で、0 始まり。
local CENTER = math.floor((VISIBLE - 1) / 2)

local function index_of(path)
	for i, entry in ipairs(entries) do
		if entry.path == path then
			return i
		end
	end
	return nil
end

-- 範囲を合わせてから開くので、開いた後に画像が入れ替わって見えることはない。
local function open()
	sbar.exec(CURRENT_COMMAND, function(output)
		if #entries > VISIBLE then
			local current = tostring(output or ""):match("^%s*(.-)%s*$")
			local index = index_of(current) or index_of(chosen_path)
			if index then
				first = (index - 1 - CENTER) % #entries
				render()
			end
		end
		popup_open = true
		notch:set({ popup = { drawing = true } })
	end)
end

notch:subscribe("mouse.clicked", function()
	if popup_open then
		close()
	else
		open()
	end
end)

-- バーの外へ出たときの mouse.exited.global も、ノッチとポップアップの外へ出たときと同じ扱いにする。
watch_hover(notch)
notch:subscribe("mouse.exited.global", schedule_close)
