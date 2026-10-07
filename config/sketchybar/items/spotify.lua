-- Spotify のアルバム画像を表示し、再生状態を明るさと回転で示す。
--   再生中  : 覆いを外して明るくし、画像をゆっくり回す
--   一時停止: 画像を暗くし、回転はその角度で止める
--   未起動・停止中: 画像の代わりに Spotify のアイコンを出す (アイテム自体は常に表示)
--   切り替え時は覆いの濃さを滑らかに変える
-- 状態は Spotify の分散通知 (media_change は macOS 26 で発火しない) から受け取り、
-- 画像は osascript の artwork url から取得し、キャッシュする (キャッシュの設計は load_artwork の付近を参照)。
-- ポップアップの再生位置は、通知の Playback Position を基準に、ローカルの時計で進める
-- (毎秒の osascript の取得は行わない。詳しくは再生位置の節を参照)。
-- 回転は background.image.rotation を使う (SketchyBar#815 のパッチが前提、pkgs/sketchybar/)。
-- 操作: 左クリックで再生/一時停止、上スクロールで前の曲、下スクロールで次の曲。
-- マウスを乗せると、カバー画像と、曲名・アーティスト・アルバム・再生位置をポップアップで表示する
-- (配置は FelixKratz/dotfiles の spotify ウィジェットを参考にした。表示のみで、ボタンは持たない)。
-- カバー画像の下に「経過時間 / 総時間」を出し、曲情報の下に、再生位置のバーと、その上に再生中の音に合わせて
-- 動く棒グラフを出す。棒グラフは cava の SDL の窓が、ポップアップの背景と枠と一緒に描く。窓はポップアップ全体に
-- 重ねて、ポップアップの下 (window level 100。ポップアップは 101) に敷く。ポップアップ自身の背景は、窓が出ている間
-- 透明にして、文字、カバー画像、再生位置のバーが棒グラフの上に描かれるようにする。
-- 再生中にホバーすると、ポップアップをすぐ開きながら cava を隠して起動し、
-- ポップアップのアニメーションの終わりと cava の準備完了に合わせて窓を出す (modules/cavaviz.nix、pkgs/cavaviz/ を参照)。
-- ポップアップの色 (背景、枠、文字、再生位置のバー、棒グラフ) は、アルバム画像の代表色から決める (palette.lua)。
-- ポップアップを開くときは、フェードインと、上から下ろす動きをつける (popup_look。棒グラフの窓は対象外)。
-- 色の頻度表は画像と同じ所にキャッシュし (.colors)、棒グラフの色は動いている cava に SIGUSR2 で伝える。
-- マウス操作は、bracket 全体を覆う透明な item (hit) が受ける。画像の item は再描画が多く、
-- マウスを購読させると mouse.exited が届かずポップアップが閉じなくなることがあるため (ui.add_hit_layer)。

local ui = require("ui")
local colors = require("colors")
local palette = require("palette")

local SIZE = 24 -- 表示サイズ (pt)。アイコンのフォントサイズも同じ値にする (このフォントでは字面が一辺 SIZE の正方形になる)
local ART_PX = SIZE * 4 -- キャッシュする画像の一辺 (px)
local CACHE_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/spotify"

-- ポップアップの配置 (pt)。見た目は実機で確認して調整する。
-- 左から 余白 | カバー画像 | 余白 | 文字の領域 (TEXT_WIDTH) | 余白 の順に並べる。
-- 縦は、左の列がカバー画像 + 経過時間 / 総時間、右の列が 曲名・アーティスト・アルバム + 棒グラフ + 再生位置のバー。
-- y_offset は、ポップアップの縦の中央からの距離 (上が正)。
local COVER_SIZE = 72
local COVER_PX = COVER_SIZE * 4 -- ポップアップ用に、アイコン用 (ART_PX) とは別に大きい画像をキャッシュする
local POPUP_PADDING = 12
-- ポップアップは、内蔵ディスプレイの画面の中央 (855 pt) に中心が来るようにする。ポップアップは左端 (実測で 714 pt。
-- bracket の左端と同じ) から右へ伸びるので、幅 = 2 * (855 - 714) = 282 pt。幅は 111 + TEXT_WIDTH (POPUP_BG_WIDTH) なので、
-- TEXT_WIDTH = 171。ノッチとの間隔 (ui.notch_gap)、notch_width、SIZE、POPUP_PADDING、COVER_SIZE を変えたときは、
-- ポップアップの左端を実測し直して、この値を計算し直す (spotify.cover の bounding_rects の x - POPUP_PADDING が左端)。
-- 画面の中央からずれるのは、内蔵ディスプレイ以外 (ノッチがない外部ディスプレイ) では item の位置が変わるため。
local TEXT_WIDTH = 171
local TIME_GAP = 3 -- カバー画像と、その下の時刻の間 (pt)
local TIME_ROW_HEIGHT = 13 -- 時刻の行の高さ (pt)
local CONTENT_HEIGHT = COVER_SIZE + 2 * colors.popup.border_width + TIME_GAP + TIME_ROW_HEIGHT -- 左の列の高さ (偶数にする)
local POPUP_HEIGHT = CONTENT_HEIGHT + 2 * POPUP_PADDING
local CONTENT_TOP = math.floor(CONTENT_HEIGHT / 2) -- 中央から見た、左の列の上端
-- 時刻の行と、再生位置のバーは、左の列の下端に高さをそろえる (行の中央)
local BOTTOM_ROW_Y = -(CONTENT_TOP - math.floor(TIME_ROW_HEIGHT / 2))
-- 再生位置のバーは、時刻をカバー画像の下に出す分、文字の領域の全幅に伸ばす
local SLIDER_WIDTH = TEXT_WIDTH

-- サウンドビジュアライザ (棒グラフ)。cava の窓はポップアップの背景全体 (POPUP_BG_WIDTH x POPUP_BG_HEIGHT) と同じ位置と大きさで、
-- 背景、枠、棒グラフを描く。棒は文字の領域と同じ幅で、再生位置のバーのすぐ上から、ポップアップの上の余白の手前
-- (左の列の上端、CONTENT_TOP) まで伸びて、曲名などの文字の下にも入る (文字は SketchyBar が窓の上に描く)。
-- 棒の領域の下端は、バー (高さ 4) の上端の 1pt 上。上端と下端は、ポップアップの縦の中央からの距離 (上が正)。
-- ポップアップの背景は、中身 (POPUP_HEIGHT の高さの帯) の左端から始まり、右と上下に枠の太さの分だけ広がる
-- (左は広がらない。SketchyBar の popup.c の popup_calculate_bounds)。
-- 棒の領域の位置と大きさ (窓の左上から VIZ_LEFT, VIZ_Y, VIZ_WIDTH, VIZ_HEIGHT)、角の半径 (colors.popup)、
-- 枠の太さは、pkgs/cavaviz/popup.frag の定数と同じ値にする。
-- 設定 (棒の数、感度など) は modules/cavaviz.nix。ここでは窓の位置と大きさだけを決める。
local POPUP_BORDER = colors.popup.border_width
local POPUP_BG_WIDTH = 3 * POPUP_PADDING + COVER_SIZE + 2 * POPUP_BORDER + TEXT_WIDTH + POPUP_BORDER -- 中身の幅 (カバー画像の枠も含む) + 右の枠
local POPUP_BG_HEIGHT = POPUP_HEIGHT + 2 * POPUP_BORDER
local VIZ_LEFT = 2 * POPUP_BORDER + 2 * POPUP_PADDING + COVER_SIZE
local VIZ_WIDTH = TEXT_WIDTH
local VIZ_TOP = CONTENT_TOP
local VIZ_BOTTOM = BOTTOM_ROW_Y + 2 + 1
local VIZ_HEIGHT = VIZ_TOP - VIZ_BOTTOM
local VIZ_Y = POPUP_BG_HEIGHT / 2 - VIZ_TOP
local VIZ_APP = os.getenv("HOME") .. "/Applications/Home Manager Apps/CavaViz.app"
local VIZ_CONFIG_HOME = os.getenv("HOME") .. "/.config/cavaviz"
local VIZ_TEMPLATE = VIZ_CONFIG_HOME .. "/config.template"
local VIZ_RUNTIME_DIR = os.getenv("HOME") .. "/Library/Caches/sketchybar/cavaviz"
local VIZ_CONFIG = VIZ_RUNTIME_DIR .. "/config"
local VIZ_LOG = VIZ_RUNTIME_DIR .. "/stderr.log"
local VIZ_SLOT_RETRIES = 20 -- ポップアップが描かれて、空きの位置が取れるまで待つ回数
local VIZ_SLOT_INTERVAL = 0.05 -- その間隔 (秒)
local VIZ_KILL_AGAIN = 0.6 -- 起動の直後に止めたとき、遅れて起動した窓を止め直すまでの秒数 (open は約 0.3 秒かかる)
local VIZ_CONTROL = os.getenv("HOME") .. "/Library/Caches/sketchybar/cavaviz/control"
-- パターンの先頭を [C] にして、この pkill を実行するシェル自身 (コマンドラインにパターンを含む) に一致させない
local VIZ_STOP = "pkill -f '[C]avaViz.app/Contents/MacOS/cava'"
-- cava の準備ができたことを知るためのイベント。cava が、描画ループの最初に sketchybar --trigger で送る
-- (ID=起動の番号つき。CAVAVIZ_READY_BIN / CAVAVIZ_READY_EVENT / CAVAVIZ_READY_ID で渡す)。
local VIZ_READY_EVENT = "cavaviz_ready"
local VIZ_WAIT_TIMEOUT = 1.5 -- 準備ができなくても、棒グラフの窓はこの秒数で出す (指示だけ出す)
local VIZ_HIDDEN_POS = -3000 -- 準備ができるまで窓を置いておく画面外の位置
-- 窓を出す指示を出してから、ポップアップ自身の背景を透明にする (窓に背景を描かせる) までの秒数。窓が実際に出る
-- (指示のファイルへの書き込みと、窓の不透明度の反映) より後にする。それまでは、窓は不透明なポップアップの背景に隠れている
-- (配色は不透明なので、窓と背景が重なっていても見た目は変わらない)。
local VIZ_HANDOVER_DELAY = 0.1

-- bracket は円にする。幅を高さ (colors.bracket.height) と同じにし、角の半径は短辺の半分以上にする
-- (背景の描画側で短辺の半分に丸められる)。左右の padding は、円の中に画像が同心で収まる値。
local BRACKET_PADDING = (colors.bracket.height - SIZE) / 2

-- 回転: TICK 秒ごとに、角度を ROTATION_STEP だけ進める。1 周が ROTATION_PERIOD 秒になる。
-- 再生位置の表示 (秒) も同じ周で 1 つ進める (秒の切り替わりと回転が同じタイミングで変わる)。
-- 負の値は rotation を減らす向き (見た目の向きはこの符号で決まる)。
local ROTATION_PERIOD = 60
local TICK = 1 -- 表示の秒を 1 周で 1 つ進めるので、1 秒にする
local ROTATION_STEP = -360 * TICK / ROTATION_PERIOD

-- 画像に重ねる覆いの色 (ARGB)。alpha が 0x00 で透明、0xff で真っ黒
local PAUSED_COLOR = 0x99000000
local PLAYING_COLOR = 0x00000000
local FADE_FRAMES = 12 -- 再生/一時停止の切り替えにかけるフレーム数 (60 フレームで 1 秒)

-- ノッチとの間隔は spacer で作る (補正の内訳は ui.add_notch_spacer)。ノッチに最も近い位置に置くので、spotify より先に追加する。
ui.add_notch_spacer("q", "spotify.notch_gap")

-- ノッチの左隣 (position "q") に置く。常に表示する。曲がない間 (未起動・停止中) は Spotify のアイコン、再生中・一時停止中は
-- アルバム画像を出す。初期状態はアイコン側 (画像と覆いは非表示)。
local spotify = ui.add_item("spotify", "q", {
	width = SIZE,
	update_freq = 5, -- 画像を出している間の、Spotify 終了の確認 (routine) に使う
	-- icon.width は padding を含む箱の全幅 (SketchyBar v2.24.0 の text.c で確認)。
	-- 字面は箱の左端 + padding_left から描かれ、箱の外にはみ出した部分は描画されず見切れる。
	-- 中央揃え (align = center) だと、字面の幅 (17pt に切り上げ) との差を整数で割るため、
	-- 左右 padding が 0 では 1pt 左に寄る。左揃えにして padding_left で位置を直接指定し、
	-- 箱は SIZE のままにして、字面が箱の中の中央に収まるようにする。
	icon = {
		string = ":spotify:",
		font = "sketchybar-app-font:Regular:" .. SIZE .. ".0",
		color = 0x99ffffff, -- 起動していないことが分かるよう、少し薄くする
		width = SIZE,
		align = "left",
		padding_left = 0, -- 字面は箱と同じ大きさなので、余白はいらない
		padding_right = 0,
	},
	-- 画像を暗くするための覆い。画像の背景より後に描かれるラベルの背景を、画像と同じ大きさで重ねる
	label = {
		drawing = false,
		string = "",
		width = SIZE,
		padding_left = 0,
		padding_right = 0,
		background = {
			drawing = true,
			color = PAUSED_COLOR,
			height = SIZE,
			corner_radius = SIZE / 2,
		},
	},
	background = {
		drawing = true,
		color = 0x00000000,
		image = {
			drawing = false,
			scale = SIZE / ART_PX,
			corner_radius = SIZE / 2,
		},
	},
	popup = {
		align = "left",
		horizontal = true,
		height = POPUP_HEIGHT,
		background = colors.popup,
	},
})

local bracket = ui.add_bracket("spotify.bracket", { spotify }, {
	background = { color = 0xff000000, corner_radius = colors.bracket.height / 2 },
}, BRACKET_PADDING)

-- bracket の範囲 (spotify の幅 + 左右の padding) 全体でマウス操作を受ける
local hit = ui.add_hit_layer("spotify.hit", SIZE, BRACKET_PADDING, { position = "q" })

-- ポップアップの中身。横に追加順で並ぶ: カバー画像 | 文字の領域。
-- 文字の領域は、曲名・アーティスト・アルバム・再生位置の item を width = 0 にして同じ x から
-- y_offset で縦にずらして重ね、その右に TEXT_WIDTH の空き (spotify.viz) を置いて幅を確保する。
-- 空の項目 (ポッドキャストのアーティストなど) は非表示にする (その行は空く)。
-- 文字は ui.popup_font (メニューバーと同じシステムフォント) で、size と color だけ行ごとに変える。
local popup_font = ui.popup_font

local function add_popup_spacer(name, width)
	return sbar.add("item", name, {
		position = "popup.spotify",
		width = width,
		padding_left = 0,
		padding_right = 0,
		icon = { drawing = false },
		label = { drawing = false },
	})
end

add_popup_spacer("spotify.pad.left", POPUP_PADDING)

-- 画像の表示サイズは 実ピクセル * scale (アイコンと同じ)。画像は取得できてから出す。
-- 枠線はポップアップの枠 (colors.popup) と同じ色と太さで、画像の外側にくっつける。
-- item の背景を画像より枠線の太さの 2 倍だけ大きくし、その枠線 (図形の内側に引かれる) を外周の
-- 1 本分に置く。画像は背景の左端から枠線の太さだけ内側 (image.padding_left)、縦は中央に描かれるので、
-- 枠線と画像は重ならない。item の幅 (COVER_BOX) は画像より枠線の分だけ広い。
local COVER_RADIUS = 6
local COVER_BORDER = colors.popup.border_width
local COVER_BOX = COVER_SIZE + 2 * COVER_BORDER

-- 経過時間 / 総時間: カバー画像の下の中央。width = 0 の item を画像の直前に置き、画像と同じ x から描く。
-- 時刻は等幅数字 (tnum) にして、秒が変わっても幅を変えない。
local time_text = sbar.add("item", "spotify.time.text", {
	position = "popup.spotify",
	width = 0,
	y_offset = BOTTOM_ROW_Y,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = {
		string = "00:00 / 00:00",
		font = popup_font(10.0, "tnum"),
		width = COVER_BOX,
		align = "center",
		padding_left = 0,
		padding_right = 0,
	},
})

local cover = sbar.add("item", "spotify.cover", {
	position = "popup.spotify",
	width = COVER_BOX,
	y_offset = CONTENT_TOP - math.floor(COVER_BOX / 2),
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	-- 開くときのフェードインで画像を隠す覆い。画像に alpha は指定できないので、画像の背景より後に
	-- 描かれるラベルの背景を、枠線を含む全体 (COVER_BOX) に重ねる。色は popup_look が決める (普段は透明)
	label = {
		string = "",
		width = COVER_BOX,
		padding_left = 0,
		padding_right = 0,
		background = {
			drawing = true,
			color = 0x00000000,
			height = COVER_BOX,
			corner_radius = COVER_RADIUS + COVER_BORDER,
		},
	},
	background = {
		drawing = true,
		color = 0x00000000,
		height = COVER_BOX,
		corner_radius = COVER_RADIUS + COVER_BORDER, -- 画像の角 (COVER_RADIUS) と同心になる
		border_width = COVER_BORDER,
		border_color = colors.popup.border_color,
		image = {
			drawing = false,
			scale = COVER_SIZE / COVER_PX,
			corner_radius = COVER_RADIUS,
			padding_left = COVER_BORDER,
		},
	},
})

add_popup_spacer("spotify.pad.cover", POPUP_PADDING)

-- 文字は幅 (TEXT_WIDTH) に収まる所で切る。幅は文字ごとの em 換算の見積もりで測る (truncate を参照)。
-- 行ごとの文字数は固定せず、size から決まる。
local ROWS = {
	{ key = "title", size = 14.0, y_offset = CONTENT_TOP - 9 },
	{ key = "artist", size = 12.0, y_offset = CONTENT_TOP - 29 },
	{ key = "album", size = 11.0, y_offset = CONTENT_TOP - 46, color = 0xffaaaaaa },
}

local rows = {}
for _, row in ipairs(ROWS) do
	rows[row.key] = {
		size = row.size,
		item = sbar.add("item", "spotify." .. row.key, {
			position = "popup.spotify",
			drawing = false,
			width = 0,
			y_offset = row.y_offset,
			padding_left = 0,
			padding_right = 0,
			icon = { drawing = false },
			label = {
				font = popup_font(row.size),
				color = row.color,
				padding_left = 0,
				padding_right = 0,
			},
		}),
	}
end

-- 再生位置のバー。文字の領域の全幅に伸ばし、高さは時刻の行にそろえる。バーは表示だけ (操作は受けない)。
-- 時刻は、カバー画像の下 (time_text)。秒の更新は、アルバム画像の回転と同じ周 (回転ループ) で進める
-- (step_time の付近)。
local time = sbar.add("slider", "spotify.time", SLIDER_WIDTH, {
	position = "popup.spotify",
	width = 0,
	y_offset = BOTTOM_ROW_Y,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = { drawing = false },
	slider = {
		percentage = 0,
		highlight_color = colors.white,
		background = { height = 4, corner_radius = 2, color = 0xff444444 },
	},
})

-- 棒グラフの領域に当たる空き。幅は TEXT_WIDTH で、文字の領域の右の端まで広げて幅を確保する
-- (曲名などの item は width = 0 なので、この空きが文字の領域の幅になる)。ビジュアライザの窓の位置の基準で、
-- sketchybar --query の bounding_rects で取る。矩形は、popup の高さいっぱいの帯になる (y_offset は含まれない)。
-- 何も描かない item だと位置が取れない可能性があるので、透明な背景を持たせる。
sbar.add("item", "spotify.viz", {
	position = "popup.spotify",
	width = TEXT_WIDTH,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = { drawing = false },
	background = { drawing = true, color = 0x00000000 },
})

add_popup_spacer("spotify.pad.right", POPUP_PADDING)

-- 文字の幅 (em 換算)。メニューバーと同じシステムフォント Bold を、12pt で CoreText が測った値 (ASCII の 1 文字ごと)。
-- 全角 (かな・漢字など) は一律 0.923、ASCII 以外の半角 (アクセント付きの文字、キリル文字など) は平均の EM_OTHER にする。
-- 注意: このフォントは文字の間隔が大きさで変わり (小さいほど広い。11pt は 12pt より約 1%、14pt は約 2% 狭い)、
-- 100pt などの大きな値で測ると、実際の表示 (11〜14pt) より 1 割以上狭く出る。必ず表示と同じ大きさ付近で測ること。
-- 曲名・アーティスト名のサンプル 38 件で、実測 (11、12、14pt) との差は -3.9%〜+4.8% (平均 -0.2%〜+2.3%)。
-- 過小な見積もりの分は TEXT_MARGIN で吸収する。
local EM_WIDE = 0.923 -- 全角 (かな・漢字・ハングル・全角記号など)
local EM_OTHER = 0.6 -- ASCII 以外の半角
local EM_REF_SIZE = 12 -- 表を測った大きさ (pt)
local EM_PER_PT = 0.01 -- 大きさが 1pt 小さいと、幅が増える割合
local EM_ASCII = { -- 0x20 (空白) から 0x7E (~) まで
	0.258, 0.356, 0.569, 0.671, 0.671, 1.036, 0.744, 0.348,
	0.429, 0.429, 0.484, 0.671, 0.348, 0.484, 0.348, 0.334,
	0.685, 0.512, 0.643, 0.669, 0.687, 0.663, 0.684, 0.604,
	0.694, 0.684, 0.348, 0.348, 0.671, 0.671, 0.671, 0.557,
	0.927, 0.732, 0.693, 0.741, 0.747, 0.622, 0.597, 0.760,
	0.783, 0.318, 0.601, 0.709, 0.595, 0.906, 0.768, 0.786,
	0.674, 0.786, 0.694, 0.675, 0.660, 0.760, 0.721, 1.009,
	0.729, 0.708, 0.676, 0.375, 0.334, 0.375, 0.671, 0.627,
	0.500, 0.590, 0.651, 0.587, 0.651, 0.601, 0.408, 0.645,
	0.632, 0.287, 0.287, 0.601, 0.295, 0.932, 0.627, 0.620,
	0.647, 0.647, 0.435, 0.566, 0.413, 0.627, 0.583, 0.847,
	0.581, 0.597, 0.566, 0.429, 0.299, 0.429, 0.671,
}
local EM_ELLIPSIS = 3 * EM_ASCII[string.byte(".") - 31]
local TEXT_MARGIN = 8 -- 見積もりの誤差 (過小に見積もる最大 約 4%) の分、TEXT_WIDTH から引く (pt)

local function char_em(code)
	if code >= 0x2E80 then
		return EM_WIDE
	end
	return EM_ASCII[code - 31] or EM_OTHER
end

-- 長い文字列は、size (pt) の文字が TEXT_WIDTH に収まる所で切って "..." を付ける
-- (utf8.len が nil なら不正なバイト列なのでそのまま使う)
local function truncate(text, size)
	if utf8.len(text) == nil then
		return text
	end
	-- 大きさが基準 (EM_REF_SIZE) と違う分の、間隔の変化を補正する (size が小さいほど、1em あたりの幅が広い)
	local limit = (TEXT_WIDTH - TEXT_MARGIN) / size / (1 + EM_PER_PT * (EM_REF_SIZE - size))
	local total = 0
	local cut = 1 -- "..." を付けても収まる、最後の切れ目 (バイト位置)
	for pos, code in utf8.codes(text) do
		if total + EM_ELLIPSIS <= limit then
			cut = pos
		end
		total = total + char_em(code)
	end
	if total <= limit then
		return text
	end
	return (text:sub(1, cut - 1):gsub("%s+$", "")) .. "..."
end

local function set_popup_info(meta)
	for key, row in pairs(rows) do
		local text = meta[key]
		if type(text) ~= "string" then
			text = ""
		end
		row.item:set({ drawing = text ~= "", label = { string = truncate(text, row.size) } })
	end
end

-- 再生位置の表示は、回転ループの 1 周ごとに 1 秒進める (ローカルの時計)。回転も同じ周で進むので、
-- 秒の切り替わりと回転は同じタイミングになる。
-- 実際の位置は、分散通知の Playback Position と、ホバーで開いたときの osascript の取得で合わせる。
-- 通知は一時停止・再開・曲の切り替えで来るが、シークでは来ない (実機で確認)。
-- そのため、ポップアップを閉じている間のシークは、開いた瞬間の取得で直る。
-- 開いている間のシークは、次の通知か開き直しまで直らない。毎秒の osascript の取得は行わない。
-- 秒の進みは、位置の見積もりとは切り離す。見積もりが表示に追いつくのを待つ作りだと、補正が続くとき
-- (素早いホバーの繰り返しなど) に、秒も回転も止まってしまう。
local shown = nil -- 表示している秒 (整数)。nil なら、まだ位置が分かっていない
local duration = 0 -- 曲の長さ (秒)
local popup_open = false
local viz_start, viz_stop, viz_wait -- サウンドビジュアライザの制御 (spinning の宣言のあとで定義する)
local viz -- サウンドビジュアライザの状態 (同じく、あとで定義する)
local open_id = 0 -- ポップアップを開くたびに増やす番号。古い取得の結果で、別の開き直しのポップアップを開かないための印
local SNAP_BACK = 1.5 -- 実際の位置が表示より後ろへこの秒数以上ずれていたら、表示も戻して合わせる

-- 分も 0 埋めの 2 桁 (mm:ss) にして、桁数が増えて幅が変わらないようにする。
-- 100 分以上は 3 桁になり、時刻の行 (COVER_BOX) を超えて見切れる。
local function format_time(seconds)
	return string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- animated が false なら、バーを滑らかに動かさず、すぐ合わせる (開く瞬間に、古い位置から伸びないように)
local function render(animated)
	if shown == nil or duration <= 0 then
		return
	end
	local function set_values()
		time_text:set({ label = { string = format_time(shown) .. " / " .. format_time(duration) } })
		time:set({ slider = { percentage = math.min(100, shown / duration * 100) } })
	end
	if animated == false then
		set_values()
	else
		sbar.animate("linear", 10, set_values)
	end
end

-- 実際の位置 (秒、小数) に合わせる。duration は秒 (nil なら前の値のまま)。
-- 再生中の小さな補正では、表示を戻さない: 実際の位置が表示より前なら進めて合わせ、
-- 後ろへ SNAP_BACK 秒未満のずれなら、そのまま進める (数字が戻らないようにする)。
-- 一時停止中、曲の切り替え (force)、ポップアップを閉じている間は、そのまま合わせる。
-- animated は render に渡す (false なら、バーを滑らかに動かさずすぐ合わせる)
local function rebase(position, new_duration, playing, force, animated)
	duration = new_duration or duration
	if shown == nil or force or not playing or not popup_open or position >= shown or position < shown - SNAP_BACK then
		shown = math.floor(position)
	end
	if popup_open then
		render(animated)
	end
end

-- 回転ループの 1 周ごとに呼ぶ。表示する秒を 1 つ進める (曲の長さを超えない)。
local function step_time()
	if shown == nil or shown >= math.floor(duration) then
		return
	end
	shown = shown + 1
	if popup_open then
		render()
	end
end

-- 状態と位置と曲の長さ (ミリ秒) をタブ区切りで返す。未起動の Spotify を起動しないよう pgrep で確認する。
local POSITION_COMMAND =
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & tab & (player position as text) & tab & (duration of current track as text)' 2>/dev/null]]

-- ロケールによっては、位置の小数点がカンマになる
local function parse_position(text)
	return tonumber((text:gsub(",", ".")))
end

-- ホバーで開いたとき、実際の位置に合わせる (閉じている間のシークはここで直る)。
-- animated は rebase に渡す。結果の反映 (または失敗) のあとに、done を呼ぶ (nil でもよい)。
local function refresh_position(done, animated)
	sbar.exec(POSITION_COMMAND, function(out)
		if type(out) == "string" then
			local state, position, length = out:match("^(%a+)\t([%d.,]+)\t(%d+)")
			if state == "playing" or state == "paused" then
				position = parse_position(position)
				length = tonumber(length) / 1000
				if position and length > 0 then
					rebase(position, length, state == "playing", false, animated)
				end
			end
		end
		if done then
			done()
		end
	end)
end

-- ポップアップを開くときのアニメーション: 背景と枠は最初から不透明にして、文字、画像、バーだけを
-- フェードインさせながら、SLIDE_DISTANCE だけ上から定位置へ下ろす。ポップアップの窓全体の透明度は変えられないので、
-- item ごとに色の alpha と y_offset を動かす。開くたびに、隠した状態にしてから定位置へ動かす
-- 画像には alpha を指定できず、背景色の覆いで隠している。背景が透明なまま覆いだけが不透明だと、画像の位置に
-- 背景色の四角が浮いて見えるので、背景はフェードさせない (覆いは背景と同じ色になり、画像も文字と同じ質で現れる)。
-- 閉じるときは、逆向き (透明にしながら上へ戻す) に動かしてから閉じる (close_popup)。
-- 棒グラフ (cava の窓) は SketchyBar の外なので動かせない。アニメーションの終わりに合わせて出す (open_popup)。
local FADE_IN_FRAMES = 10 -- 60 フレームで 1 秒。再生中でない (棒グラフがない) ときの長さ
local FADE_OUT_FRAMES = 8 -- 閉じるときの長さ。待たされる感じがしないよう、開くときより短くする
local FADE_IN_FRAMES_VIZ = 24 -- 再生中の長さ。ホバーから cava の準備ができるまでの時間 (約 0.4 秒) に合わせる
local SLIDE_DISTANCE = 6 -- pt
local current_palette = palette.default -- 表示中の配色 (apply_palette が更新する)

local function with_alpha(color, alpha)
	return alpha * 0x1000000 + color % 0x1000000
end

-- slide_items: 中身の item と、その定位置の y_offset
local slide_items = {
	{ time_text, BOTTOM_ROW_Y },
	{ cover, CONTENT_TOP - math.floor(COVER_BOX / 2) },
	{ time, BOTTOM_ROW_Y },
}
for _, row in ipairs(ROWS) do
	slide_items[#slide_items + 1] = { rows[row.key].item, row.y_offset }
end

-- ポップアップ自身の背景と枠。棒グラフの窓が背景と枠を描いている間 (viz.drawing_bg) は、透明にする。
local function popup_background(p)
	if viz.drawing_bg then
		return { color = with_alpha(p.bg, 0), border_color = with_alpha(p.border, 0) }
	end
	return { color = p.bg, border_color = p.border }
end

-- visible が true なら配色と位置を定位置 (current_palette) に、false なら中身を隠した状態 (透明、上にずらす) にする。
-- 背景と枠は、どちらでも定位置の色のまま
local function popup_look(visible)
	local p = current_palette
	local function color(c)
		return visible and c or with_alpha(c, 0)
	end
	local dy = visible and 0 or SLIDE_DISTANCE
	spotify:set({ popup = { background = popup_background(p) } })
	cover:set({ label = { background = { color = visible and with_alpha(p.bg, 0) or p.bg } } })
	time_text:set({ label = { color = color(p.text) } })
	-- slider.background.color は、進んだ部分 (foreground) の色も同じ値に動かす (SketchyBar の slider.c)。
	-- アニメーション中は、あとから動かした highlight_color が勝つよう、必ずこの順に別の set で送る
	-- (1 つの set にまとめると、テーブルの順序しだいで進んだ部分が track の色になり、バーが見えなくなる)
	time:set({ slider = { background = { color = color(p.track) } } })
	time:set({ slider = { highlight_color = color(p.accent) } })
	rows.title.item:set({ label = { color = color(p.text) } })
	rows.artist.item:set({ label = { color = color(p.text) } })
	rows.album.item:set({ label = { color = color(p.subtext) } })
	for _, entry in ipairs(slide_items) do
		entry[1]:set({ y_offset = entry[2] + dy })
	end
end

local function popup_fade_in(frames)
	sbar.animate("sin", frames, function()
		popup_look(true)
	end)
end

local function popup_fade_out()
	sbar.animate("sin", FADE_OUT_FRAMES, function()
		popup_look(false)
	end)
end

local fading_out = false -- 閉じるアニメーションの途中 (close_popup が重ねて呼ばれても、やり直さない)
-- 右クリックでピン留めした状態。ピン留め中は、マウスが外れてもポップアップを閉じない (close_popup)。
-- もう一度右クリックすると外す。ピン留め中は bracket の枠線が白くなる。曲情報がなくなってポップアップが閉じるとき (show_icon) にも外す。
local pinned = false
local PINNED_BORDER_COLOR = 0xffffffff -- ピン留め中の bracket の枠線の色 (普段は colors.bracket.border_color)

-- ピン留めの状態を変え、bracket の枠線の色で示す
local function set_pinned(value)
	pinned = value
	bracket:set({ background = { border_color = value and PINNED_BORDER_COLOR or colors.bracket.border_color } })
end

-- ポップアップを開く。ホバーの瞬間にアニメーションを始め、実際の位置は取得できしだい、アニメーションなしで合わせる
-- (開いている間にバーが古い位置から伸びないように)。
-- 再生中は、同時に cava を隠して起動し (viz_wait)、棒グラフの窓を、アニメーションの終わりと cava の準備完了の
-- 遅いほうで出す。アニメーションは cava の準備にかかる時間 (FADE_IN_FRAMES_VIZ) に合わせてあるので、
-- ふつうは同時になる。
local function open_popup()
	popup_open = true
	fading_out = false
	open_id = open_id + 1
	local id = open_id
	local viz_done = true
	local animation_done = false
	local viz_shown = false

	local function show_viz()
		if viz_shown or not (viz_done and animation_done) or not popup_open or id ~= open_id then
			return
		end
		viz_shown = true
		viz_start()
	end

	viz_done = not viz_wait(function()
		viz_done = true
		show_viz()
	end)
	local frames = viz_done and FADE_IN_FRAMES or FADE_IN_FRAMES_VIZ

	render(false)
	popup_look(false)
	spotify:set({ popup = { drawing = true } })
	popup_fade_in(frames)
	sbar.delay(frames / 60, function()
		animation_done = true
		show_viz()
	end)
	-- 準備ができなくても (許可がなくて cava が起動できないときなど)、この秒数で窓を出す指示を出す
	sbar.delay(VIZ_WAIT_TIMEOUT, function()
		viz_done = true
		show_viz()
	end)
	refresh_position(nil, false)
end

-- ポップアップを閉じる。棒グラフの窓は、消え残りを避けるため、先に即座に隠す (窓は SketchyBar の外なのでフェードできない)。
-- ポップアップは、逆向きのアニメーションが終わってから閉じる。その間に開き直されたら (open_id が変わる) 閉じない。
-- mouse.exited と mouse.exited.global が続けて来ても、1 回だけ行う。ピン留め中は閉じない。
local function close_popup()
	if pinned then
		return
	end
	local was_open = popup_open
	popup_open = false
	-- 窓を隠す指示 (制御ファイルへの同期的な書き込み) を、アニメーションより先に出す
	viz_stop()
	if not was_open then
		if not fading_out then
			spotify:set({ popup = { drawing = false } })
		end
		return
	end
	fading_out = true
	local id = open_id
	popup_fade_out()
	sbar.delay(FADE_OUT_FRAMES / 60, function()
		if id == open_id and not popup_open then
			fading_out = false
			spotify:set({ popup = { drawing = false } })
		end
	end)
end

-- 回転ループ。停止 -> 再生が短時間で続いても古いループが残らないよう世代で管理する。
-- 停止しても角度は戻さず、次の再生は止まった角度から続ける。
-- 再生位置の表示 (秒) もこのループの同じ周で進める (回転と同じタイミングで変わる)。
local angle = 0
local spinning = false
local generation = 0

local function tick(id)
	if not spinning or id ~= generation then
		return
	end
	step_time()
	angle = (angle + ROTATION_STEP) % 360
	spotify:set({ background = { image = { rotation = angle } } })
	sbar.delay(TICK, function()
		tick(id)
	end)
end

local function set_spinning(on)
	if on == spinning then
		return
	end
	spinning = on
	generation = generation + 1
	if on then
		-- 開始の瞬間には進めず、1 周期待ってから最初のステップを進める。
		-- 瞬間に進めると、再生と停止を素早く繰り返したとき、そのたびに回転が進んでしまう。
		local id = generation
		sbar.delay(TICK, function()
			tick(id)
		end)
	end
end

-- 再生中は明るく、それ以外は暗くする。覆いの初期色は暗い側なので、最初の状態が暗いなら何もしない。
local lit = false

local function set_lit(on)
	if on == lit then
		return
	end
	lit = on
	local color = on and PLAYING_COLOR or PAUSED_COLOR
	sbar.animate("sin", FADE_FRAMES, function()
		spotify:set({ label = { background = { color = color } } })
	end)
end

-- サウンドビジュアライザ。cava の SDL の窓 (CavaViz.app) を、ポップアップ全体に重ねて、ポップアップの下に敷く。
-- 再生中のホバーで起動し (ポップアップを開くのと同時に viz_wait)、ホバーが外れる、または再生が止まったら止める
-- (停止中は何も描かないので、動かす意味がない)。窓は画面外に隠して準備しておき、アニメーションの終わりに出す。
-- 起動のたびに、窓の位置と大きさと配色を設定のひな形 (VIZ_TEMPLATE の @X@ @Y@ @W@ @H@ @FG@ @BG@ @BORDER@) に入れて、
-- キャッシュに書き出す。
-- 音声の取得 (Core Audio tap) の許可は CavaViz.app に付いているので、sketchybar の子プロセスにせず、
-- open で起動する (pkgs/cavaviz/default.nix を参照)。
-- viz.running: cava を起動した (起動の待ちを含む)。viz.ready: 準備完了のイベントが届いた。
-- viz.on_ready: 準備完了を待っている処理 (ポップアップを開く)。
-- viz.id: 起動の番号。位置の待ちや止め直しを取り消すのと、準備完了のイベントがどの起動のものかを見分けるのに使う。
-- viz.cache: 前回の窓の位置 (ポップアップより先に窓を出すのに使う)。
-- viz.fg, viz.bg, viz.border: 棒、ポップアップの背景、枠の色 ("#rrggbb"。アルバム画像から決める)。
-- viz.applied: cava の設定ファイルに入っている配色 (viz_look)。
-- viz.shown: 窓を出す指示を出した。viz.drawing_bg: 窓が背景と枠を描いていて、ポップアップ自身の背景は透明にしてある。
-- 窓が出ていないとき (許可がなくて cava が起動できないときなど) に背景を透明にすると、ポップアップの背景がなくなってしまうので、
-- 準備完了 (viz.ready) と窓を出す指示 (viz.shown) がそろってから、viz_take_background で透明にする。
local function hex(color)
	return string.format("#%06x", color % 0x1000000)
end

viz = {
	running = false,
	id = 0,
	cache = nil,
	ready = false,
	on_ready = nil,
	fg = palette.default.viz,
	bg = hex(palette.default.bg),
	border = hex(palette.default.border),
	applied = nil,
	shown = false,
	drawing_bg = false,
}

local function viz_look()
	return viz.fg .. viz.bg .. viz.border
end

-- 設定のひな形の @X@ などを置き換える sed の引数
local function viz_sed_args(x, y)
	return string.format(
		"-e 's/@X@/%d/' -e 's/@Y@/%d/' -e 's/@W@/%d/' -e 's/@H@/%d/' -e 's/@FG@/%s/' -e 's/@BG@/%s/' -e 's/@BORDER@/%s/'",
		x,
		y,
		POPUP_BG_WIDTH,
		POPUP_BG_HEIGHT,
		viz.fg,
		viz.bg,
		viz.border
	)
end

-- 空きの画面上の位置。ポップアップが描かれる前は、origin が (-9999, -9999) になる。
local function viz_slot()
	local rects = sbar.query("spotify.viz").bounding_rects
	for _, rect in pairs(rects or {}) do
		if rect.origin[1] >= 0 then
			return rect
		end
	end
	return nil
end

-- 窓の左上の位置 (ポップアップの背景の左上)。x は空き (棒の領域) の左端から VIZ_LEFT 戻った位置、
-- y は popup の縦の中央から POPUP_BG_HEIGHT の半分だけ上の位置。
-- ポップアップは半ポイント位置に描かれることがある (中央揃えで、項目の位置が x.5 のとき) ので、丸めずに小数のまま渡す。
local function viz_window_pos(rect)
	local x = rect.origin[1] - VIZ_LEFT
	local y = rect.origin[2] + rect.size[2] / 2 - POPUP_BG_HEIGHT / 2
	return x, y
end

-- 空きの位置が取れるまで待って (ポップアップが描かれるのを待つ)、found(x, y) を呼ぶ。
-- id が変わったら (停止された) 取り消す。取れないまま VIZ_SLOT_RETRIES 回で諦めたら、何もしない。
local function viz_find_slot(id, found, n)
	n = n or 0
	if id ~= viz.id then
		return
	end
	local rect = viz_slot()
	if rect then
		found(viz_window_pos(rect))
	elseif n < VIZ_SLOT_RETRIES then
		sbar.delay(VIZ_SLOT_INTERVAL, function()
			viz_find_slot(id, found, n + 1)
		end)
	end
end

-- 設定のひな形に位置 (画面外) を入れて書き出し、制御ファイルの初期値 (hide) を書いて、cava を起動する。
-- 制御ファイル ("show X Y" か "hide") は、起動後も窓の表示、移動、非表示の指示に使う。
local VIZ_START = [[
mkdir -p %q && sed %s %q > %q \
	&& printf %%s %q > %q \
	&& open -n -a %q --env XDG_CONFIG_HOME=%q --env CAVAVIZ_CONTROL=%q --env CAVAVIZ_READY_BIN="$(command -v sketchybar)" --env CAVAVIZ_READY_EVENT=%s --env CAVAVIZ_READY_ID=%d --stderr %q --args -p %q
]]

local function viz_launch(id)
	viz.applied = viz_look()
	sbar.exec(
		string.format(
			VIZ_START,
			VIZ_RUNTIME_DIR,
			viz_sed_args(VIZ_HIDDEN_POS, VIZ_HIDDEN_POS),
			VIZ_TEMPLATE,
			VIZ_CONFIG,
			"hide",
			VIZ_CONTROL,
			VIZ_APP,
			VIZ_CONFIG_HOME,
			VIZ_CONTROL,
			VIZ_READY_EVENT,
			id,
			VIZ_LOG,
			VIZ_CONFIG
		)
	)
end

-- 起動済みの cava の配色 (棒、背景、枠) を、viz.fg, viz.bg, viz.border に変える。設定ファイルを書き直して (一時ファイルに書いてから置き換え、
-- cava が書きかけを読まないようにする)、SIGUSR2 を送る。cava は SIGUSR2 でグラデーションの色だけを読み直す
-- (foreground / background は読み直さないので、色はグラデーションで指定している。窓も音声の取得も作り直さない)。cava が準備中 (ready の前) だと、シグナルの受け口がなく、終了させてしまうので、
-- 準備完了のイベントのあとに行う (そのとき viz.applied とのずれを直す)。
local VIZ_RECOLOR = [[
sed %s %q > %q \
	&& mv %q %q && pkill -USR2 -f '[C]avaViz.app/Contents/MacOS/cava'
]]

local function viz_apply_color()
	if not viz.running or not viz.ready or viz.applied == viz_look() then
		return
	end
	viz.applied = viz_look()
	local tmp = VIZ_CONFIG .. ".tmp"
	sbar.exec(
		string.format(
			VIZ_RECOLOR,
			viz_sed_args(VIZ_HIDDEN_POS, VIZ_HIDDEN_POS),
			VIZ_TEMPLATE,
			tmp,
			tmp,
			VIZ_CONFIG
		)
	)
end

-- 起動済みの cava に、窓の表示 (位置つき) を指示する
local function viz_control(text)
	sbar.exec(string.format("printf %%s %q > %q", text, VIZ_CONTROL))
end

-- ポップアップ自身の背景を透明にして、窓に背景と枠を描かせる。窓が出ていて (準備完了と、窓を出す指示がそろって)
-- いるときだけ行う。
local function viz_take_background()
	if viz.drawing_bg or not (viz.running and viz.ready and viz.shown) then
		return
	end
	viz.drawing_bg = true
	spotify:set({ popup = { background = popup_background(current_palette) } })
end

-- 窓を出す指示を出したあと、窓が実際に出るのを待って、背景を窓に任せる
local function viz_take_background_later(id)
	sbar.delay(VIZ_HANDOVER_DELAY, function()
		if id == viz.id then
			viz_take_background()
		end
	end)
end

-- 起動済みの cava の窓を、ポップアップに重ねる。
-- use_cache: 前回の位置が分かっていれば、ポップアップが描かれるのを待たずに、まずそこへ出す
-- (ポップアップの位置は、普通は変わらない)。空きの位置が取れたあと、ずれていたときだけ出し直す。
-- 窓の位置が決まったら、ポップアップ自身の背景を透明にする。
local function viz_show_at_slot(use_cache)
	if use_cache and viz.cache then
		viz_control(string.format("show %.2f %.2f", viz.cache.x, viz.cache.y))
	end
	local id = viz.id
	viz_find_slot(id, function(x, y)
		local c = viz.cache
		if not (use_cache and c and c.x == x and c.y == y) then
			viz.cache = { x = x, y = y }
			viz_control(string.format("show %.2f %.2f", x, y))
		end
		viz.shown = true
		viz_take_background_later(id)
	end)
end

-- 起動していなければ、画面外に隠した状態で起動する
local function viz_ensure_hidden()
	if viz.running then
		return
	end
	viz.running = true
	viz.ready = false
	viz.shown = false
	viz.on_ready = nil
	viz.id = viz.id + 1 -- 直前の viz_stop の「止め直し」で、起動したばかりの cava を止めないようにする
	viz_launch(viz.id)
end

-- 止めるときは、先に窓を隠す。pkill だけだと、プロセスが終わるまで約 0.1〜0.2 秒、窓が残って見える
-- (ポップアップは先に消える)。制御ファイルへの書き込みは Lua で同期的に行い (シェルの起動を待たない)、
-- cava は書き込みで即座に起きて窓を隠す (消えるまで約 0.02 秒)。
local function viz_hide_now()
	local f = io.open(VIZ_CONTROL, "w")
	if f then
		f:write("hide")
		f:close()
	end
end

viz_stop = function()
	-- ポップアップ自身の背景を先に戻す (窓は、そのあとすぐに隠れる)。アニメーションの中で戻すと、透明から滑らかに
	-- 変わってしまうので、アニメーションの外で行う。
	viz.drawing_bg = false
	spotify:set({ popup = { background = popup_background(current_palette) } })
	viz_hide_now()
	viz.id = viz.id + 1 -- 位置を待っている処理を取り消す
	local id = viz.id
	viz.running = false
	viz.ready = false
	viz.shown = false
	viz.on_ready = nil
	sbar.exec(VIZ_STOP)
	-- open は起動に約 0.3 秒かかる。起動の直後に止めると、まだ存在しない窓には pkill が当たらず、
	-- 遅れて起動した窓が残ってしまう。その間に再び起動されていなければ、もう一度止める。
	sbar.delay(VIZ_KILL_AGAIN, function()
		if id == viz.id then
			sbar.exec(VIZ_STOP)
		end
	end)
end

-- ポップアップを開いたとき、または再生が始まったときに呼ぶ。ポップアップが開いていれば、窓を空きに出す。
viz_start = function()
	if not spinning or not popup_open then
		return
	end
	-- 普通は、ホバーの時点で起動済み (viz_wait)。ここで起動した場合 (ポップアップを開いたまま、停止から
	-- 再生に戻したときなど) は、起動の指示 (制御ファイルへの "hide" の書き込み) と、窓を出す指示 (同じファイルへの
	-- "show" の書き込み) の順序が決まらず、"hide" があとになると窓が出なくなる。そのため、準備完了を待ってから出す。
	local was_running = viz.running
	viz_ensure_hidden()
	if was_running then
		viz_show_at_slot(true)
	else
		viz.on_ready = function()
			viz_show_at_slot(false)
		end
	end
end

-- ポップアップを開くときに呼ぶ。cava を隠して起動し、準備ができたら on_ready を呼ぶ。
-- on_ready があとで呼ばれるときは true、再生中でない、または準備が済んでいるときは false を返す。
-- 準備ができなくても、呼び出し側が VIZ_WAIT_TIMEOUT 秒で窓を出す指示を出す (許可がなくて cava が起動できないときなど)。
viz_wait = function(on_ready)
	if not spinning then
		return false
	end
	viz_ensure_hidden()
	if viz.ready then
		return false
	end
	viz.on_ready = on_ready
	return true
end

sbar.add("event", VIZ_READY_EVENT)
spotify:subscribe(VIZ_READY_EVENT, function(env)
	-- 取り消された (止めた、または起動し直した) 起動のイベントは無視する
	if not viz.running or tostring(env.ID) ~= tostring(viz.id) then
		return
	end
	viz.ready = true
	viz_apply_color() -- 起動してから準備完了までの間に、色が変わっていたとき
	if viz.shown then
		viz_take_background_later(viz.id) -- 準備完了より先に、窓を出す指示を出していたとき
	end
	local on_ready = viz.on_ready
	viz.on_ready = nil
	if on_ready then
		on_ready()
	end
end)

-- 再読み込み前の窓が残っていたら止める
viz_stop()

-- アルバム画像から決めた配色 (palette.lua) を、ポップアップの各部分と棒グラフに反映する。
-- 棒、背景、枠の色は、cava が動いていれば SIGUSR2 で即座に変わる (止まっていれば、次の起動で入る)。
local function apply_palette(p)
	current_palette = p
	spotify:set({ popup = { background = popup_background(p) } })
	cover:set({ background = { border_color = p.border } })
	time_text:set({ label = { color = p.text } })
	time:set({ slider = { highlight_color = p.accent, background = { color = p.track } } })
	rows.title.item:set({ label = { color = p.text } })
	rows.artist.item:set({ label = { color = p.text } })
	rows.album.item:set({ label = { color = p.subtext } })
	viz.fg = p.viz
	viz.bg = hex(p.bg)
	viz.border = hex(p.border)
	viz_apply_color()
end

-- 表示の切り替え。アルバム画像 (と覆い) を出すか、Spotify のアイコンを出すか。
-- 画像は取得できてから出す (取得前に切り替えると、画像のない覆いだけが見えてしまう)。
local showing_art = false

local function show_art()
	showing_art = true
	spotify:set({
		icon = { drawing = false },
		label = { drawing = true },
		background = { image = { drawing = true } },
	})
end

local function show_icon()
	showing_art = false
	set_pinned(false)
	popup_open = false
	viz_stop()
	spotify:set({
		icon = { drawing = true },
		label = { drawing = false },
		background = { image = { drawing = false } },
		popup = { drawing = false },
	})
end

-- アルバム画像のキャッシュ。1 枚の画像につき、アイコン用 (ART_PX) とポップアップ用 (COVER_PX) の 2 サイズと、
-- 色の頻度表 ("個数,R,G,B;..."。palette.lua が配色を決める) の 3 ファイルを、画像の ID (artwork url の末尾) で持つ。
-- ファイル名にサイズ (px) を含めるのは、サイズを変えたとき、古い解像度の画像が残ると、表示サイズが設定から
-- ずれるため (表示サイズ = 画像の実ピクセル * scale)。
-- 流れは、曲 ID -> 画像の ID と url (osascript。一度引いた曲は覚えておく) -> キャッシュの確認 (Lua) ->
-- なければ取得 (シェル)。確認を Lua で行うので、キャッシュにある画像では、取得のためのシェルを起動しない。
-- 取得は画像の ID ごとに 1 本だけ走らせる (同じアルバムの曲を続けて切り替えると、同じ画像の取得が重なる。
-- 重なった要求は、走っている取得の完了を待つ)。取得は、curl の出力を中間ファイルなしで magick に渡し、
-- 1 回のデコードで 2 サイズと頻度表を出す。出力は一時ファイルに書いて、最後に mv で置く (途中の状態が見えない)。
local COLOR_SWATCHES = 32 -- 頻度表の色数 (palette.lua の入力)
local COLOR_SAMPLE_PX = 48 -- 頻度表を数えるときの画像の一辺 (px)

-- 未起動の Spotify を osascript が起動してしまわないよう、先に pgrep で確認する。
local ARTWORK_URL_COMMAND =
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to get artwork url of current track' 2>/dev/null]]

-- 画像の ID (key) と url から、3 つのファイルを作る。curl か magick が失敗したら (pipefail)、何も置かない。
local function download_command(key, url)
	return string.format(
		[[
set -o pipefail
dir=%q
key=%q
mkdir -p "$dir"
tmp="$dir/.$key.$$"
curl -sfL --max-time 10 %q \
  | magick - -units PixelsPerInch -density 72 \
      -resize %dx%d -write "jpeg:$tmp.large" \
      -resize %dx%d -write "jpeg:$tmp.small" \
      -resize %dx%d -colors %d -depth 8 -format %%c histogram:info:- \
  | sed -nE 's/^ *([0-9]+): *\( *([0-9]+), *([0-9]+), *([0-9]+).*/\1,\2,\3,\4/p' | paste -sd';' - > "$tmp.colors"
if [ $? -eq 0 ] && [ -s "$tmp.small" ] && [ -s "$tmp.large" ]; then
  [ -s "$tmp.colors" ] && mv -f "$tmp.colors" "$dir/$key.colors32"
  mv -f "$tmp.large" "$dir/$key.%d.jpg" && mv -f "$tmp.small" "$dir/$key.%d.jpg"
fi
rm -f "$tmp.large" "$tmp.small" "$tmp.colors"
]],
		CACHE_DIR,
		key,
		url,
		COVER_PX,
		COVER_PX,
		ART_PX,
		ART_PX,
		COLOR_SAMPLE_PX,
		COLOR_SAMPLE_PX,
		COLOR_SWATCHES,
		COVER_PX,
		ART_PX
	)
end

local function artwork_files(key)
	local base = CACHE_DIR .. "/" .. key
	return {
		small = string.format("%s.%d.jpg", base, ART_PX),
		large = string.format("%s.%d.jpg", base, COVER_PX),
		colors = base .. ".colors32",
	}
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text ~= "" and text or nil
end

local function file_exists(path)
	local f = io.open(path, "rb")
	if not f then
		return false
	end
	local size = f:seek("end")
	f:close()
	return size ~= nil and size > 0
end

-- 3 つとも揃っていれば files と頻度表を返す (色の頻度表が欠けた古いキャッシュは、取り直して揃える)
local function cached_artwork(key)
	local files = artwork_files(key)
	local histogram = read_file(files.colors)
	if histogram and file_exists(files.small) and file_exists(files.large) then
		return files, (histogram:gsub("%s+$", ""))
	end
	return nil
end

-- 古い画像の掃除は、起動時 (再読み込み含む) に 1 回だけ行う (取得と重ならない)
sbar.exec(string.format("find %q -type f -mtime +30 -delete 2>/dev/null", CACHE_DIR))

local downloads = {} -- 画像の ID -> 取得の完了を待っている処理 (取得が走っている間だけ持つ)

-- 画像を用意して、done(files, histogram) を呼ぶ (失敗したら done(nil))。
local function ensure_artwork(key, url, done)
	local files, histogram = cached_artwork(key)
	if files then
		done(files, histogram)
		return
	end
	if downloads[key] then
		table.insert(downloads[key], done)
		return
	end
	downloads[key] = { done }
	sbar.exec(download_command(key, url), function()
		local waiting = downloads[key]
		downloads[key] = nil
		local ready, ready_histogram = cached_artwork(key)
		if not ready then
			-- 色の頻度表だけ作れなかったときも、画像は出す (配色は固定色に戻る)
			local partial = artwork_files(key)
			if file_exists(partial.small) and file_exists(partial.large) then
				ready, ready_histogram = partial, ""
			end
		end
		for _, callback in ipairs(waiting) do
			callback(ready, ready_histogram)
		end
	end)
end

-- 曲 ID から画像の ID と url を引く。画像を出せた曲は覚えていて (load_artwork)、osascript を呼ばない。
-- 取得に失敗した曲は覚えない (誤った url を取っても、使い回さない)。
local artwork_of_track = {}

local function resolve_artwork(track_id, done)
	local known = artwork_of_track[track_id]
	if known then
		done(known)
		return
	end
	sbar.exec(ARTWORK_URL_COMMAND, function(out)
		local url = type(out) == "string" and out:match("^%s*(https?://%S+)") or nil
		local key = url and url:match("([^/]+)$")
		done(key and { key = key, url = url } or nil)
	end)
end

local current_track = nil

-- 取得に失敗したとき (ネットワークや osascript の一時的な失敗) は、少し待って取り直す。
local ARTWORK_ATTEMPTS = 3
local ARTWORK_RETRY_DELAY = 0.5 -- 秒

local function load_artwork(track_id, attempt)
	attempt = attempt or 1
	current_track = track_id
	local function retry()
		if attempt < ARTWORK_ATTEMPTS then
			sbar.delay(ARTWORK_RETRY_DELAY, function()
				if current_track == track_id then
					load_artwork(track_id, attempt + 1)
				end
			end)
		else
			current_track = nil -- 次のイベントで再試行する
		end
	end
	resolve_artwork(track_id, function(artwork)
		-- 取得中に曲が変わった・停止した場合は捨てる
		if current_track ~= track_id then
			return
		end
		if not artwork then
			retry()
			return
		end
		ensure_artwork(artwork.key, artwork.url, function(files, histogram)
			if current_track ~= track_id then
				return
			end
			if not files then
				retry()
				return
			end
			artwork_of_track[track_id] = artwork
			spotify:set({ background = { image = { string = files.small } } })
			cover:set({ background = { image = { string = files.large, drawing = true } } })
			apply_palette(palette.from_histogram(histogram) or palette.default)
			show_art()
		end)
	end)
end

-- meta は { title, artist, album }、timing は { position, duration } (どちらも秒)。
-- 取れなかったときは nil で、ポップアップ (曲情報、再生位置) はそのまま。
local function apply(state, track_id, meta, timing)
	local playing = state == "Playing"
	if playing or state == "Paused" then
		local changed = track_id ~= current_track
		if changed then
			load_artwork(track_id)
		end
		if meta then
			set_popup_info(meta)
		end
		if timing then
			rebase(timing.position, timing.duration, playing, changed)
		end
		set_spinning(playing)
		set_lit(playing)
		if playing then
			viz_start() -- ポップアップを開いたまま再開したとき
		else
			viz_stop()
		end
	else
		set_spinning(false)
		set_lit(false)
		current_track = nil
		show_icon()
	end
end

sbar.add("event", "spotify_change", "com.spotify.client.PlaybackStateChanged")

spotify:subscribe("spotify_change", function(env)
	local info = env.INFO
	if type(info) ~= "table" then
		return
	end
	-- Playback Position は秒 (小数)、Duration はミリ秒 (実機で確認)
	local position, duration = tonumber(info["Playback Position"]), tonumber(info["Duration"])
	local timing = nil
	if position and duration and duration > 0 then
		timing = { position = position, duration = duration / 1000 }
	end
	apply(info["Player State"], info["Track ID"], {
		title = info["Name"],
		artist = info["Artist"],
		album = info["Album"],
	}, timing)
end)

-- Spotify の終了は通知が来るとは限らないので、画像を出している間だけ、起動中かを定期的に確認する。
-- 終了していたら、曲がないときと同じくアイコンに戻す。
spotify:subscribe("routine", function()
	if not showing_art then
		return
	end
	sbar.exec("pgrep -x Spotify >/dev/null && echo running", function(out)
		if type(out) == "string" and out:find("running", 1, true) then
			return
		end
		apply(nil)
	end)
end)

-- ホバーでポップアップを開閉する (曲情報があるとき、つまり画像を出している間だけ)。
-- バーの外へ出たときは mouse.exited.global でも閉じる。
hit:subscribe("mouse.entered", function()
	-- ピン留め中は開いたままなので、開き直さない (フェードインのやり直しになる)
	if showing_art and not popup_open then
		open_popup()
	end
end)

hit:subscribe({ "mouse.exited", "mouse.exited.global" }, close_popup)

-- 操作: 左クリックで再生/一時停止、左ダブルクリックで Spotify のウィンドウを表示、
-- 右クリックでポップアップのピン留め (もう一度で外す)、上スクロールで前の曲、下スクロールで次の曲。
-- 表示は上の分散通知で追従するので、ここでは Spotify に命令を送るだけにする。
-- 未起動の Spotify を起動してしまわないよう、pgrep で確認してから送る。
local function spotify_command(command)
	sbar.exec(
		string.format([[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to %s']], command)
	)
end

-- ウィンドウの表示は open で行う。-g -j の自動起動で隠れているときも前面に出て、
-- ウィンドウを閉じただけのときも開き直す。名前 (open -a Spotify) ではなく
-- Home Manager Apps のパスで指定する (名前だと更新用の一時コピーに解決されることがある)。
local SPOTIFY_APP = os.getenv("HOME") .. "/Applications/Home Manager Apps/Spotify.app"

-- ダブルクリックの検出。SketchyBar にはダブルクリックのイベントがなく、クリックが 2 回届くだけなので、
-- 1 回目のクリックの再生/一時停止を DOUBLE_CLICK_INTERVAL 秒だけ待ち、その間に 2 回目が来たらダブルクリックとして
-- Spotify のウィンドウの表示にする (再生/一時停止は行わない)。そのため、再生/一時停止はクリックからこの秒数だけ遅れる。
-- macOS の既定のダブルクリックの間隔は約 0.5 秒だが、再生/一時停止の遅れを抑えるため短くしてある。
local DOUBLE_CLICK_INTERVAL = 0.3
local click_id = 0
local click_pending = false

hit:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "left" then
		if click_pending then
			click_pending = false
			sbar.exec(string.format("open %q", SPOTIFY_APP))
			return
		end
		click_pending = true
		click_id = click_id + 1
		local id = click_id
		sbar.delay(DOUBLE_CLICK_INTERVAL, function()
			if click_pending and id == click_id then
				click_pending = false
				spotify_command("playpause")
			end
		end)
	elseif env.BUTTON == "right" then
		-- ポップアップが開いていない (曲情報がない) ときは、ピン留めしない。外すのはいつでもできる
		if pinned then
			set_pinned(false)
		elseif popup_open then
			set_pinned(true)
		end
	end
end)

-- トラックパッドは 1 回のスワイプで多数のイベントが出る (慣性スクロール含む) ので、
-- 一度反応したら SCROLL_COOLDOWN 秒は無視して、1 スワイプで 1 曲だけ動かす。
-- SCROLL_DELTA の符号は上スクロールが正の想定。逆なら SCROLL_UP_SIGN を -1 にする。
local SCROLL_COOLDOWN = 1.0
local SCROLL_UP_SIGN = 1
local PREVIOUS_REFRESH_DELAY = 0.4 -- 「前の曲」の命令から、再生位置を取り直すまでの秒数
local scroll_locked = false

hit:subscribe("mouse.scrolled", function(env)
	local delta = tonumber(env.SCROLL_DELTA)
	if not delta or delta == 0 or scroll_locked then
		return
	end
	scroll_locked = true
	sbar.delay(SCROLL_COOLDOWN, function()
		scroll_locked = false
	end)
	local previous = delta * SCROLL_UP_SIGN > 0
	spotify_command(previous and "previous track" or "next track")
	if previous then
		-- 曲の途中なら、Spotify は同じ曲の先頭に戻す (シーク)。シークでは分散通知が来ないので、
		-- 少し待って (Spotify が位置を戻すのを待つ)、実際の位置に合わせ直す。別の曲に戻った場合は通知が来る。
		sbar.delay(PREVIOUS_REFRESH_DELAY, function()
			refresh_position(nil, false)
		end)
	end
end)

-- 起動時 (再読み込み含む) に既に再生中でも拾えるよう、現在の状態を一度だけ取得する
local INITIAL_STATES = { playing = "Playing", paused = "Paused" }

-- 曲名などに "|" が含まれうるので、区切りにはタブを使う
sbar.exec(
	[[pgrep -x Spotify >/dev/null && osascript -e 'tell application "Spotify" to (player state as text) & tab & (id of current track) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text)' 2>/dev/null]],
	function(out)
		if type(out) ~= "string" then
			return
		end
		local state, track_id, title, artist, album, position, duration =
			out:match("^(%a+)\t(%S+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([%d.,]+)\t(%d+)")
		if INITIAL_STATES[state] then
			position = parse_position(position)
			duration = tonumber(duration) / 1000
			local timing = position and duration > 0 and { position = position, duration = duration } or nil
			apply(INITIAL_STATES[state], track_id, { title = title, artist = artist, album = album }, timing)
		end
	end
)
