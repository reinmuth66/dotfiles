local ui = require("ui")

-- アイコンの箱の幅 (padding を含む全幅)。字面は箱の外にはみ出すと見切れるので、字面の最大幅
-- (実測 15.0。advance は 12.0 しかない) にする。
-- 字面は箱の左端 + padding_left + 字面の左端のずれ から描かれる (bluetooth.lua と同じ)。
-- 音量が変わってもスピーカーの位置が動かないよう、スピーカーの左端が箱の左端にそろうようにする (波形だけが右へ伸び縮みする)。
-- padding は整数に切り捨てられる (実機で確認) ので、0.5pt 単位の補正はできない。
-- 通常の Hack Nerd Font は、字面ごとに左端のずれが違う (20pt で off / high 0、medium 0.38、low 2.25) ので、
-- padding では 0.3pt 前後のずれが残り、mute と high が左にずれて見える。
-- Propo は、字面ごとの位置の補正が無く、どの字面も左端が 0 なので、padding を使わずにそろう。
-- 実測値 (Hack Nerd Font Propo Bold 20pt、CoreText で 32 倍に描いて測定): フォントやサイズを変えたら再測定が必要。
--   字面        インクの左端  幅
--   off / high  0             15.0
--   medium      0             11.3
--   low         0             7.5
--   headphones  0             15.0
local ICON_WIDTH = 15

-- フォントサイズは、Wi-Fi や Bluetooth (18pt) より大きい。音量の字面は、同じ 18pt では他より小さく見えるため
-- (音量の high の字面の高さは 18pt で 13.1、Wi-Fi は 13.9、Bluetooth は 15.0)。
local FONT_SIZE = 20.0

-- 字面の縦の中心 (ベースラインからの高さ) は、20pt で 6.94 (Propo でも同じ。どの字面も同じ)、Wi-Fi や Bluetooth は 18pt で 6.25。
-- 他は y_offset = 1 なので、差の 0.69 を引いて 0.31 になり、整数に切り捨てて 0 にする。
local Y_OFFSET = 0

local HEADPHONES = { icon = "󰋋" } -- nf-md-headphones

-- 音量が (上限 %, 字面) の段階。上から順に見て、最初に音量が上限以下になったものを使う
local LEVELS = {
	{ max = 0, icon = "󰖁" }, -- nf-md-volume_off
	{ max = 33, icon = "󰕿" }, -- nf-md-volume_low
	{ max = 66, icon = "󰖀" }, -- nf-md-volume_medium
	{ max = 100, icon = "󰕾" }, -- nf-md-volume_high
}

-- mute の字面は、音量 0 と同じ
local MUTED = LEVELS[1]

-- 出力先の名前 (小文字にしたもの) に含まれる文字 -> 専用の字面。上から順に見て、最初に一致したものを使う。
-- Hack Nerd Font にイヤホンの字面は無いので、Beats もヘッドホンと同じ字面にしている。
-- 他のデバイスを足すときは、SwitchAudioSource -a -t output で名前を確認する。
local DEVICES = {
	{ match = "beats", glyph = HEADPHONES },
	{ match = "headphone", glyph = HEADPHONES },
	{ match = "headset", glyph = HEADPHONES },
	{ match = "ヘッドフォン", glyph = HEADPHONES }, -- 有線のヘッドホン (内蔵の出力として現れる)
	{ match = "ヘッドホン", glyph = HEADPHONES },
}

-- スクロールで音量を変える。トラックパッドは 1 回のスワイプで多数のイベントが出る (慣性スクロール含む) ので、
-- イベントごとには変えず、スクロールの量 (delta) を足し合わせて、SCROLL_THRESHOLD に達するごとに
-- 音量キー 1 回分だけ変える。音量キーを合成して送る (media-key, pkgs/media-key) ので、標準の音量ポップアップが出る。
-- 音量キー 1 回は音量の 1/16 (約 6%)、option を押している間 (fine) は 1/64 (約 1.6%)。調整するのは次の 2 つ:
--   SCROLL_THRESHOLD: 音量キー 1 回に必要なスクロールの量。大きいほど鈍くなる
--   SCROLL_IDLE: この秒数スクロールが止まったら、足し合わせた量を捨てる (次の操作に持ち越さない)
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

-- 出力先と、音量・mute の状態を読む。音量を持たない出力 (HDMI など) は "missing value" になる。
local COMMAND = [[
echo "device=$(SwitchAudioSource -c -t output)"
osascript -e 'set s to get volume settings' -e 'return "vol=" & (output volume of s as text) & linefeed & "muted=" & (output muted of s as text)'
]]

-- mute は音量を変えず、mute 中も volume_change が届くとは限らない (実機で未確認) ので、
-- 数秒おきの更新 (update_freq) でも拾う。状態が前回と同じなら何もしない。
local current

-- mute > 専用の出力先 > 音量の段階、の順に字面を決める
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

	-- 音量が取れない出力は、最大の段階として扱う
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

volume:subscribe({ "volume_change", "system_woke", "routine", "forced" }, update)
update()

-- mute キーを合成して送る (スクロールと同じく、標準のポップアップが出る)
local function toggle_mute()
	sbar.exec("media-key mute", update)
end

-- delta はスクロールの量 (向きは符号)。範囲外は OS が収める。
-- 音量を設定すると、同じ値でも mute が解除される (実機で確認)。トラックパッドの右クリック (2 本指) は、
-- クリックの直前に量 0 のスクロールが届くと推測している (音量が変わらないまま mute だけ解除されていた) ので、
-- 目盛りに達するまでは音量を設定しない。
-- 何もしないと、mute 中の右クリックが、スクロールで解除された後にクリックで mute し直してしまう。
-- 積算の仕組みは ui.scroll_accumulator。fine は scroll の 2 番目の引数で、そのまま渡る。
local scroll = ui.scroll_accumulator(SCROLL_THRESHOLD, SCROLL_IDLE, function(sign, ticks, fine)
	sbar.exec(string.format("media-key %s %d%s", sign > 0 and "up" or "down", ticks, fine and " fine" or ""), update)
end)

-- bracket と、クリックを受ける領域は、items/network.lua が作る (Wi-Fi、Bluetooth とまとめて 1 つの bracket にする)
return {
	item = volume,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "サウンド", -- システム設定のウィンドウのタイトルに含まれる文字 (ui.toggle_settings)。表示言語に依存する
	toggle_mute = toggle_mute,
	scroll = scroll,
}
