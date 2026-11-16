"""デザインシステム「modern」の色を、法則から計算する。標準ライブラリだけを使う。

法則 (tokens.json の meta.colorRule と同じ):
  明るさ   段の番号 N から L = 1.018 - 0.000853 * N (上限 1)。灰と有彩色で共通
  鮮やかさ 50 は 0.012、100 は 0.03。300 はその明るさで出せる上限の 55%、500 は 85%、600・700・900 は 95%。灰は 0
  色相     meta.colorRule.hue に書いた角度

使い方:
  python3 color.py check <tokens.json>   全ての <色相>-<段> と gray-<段> が、法則どおりの値かを確かめる
  python3 color.py ladder <角度>         その色相の 7 段の値と、地 (gray-50) とのコントラスト比を出す

色相を足すときは、meta.colorRule.hue に名前と角度を足し、check が出す値を tokens.json に書く。
"""

import json
import math
import sys

STEPS = [50, 100, 300, 500, 600, 700, 900]
# 上限に対する鮮やかさの割合。50 と 100 は、割合ではなく固定の値にする
CHROMA_RATIO = {300: 0.55, 500: 0.85, 600: 0.95, 700: 0.95, 900: 0.95}
CHROMA_FIXED = {50: 0.012, 100: 0.03}


def _to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _to_gamma(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def oklch_to_linear_rgb(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def in_gamut(L, C, H, eps=1e-4):
    return all(-eps <= c <= 1 + eps for c in oklch_to_linear_rgb(L, C, H))


def max_chroma(L, H):
    """その明るさと色相で、sRGB に収まる鮮やかさの上限。"""
    lo, hi = 0.0, 0.4
    for _ in range(40):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if in_gamut(L, mid, H) else (lo, mid)
    return lo


def to_hex(L, C, H):
    C = min(C, max_chroma(L, H))
    rgb = (_to_gamma(max(0, min(1, c))) for c in oklch_to_linear_rgb(L, C, H))
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in rgb)


def luminance(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (_to_linear(int(h[i : i + 2], 16) / 255) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def lightness(step):
    return min(1.0, 1.018 - 0.000853 * step)


def chroma(step, hue):
    L = lightness(step)
    if step in CHROMA_FIXED:
        return min(CHROMA_FIXED[step], max_chroma(L, hue))
    return CHROMA_RATIO[step] * max_chroma(L, hue)


def color(step, hue):
    """hue が None なら灰。"""
    if hue is None:
        return to_hex(lightness(step), 0, 0)
    return to_hex(lightness(step), chroma(step, hue), hue)


def check(path):
    with open(path, encoding="utf-8") as f:
        tokens = json.load(f)
    values = {token["name"]: token["value"] for token in tokens["color"]["tokens"]}
    hues = {"gray": None, **tokens["meta"]["colorRule"]["hue"]}

    problems = []
    for name, hue in hues.items():
        for step in STEPS:
            token = f"{name}-{step}"
            expected = color(step, hue)
            actual = values.get(token)
            if actual is None:
                problems.append(f"{token} がない (法則の値は {expected})")
            elif actual.lower() != expected:
                problems.append(f"{token} は {actual} だが、法則の値は {expected}")

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f"{len(hues) * len(STEPS)} 色が法則どおり")
    return 0


def ladder(hue):
    background = color(50, None)
    for step in STEPS:
        value = color(step, hue)
        print(f"{step:>3}  {value}  地との比 {contrast(value, background):.1f}")
    return 0


def main(argv):
    if len(argv) == 3 and argv[1] == "check":
        return check(argv[2])
    if len(argv) == 3 and argv[1] == "ladder":
        return ladder(float(argv[2]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
