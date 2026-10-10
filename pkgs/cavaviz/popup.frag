#version 330

// Draws the Spotify popup's background, border, and bar graph. A shader for the SDL version of cava; see modules/cavaviz.nix.
// The window has the same position and size as the SketchyBar popup's background, and is placed under the popup. Under the popup is window level 100 via sdl-window.patch.
// The popup's background starts from the contents' left edge and is wider by the border thickness on the right, top, and bottom.
// The popup's background is made transparent, and SketchyBar draws the text over this window.
// Outside the corners, the window is transparent with alpha 0. The window is composited with premultiplied alpha, so multiply the color by alpha too.
// The brightness of the two colors, played and unplayed, is decided by config/sketchybar/palette.lua.

in vec2 fragCoord;
out vec4 fragColor;

uniform float bars[512];
uniform int bars_count;
uniform int bar_spacing; // pt

// The drawing surface is 2x px on Retina.
uniform vec3 u_resolution; // pt

// Playback position 0 to 1. sdl-progress.patch passes it from the file at $CAVAVIZ_PROGRESS.
uniform float viz_progress;

// Colors are received as the config's gradient colors gradient_color_1 to 4. foreground and background cannot be changed while running,
// and only the gradient colors are re-read on SIGUSR2.
// Index 0 is the unplayed bar, 1 is the background, 2 is the border, 3 is the played bar.
uniform vec3 gradient_colors[8];

// Values with the window's top-left as origin and downward positive, in pt. Match VIZ_* in config/sketchybar/items/spotify.lua and
// the popup's corner radius and border thickness in config/sketchybar/colors.lua.
// VIZ is the bar graph's area, in the order x, y, width, height. BORDER is drawn inside the shape.
// The unit of MIN_BAR is pt. It lets the playback position be seen by bar color even in quiet parts of a track.
const vec4 VIZ = vec4(6.0, 4.0, 222.0, 26.0);
const float RADIUS = 5.0;
const float BORDER = 1.0;
const float MIN_BAR = 2.0;

// How many pt one screen px is. 0.5 on Retina. Edges are blurred by this width.
// Compute the distance of a rounded rectangle. Negative inside. Smooths the corners and border.
// The bar graph takes the area's bottom-left as origin and upward as positive.
// Lay out so that the first bar's left edge and the last bar's right edge meet the two ends of the area. Fractions arise, so the left and right edges are also blurred.
// Even in silence, draw the MIN_BAR height. To indicate the playback position by bar color. The top edge is blurred.
// It switches to played partway through a bar. The boundary is blurred by 1px.
// Bars are drawn opaque. palette.lua decides the brightness of the unplayed and played colors relative to the background and text.
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
