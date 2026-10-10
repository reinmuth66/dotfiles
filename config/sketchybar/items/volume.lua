local ui = require("ui")

-- 字面は箱の外にはみ出すと見切れるので、字面の最大幅にする。実測は 15.0 で、advance は 12.0 しかない。
-- 字面は箱の左端 + padding_left + 字面の左端のずれから描かれる。bluetooth.lua と同じ。
-- 音量が変わってもスピーカーの位置が動かないよう、スピーカーの左端を箱の左端にそろえ、波形だけが右へ伸び縮みするようにする。
-- padding は整数に切り捨てられるので、0.5pt 単位の補正はできない。実機で確認した。
-- 通常の Hack Nerd Font は字面ごとに左端のずれが違う。20pt で off と high が 0、medium が 0.38、low が 2.25。
-- そのため padding では 0.3pt 前後のずれが残り、mute と high が左にずれて見える。
-- Propo は字面ごとの位置の補正が無く、どの字面も左端が 0 なので、padding を使わずにそろう。
-- 実測は Hack Nerd Font Propo Bold 20pt を CoreText で 32 倍に描いて測った。フォントやサイズを変えたら再測定する。
--   字面        インクの左端  幅
--   off / high  0             15.0
--   medium      0             11.3
--   low         0             7.5
--   headphones  0             15.0
local ICON_WIDTH = 15

-- フォントサイズは Wi-Fi や Bluetooth の 18pt より大きくする。音量の字面は同じ 18pt では他より小さく見えるため。
-- 音量 high の字面の高さは 18pt で 13.1、Wi-Fi は 13.9、Bluetooth は 15.0。
local FONT_SIZE = 20.0

-- 字面の縦の中心はベースラインからの高さで、20pt が 6.94、Wi-Fi と Bluetooth の 18pt が 6.25。
-- Propo でも、どの字面でも同じ。他は y_offset = 1 なので、差の 0.69 を引いて 0.31 になり、整数に切り捨てて 0 にする。
local Y_OFFSET = 0

local HEADPHONES = { icon = "󰋋" } -- nf-md-headphones

local LEVELS = {
	{ max = 0, icon = "󰖁" }, -- nf-md-volume_off
	{ max = 33, icon = "󰕿" }, -- nf-md-volume_low
	{ max = 66, icon = "󰖀" }, -- nf-md-volume_medium
	{ max = 100, icon = "󰕾" }, -- nf-md-volume_high
}

local MUTED = LEVELS[1]

-- match は、出力先の名前を小文字にしたものに含まれる文字。
-- Hack Nerd Font にイヤホンの字面は無いので、Beats もヘッドホンと同じ字面にしている。
-- 他のデバイスを足すときは、SwitchAudioSource -a -t output で名前を確認する。
local DEVICES = {
	{ match = "beats", glyph = HEADPHONES },
	{ match = "headphone", glyph = HEADPHONES },
	{ match = "headset", glyph = HEADPHONES },
	{ match = "ヘッドフォン", glyph = HEADPHONES }, -- 有線のヘッドホン。内蔵の出力として現れる
	{ match = "ヘッドホン", glyph = HEADPHONES },
}

-- トラックパッドは 1 回のスワイプで慣性スクロールを含め多数のイベントが出るので、
-- スクロールの量を足し合わせて、音量キー 1 回分ずつ変える。
-- 音量キーは media-key が合成して送るので、標準の音量ポップアップが出る。pkgs/media-key を参照。
-- 音量キー 1 回は音量の 1/16 で約 6%。option を押している間の fine は 1/64 で約 1.6%。
-- SCROLL_THRESHOLD は大きいほど鈍くなる。
local SCROLL_THRESHOLD = 5
local SCROLL_IDLE = 0.3

local SETTINGS_URL = "x-apple.systempreferences:com.apple.Sound-Settings.extension"

local volume = ui.add_item("volume", "right", {
	update_freq = 5,
	icon = {
		font = { family = "Hack Nerd Font Propo", style = "Bold", size = FONT_SIZE },
		y_offset = Y_OFFSET,
		width = ICON_WIDTH,
		align = "left",
		padding_left = 0,
		padding_right = 0,
	},
	label = { drawing = false },
})

-- 音量を持たない出力は HDMI などで、値が missing value になる。
local COMMAND = [[
echo "device=$(SwitchAudioSource -c -t output)"
osascript -e 'set s to get volume settings' -e 'return "vol=" & (output volume of s as text) & linefeed & "muted=" & (output muted of s as text)'
]]

local current

-- 音量が取れない出力は、最大の段階として扱う。
local function pick(device, vol, muted)
	if muted then
		return MUTED
	end

	local name = device:lower()
	for _, d in ipairs(DEVICES) do
		if name:find(d.match, 1, true) then
			return d.glyph
		end
	end

	vol = vol or 100
	for _, level in ipairs(LEVELS) do
		if vol <= level.max then
			return level
		end
	end
	return LEVELS[#LEVELS]
end

local function update()
	sbar.exec(COMMAND, function(out)
		if type(out) ~= "string" then
			return
		end

		local device = out:match("device=([^\n]*)") or ""
		local vol = tonumber(out:match("vol=(%d+)"))
		local muted = out:match("muted=(%a+)") == "true"

		local glyph = pick(device, vol, muted)
		if glyph == current then
			return
		end
		current = glyph

		volume:set({ icon = { string = glyph.icon } })
	end)
end

-- mute は音量を変えず、mute 中も volume_change が届くかは実機で未確認。
-- そのため update_freq の数秒おきの更新でも拾う。
volume:subscribe({ "volume_change", "system_woke", "routine", "forced" }, update)
update()

local function toggle_mute()
	sbar.exec("media-key mute", update)
end

-- 音量を設定すると、同じ値でも mute が解除される。実機で確認した。
-- トラックパッドの右クリックは 2 本指で、クリックの直前に量 0 のスクロールが届くと推測している。
-- 音量が変わらないまま mute だけ解除されていたため、目盛りに達するまでは音量を設定しない。
-- 何もしないと、mute 中の右クリックが、スクロールで解除された後にクリックで mute し直してしまう。
local scroll = ui.scroll_accumulator(SCROLL_THRESHOLD, SCROLL_IDLE, function(sign, ticks, fine)
	sbar.exec(string.format("media-key %s %d%s", sign > 0 and "up" or "down", ticks, fine and " fine" or ""), update)
end)

-- bracket とクリックを受ける領域は、Wi-Fi と Bluetooth とまとめて 1 つの bracket にする items/network.lua が作る。
return {
	item = volume,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "サウンド", -- 表示言語に依存する
	toggle_mute = toggle_mute,
	scroll = scroll,
}
