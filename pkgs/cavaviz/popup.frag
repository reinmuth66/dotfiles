#version 330

// Spotify のポップアップの背景、枠、棒グラフを描く。cava の SDL 版のシェーダーで、modules/cavaviz.nix を参照。
// 窓は SketchyBar のポップアップの背景と同じ位置と大きさで、ポップアップの下に置く。ポップアップの下は sdl-window.patch で window level 100。
// ポップアップの背景は、中身の左端から始まり、右と上下に枠の太さの分だけ広い。
// ポップアップの背景は透明にしてあり、文字は、SketchyBar がこの窓の上に描く。
// 窓のうち、角の外は透明でアルファ 0。窓は premultiplied alpha で合成されるので、色にもアルファを掛ける。
// 再生済みと未再生の 2 色の明るさは config/sketchybar/palette.lua が決める。

in vec2 fragCoord;
out vec4 fragColor;

uniform float bars[512];
uniform int bars_count;
uniform int bar_spacing; // pt

// 描画面は Retina で 2 倍の px。
uniform vec3 u_resolution; // pt

// 再生位置の 0〜1。sdl-progress.patch が、$CAVAVIZ_PROGRESS のファイルから渡す。
uniform float viz_progress;

// 色は、設定のグラデーションの色の gradient_color_1〜4 で受け取る。foreground と background は動いている間に変えられず、
// グラデーションの色だけが SIGUSR2 で読み直されるため。
// 添字は 0 が未再生の棒、1 が背景、2 が枠、3 が再生済みの棒。
uniform vec3 gradient_colors[8];

// 窓の左上を原点とする、下向きが正の値で、単位は pt。config/sketchybar/items/spotify.lua の VIZ_* と、
// config/sketchybar/colors.lua の popup の角の半径と枠の太さに合わせる。
// VIZ は棒グラフの領域で、x, y, 幅, 高さの順。BORDER は図形の内側に引く。
// MIN_BAR の単位は pt。曲の静かな部分でも、棒の色で再生位置が見えるようにする。
const vec4 VIZ = vec4(6.0, 4.0, 222.0, 26.0);
const float RADIUS = 5.0;
const float BORDER = 1.0;
const float MIN_BAR = 2.0;

// 画面の 1px が何 pt かを px に取る。Retina なら 0.5。縁は、この幅でぼかす。
// 角丸の長方形の距離を求める。内側が負。角と枠を滑らかにする。
// 棒グラフは、領域の左下を原点にして、上向きを正にする。
// 最初の棒の左端と最後の棒の右端が、領域の両端に合うように並べる。端数が出るので、左右の縁もぼかす。
// 無音でも MIN_BAR の高さは描く。再生位置を、棒の色で示すため。上端はぼかす。
// 棒の途中でも再生済みに切り替わる。境界は 1px でぼかす。
// 棒は不透明で描く。未再生と再生済みの色は、背景と文字に対する明るさを palette.lua が決めている。
void main() {
    vec2 size = u_resolution.xy;
    vec2 p = vec2(fragCoord.x, 1.0 - fragCoord.y) * size;

    vec3 bar_color = gradient_colors[0];
    vec3 played_color = gradient_colors[3];
    vec3 bg_color = gradient_colors[1];
    vec3 border_color = gradient_colors[2];

    float px = fwidth(p.y);

    vec2 q = abs(p - 0.5 * size) - 0.5 * size + RADIUS;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - RADIUS;
    float shape = clamp(0.5 - d / px, 0.0, 1.0);
    float inner = clamp(0.5 - (d + BORDER) / px, 0.0, 1.0);
    vec3 color = mix(border_color, bg_color, inner);

    vec2 v = vec2(p.x - VIZ.x, VIZ.y + VIZ.w - p.y);
    if (v.x >= 0.0 && v.x < VIZ.z && v.y >= 0.0 && v.y <= VIZ.w) {
        float pitch = (VIZ.z + float(bar_spacing)) / float(bars_count);
        int bar = min(int(v.x / pitch), bars_count - 1);
        float left = float(bar) * pitch;
        float right = left + pitch - float(bar_spacing);
        float across = clamp((v.x - left) / px + 0.5, 0.0, 1.0) * clamp((right - v.x) / px + 0.5, 0.0, 1.0);
        float height = max(bars[bar] * VIZ.w, MIN_BAR);
        float cover = clamp((height - v.y) / px + 0.5, 0.0, 1.0);
        float played = clamp((viz_progress * VIZ.z - v.x) / px + 0.5, 0.0, 1.0);
        vec3 paint = mix(bar_color, played_color, played);
        color = mix(color, paint, across * cover);
    }

    fragColor = vec4(color * shape, shape);
}
