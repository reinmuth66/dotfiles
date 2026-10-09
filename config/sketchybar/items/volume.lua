local ui = require("ui")

-- アイコンの箱の幅 (padding を含む全幅)。字面は箱の外にはみ出すと見切れるので、字面の最大幅
-- (実測 13.5。advance は 10.8 しかない) を切り上げた値にする。
-- 字面は箱の左端 + padding_left + 字面の左端のずれから描かれるので (bluetooth.lua と同じ)、
-- 字面ごとの padding_left で、箱の中の中央に寄せる。
-- 実測値 (Hack Nerd Font Bold 18pt、CoreText): フォントやサイズを変えたら再測定が必要。
--   mute / high / headphones: 幅 13.5、左端のずれ 0   -> pad 0
--   low:                      幅 6.8、左端のずれ 2.0   -> pad 1.5
--   medium:                   幅 10.1、左端のずれ 0.4  -> pad 1.5
local ICON_WIDTH = 14

local MUTED = { icon = "󰖁", pad = 0 } -- nf-md-volume_off
local HEADPHONES = { icon = "󰋋", pad = 0 } -- nf-md-headphones

-- 音量が (上限 %, 字面) の段階。上から順に見て、最初に音量が上限以下になったものを使う
local LEVELS = {
	{ max = 0, icon = "󰖁", pad = 0 }, -- nf-md-volume_off
	{ max = 33, icon = "󰕿", pad = 1.5 }, -- nf-md-volume_low
	{ max = 66, icon = "󰖀", pad = 1.5 }, -- nf-md-volume_medium
	{ max = 100, icon = "󰕾", pad = 0 }, -- nf-md-volume_high
}

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

-- 音量を 1 目盛りで変える量 (%)。ctrl を押している間は細かく変える
local SCROLL_STEP = 10
local SCROLL_STEP_FINE = 1

local SETTINGS_URL = "x-apple.systempreferences:com.apple.Sound-Settings.extension"

local volume = ui.add_item("volume", "right", {
	update_freq = 5,
	icon = {
		font = { size = 18.0 },
		y_offset = 1,
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

		volume:set({ icon = { string = glyph.icon, padding_left = glyph.pad } })
	end)
end

volume:subscribe({ "volume_change", "system_woke", "routine", "forced" }, update)
update()

local function toggle_mute()
	sbar.exec("osascript -e 'set volume output muted not (output muted of (get volume settings))'", update)
end

-- delta はスクロールの量 (向きは符号)。範囲外は osascript が収める
local function scroll(delta, fine)
	local step = delta * (fine and SCROLL_STEP_FINE or SCROLL_STEP)
	sbar.exec(
		string.format(
			"osascript -e 'set volume output volume ((output volume of (get volume settings)) + (%d))'",
			math.floor(step + 0.5)
		),
		update
	)
end

-- bracket と、クリックを受ける領域は、items/network.lua が作る (Wi-Fi、Bluetooth とまとめて 1 つの bracket にする)
return {
	item = volume,
	icon_width = ICON_WIDTH,
	settings_url = SETTINGS_URL,
	title_pattern = "サウンド", -- システム設定のウィンドウのタイトルに含まれる文字 (ui.toggle_settings)。表示言語に依存する
	toggle_mute = toggle_mute,
	scroll = scroll,
}
