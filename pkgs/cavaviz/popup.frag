#version 330

// Spotify のポップアップの背景、枠、棒グラフを描く (cava の SDL 版のシェーダー。modules/cavaviz.nix を参照)。
// 窓は SketchyBar のポップアップの背景 (中身の左端から始まり、右と上下に枠の太さの分だけ広い) と同じ位置と大きさで、ポップアップの下 (sdl-window.patch で window level 100) に置く。
// ポップアップの背景は透明にしてあり、文字は、SketchyBar がこの窓の上に描く。
// 窓のうち、角の外は透明 (アルファ 0)。窓は premultiplied alpha で合成されるので、色にもアルファを掛ける。
// 再生位置は、棒の色で示す。棒の領域の左端から再生位置 (viz_progress) までの棒は再生済みの色で明るく、
// それより右は未再生の色で描く (2 色の明るさは config/sketchybar/palette.lua が決める)。

in vec2 fragCoord;
out vec4 fragColor;

uniform float bars[512];
uniform int bars_count;
uniform int bar_spacing; // 棒と棒の間の隙間 (pt)。棒の幅は、領域の幅と棒の数から決まる

uniform vec3 u_resolution; // 窓の大きさ (pt。描画面は Retina で 2 倍の px)
uniform float viz_progress; // 再生位置 (0〜1)。sdl-progress.patch が、$CAVAVIZ_PROGRESS のファイルから渡す

// 色は、設定のグラデーションの色 (gradient_color_1〜4) で受け取る。foreground / background は動いている間に変えられず、
// グラデーションの色だけが SIGUSR2 で読み直されるため。
uniform vec3 gradient_colors[8]; // [0] 未再生の棒、[1] 背景、[2] 枠、[3] 再生済みの棒

// 窓の左上を原点とする、下向きが正の値 (pt)。config/sketchybar/items/spotify.lua の VIZ_* と、
// config/sketchybar/colors.lua の popup (角の半径と枠の太さ) に合わせる。
const vec4 VIZ = vec4(6.0, 4.0, 220.0, 26.0); // 棒グラフの領域: x, y, 幅, 高さ
const float RADIUS = 5.0; // ポップアップの角の半径
const float BORDER = 1.0; // 枠の太さ (図形の内側に引く)
const float MIN_BAR = 2.0; // 棒の最小の高さ (pt)。曲の静かな部分でも、棒の色で再生位置が見えるようにする

void main() {
    vec2 size = u_resolution.xy;
    vec2 p = vec2(fragCoord.x, 1.0 - fragCoord.y) * size; // 窓の左上を原点にした位置

    vec3 bar_color = gradient_colors[0];
    vec3 played_color = gradient_colors[3];
    vec3 bg_color = gradient_colors[1];
    vec3 border_color = gradient_colors[2];

    // 画面の 1px が何 pt か (Retina なら 0.5)。縁は、この幅でぼかす
    float px = fwidth(p.y);

    // 角丸の長方形の距離 (内側が負)。角と枠を滑らかにする
    vec2 q = abs(p - 0.5 * size) - 0.5 * size + RADIUS;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - RADIUS;
    float shape = clamp(0.5 - d / px, 0.0, 1.0);
    float inner = clamp(0.5 - (d + BORDER) / px, 0.0, 1.0);
    vec3 color = mix(border_color, bg_color, inner);

    // 棒グラフ。領域の左下を原点にして、上向きを正にする
    vec2 v = vec2(p.x - VIZ.x, VIZ.y + VIZ.w - p.y);
    if (v.x >= 0.0 && v.x < VIZ.z && v.y >= 0.0 && v.y <= VIZ.w) {
        // 最初の棒の左端と最後の棒の右端が、領域の両端に合うように並べる。
        // 棒の間隔 (幅 + 隙間) は (領域の幅 + 隙間) / 棒の数。棒の幅は、そこから隙間を引いた値 (端数が出るので、左右の縁もぼかす)
        float pitch = (VIZ.z + float(bar_spacing)) / float(bars_count);
        int bar = min(int(v.x / pitch), bars_count - 1);
        float left = float(bar) * pitch;
        float right = left + pitch - float(bar_spacing);
        float across = clamp((v.x - left) / px + 0.5, 0.0, 1.0) * clamp((right - v.x) / px + 0.5, 0.0, 1.0);
        // 無音でも MIN_BAR の高さは描く (再生位置を、棒の色で示すため)。上端はぼかす
        float height = max(bars[bar] * VIZ.w, MIN_BAR);
        float cover = clamp((height - v.y) / px + 0.5, 0.0, 1.0);
        // 再生済みの範囲は、棒の領域の左端から再生位置まで。棒の途中でも切り替わる (境界は 1px でぼかす)
        float played = clamp((viz_progress * VIZ.z - v.x) / px + 0.5, 0.0, 1.0);
        vec3 paint = mix(bar_color, played_color, played);
        // 棒は不透明で描く。未再生と再生済みの色は、背景と文字に対する明るさを palette.lua が決めている
        color = mix(color, paint, across * cover);
    }

    fragColor = vec4(color * shape, shape);
}
