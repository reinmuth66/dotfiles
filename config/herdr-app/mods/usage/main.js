// 利用制限 (5h、7d)。data/limits/{claude-code,agy}.json を見張り、2 つの二重の円で出す。
// agy の値は 5 分ごとに `agy -p /quota` で取って agy.json に書く。
// 表示の組み立ては logic.js、色と寸法は ui.js にある
import * as fs from "fs/promises";
import { View, div, image, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { appHome, checking, exec, readTextFile, writeTextFile } from "herdr";
import { METRICS, PALETTE, cells, ringArc } from "./ui.js";
import { watchJsonDir } from "./data.js";
import { parseAgyQuota, pickAgyPool, windowView } from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;
const RING_OUTER = 36; // 5h (外側の輪) の直径
const RING_INNER = 26; // 7d (内側の輪) の直径
const RING_STROKE = 3;
const TICK_LEN = 3; // 経過の位置に輪をまたぐ線の長さ
const TICK_STROKE = 1;
const ICON_SIZE = 14;
const GROUP_GAP = 4;
const AGY_INTERVAL = 5 * 60_000;
const AGY_TIMEOUT = 60_000;

// 12 時を 0、時計回りに 1 周を 1 とする角度の円周上の点
function ringPoint(cx, cy, r, fraction) {
  const angle = fraction * 2 * Math.PI;
  return [cx + r * Math.sin(angle), cy - r * Math.cos(angle)];
}

function strokeArc(arc, stroke) {
  const { r, cx, cy, start, end, largeArc, full } = arc;
  let builder = PathBuilder.stroke(stroke).move_to(...start);
  if (full) builder = builder.arc_to(r, r, 0, false, true, cx, cy + r).arc_to(r, r, 0, false, true, ...start);
  else builder = builder.arc_to(r, r, 0, largeArc, true, ...end);
  return builder.build();
}

// 経過の位置から超過分だけ時計回りに描く弧
function overArcPath(from, over, outer, stroke) {
  const to = Math.min(1, from + over);
  const span = to - from;
  if (!(span > 0)) return null;
  const r = (outer - stroke) / 2;
  const cx = outer / 2;
  const cy = outer / 2;
  const start = ringPoint(cx, cy, r, from);
  let builder = PathBuilder.stroke(stroke).move_to(...start);
  if (span >= 0.999) {
    const mid = ringPoint(cx, cy, r, from + 0.5);
    builder = builder.arc_to(r, r, 0, false, true, ...mid).arc_to(r, r, 0, false, true, ...start);
  } else {
    const end = ringPoint(cx, cy, r, to);
    builder = builder.arc_to(r, r, 0, span > 0.5, true, ...end);
  }
  return builder.build();
}

// 経過の位置に輪の線をまたぐ短い線
function tickPath(fraction, outer, stroke) {
  const r = (outer - stroke) / 2;
  const cx = outer / 2;
  const cy = outer / 2;
  const angle = fraction * 2 * Math.PI;
  const ux = Math.sin(angle);
  const uy = -Math.cos(angle);
  const half = TICK_LEN / 2;
  return PathBuilder.stroke(TICK_STROKE)
    .move_to(cx + (r - half) * ux, cy + (r - half) * uy)
    .line_to(cx + (r + half) * ux, cy + (r + half) * uy)
    .build();
}

// 1 本の輪。全周の下地を敷き、窓があれば使用分・超過分・経過の印を重ねる
function ringLayer(view, outer) {
  const offset = (RING_OUTER - outer) / 2;
  const paint = (path, color) => window.paint_path(path, color).absolute().top(0).left(0).size_full();
  const layers = [paint(strokeArc(ringArc(1, outer, RING_STROKE), RING_STROKE), PALETTE.surface0)];
  if (view) {
    const usedArc = ringArc(view.used / 100, outer, RING_STROKE);
    if (usedArc) layers.push(paint(strokeArc(usedArc, RING_STROKE), view.barColor));
    if (view.elapsed != null) {
      if (view.overColor) {
        const over = overArcPath(view.elapsed, view.over, outer, RING_STROKE);
        if (over) layers.push(paint(over, view.overColor));
      }
      layers.push(paint(tickPath(view.elapsed, outer, RING_STROKE), PALETTE.text));
    }
  }
  return div().absolute().top(offset).left(offset).w(outer).h(outer).children(layers);
}

function findWindow(windows, key) {
  return Array.isArray(windows) ? (windows.find((w) => w?.key === key) ?? null) : null;
}

export default class Usage extends View {
  init(_props, cx) {
    this.files = {};
    this.agyPath = null;
    this.fetchingAgy = false;
    this.watch = watchJsonDir(cx, "limits", (files) => {
      this.files = files;
      cx.notify();
    });
    if (checking()) return;
    // 経過と残り時間を進める
    this.timer = cx.timer.every(60_000, (cx) => cx.notify());
    cx.spawn(() => this.fetchAgy());
    this.agyTimer = cx.timer.every(AGY_INTERVAL, (cx) => {
      cx.spawn(() => this.fetchAgy());
    });
  }

  close() {
    this.watch?.cancel();
    this.timer?.cancel();
    this.agyTimer?.cancel();
  }

  // `agy -p /quota` を実行し、取れた窓があれば data/limits/agy.json を原子的に置き換える。
  // herdr の PATH に agy が無いこともあるので、最初の 1 回だけログインシェルで絶対パスを引く
  async fetchAgy() {
    if (this.fetchingAgy) return;
    this.fetchingAgy = true;
    try {
      if (!this.agyPath) {
        const found = await exec("/bin/zsh", ["-lc", "command -v agy"]);
        const resolved = found.code === 0 ? found.stdout.trim() : "";
        if (!resolved) return;
        this.agyPath = resolved;
      }
      const res = await exec(this.agyPath, ["-p", "/quota"], { timeout: AGY_TIMEOUT });
      if (res.code !== 0) return;
      const pools = parseAgyQuota(res.stdout);
      if (pools.gemini.length + pools.other.length === 0) return;
      const dir = `${appHome()}/data/limits`;
      const target = `${dir}/agy.json`;
      const body = JSON.stringify({
        agent: "agy",
        name: "agy",
        updated_at: Math.floor(Date.now() / 1000),
        pools,
      });
      await fs.mkdir(dir, { recursive: true });
      const expected = await readTextFile(target);
      await writeTextFile(target, body, expected);
    } catch {
      // 失敗は黙って次を待つ
    } finally {
      this.fetchingAgy = false;
    }
  }

  // 左 (使用率 2 行) + 二重の円 (中央にマーク) + 右 (残り時間 2 行)
  ringGroup(windows, icon, now) {
    const w5 = findWindow(windows, "5h");
    const w7 = findWindow(windows, "7d");
    const v5 = w5 ? windowView(w5, now) : null;
    const v7 = w7 ? windowView(w7, now) : null;
    const rowH = RING_OUTER / 2;

    const leftCol = v_flex()
      .flex_none()
      .w(cells(4))
      .h(RING_OUTER)
      .items_end()
      .child(
        h_flex()
          .h(rowH)
          .items_center()
          .text_color(v5 ? v5.barColor : PALETTE.text)
          .child(v5 ? `${Math.round(v5.used)}%` : ""),
      )
      .child(
        h_flex()
          .h(rowH)
          .items_center()
          .text_color(v7 ? v7.barColor : PALETTE.text)
          .child(v7 ? `${Math.round(v7.used)}%` : ""),
      );

    const ring = div()
      .relative()
      .flex_none()
      .w(RING_OUTER)
      .h(RING_OUTER)
      .child(ringLayer(v5, RING_OUTER))
      .child(ringLayer(v7, RING_INNER))
      .child(div().absolute().inset_0().flex().items_center().justify_center().child(icon.w(ICON_SIZE).h(ICON_SIZE).flex_none()));

    const rightCol = v_flex()
      .flex_none()
      .w(cells(5))
      .h(RING_OUTER)
      .items_start()
      .child(
        h_flex()
          .h(rowH)
          .items_center()
          .text_color(v5 ? v5.remainingColor : PALETTE.text)
          .child(v5?.remaining ?? ""),
      )
      .child(
        h_flex()
          .h(rowH)
          .items_center()
          .text_color(v7 ? v7.remainingColor : PALETTE.text)
          .child(v7?.remaining ?? ""),
      );

    return h_flex().flex_none().items_center().gap(GROUP_GAP).child(leftCol).child(ring).child(rightCol);
  }

  render() {
    const now = Date.now() / 1000;
    const claudeWindows = this.files["claude-code"]?.windows;
    const agyPools = this.files["agy"]?.pools;
    const agyPool = pickAgyPool(agyPools, now);
    const agyWindows = agyPools?.[agyPool];
    const agyIcon = agyPool === "gemini" ? image("icons/antigravity.svg") : svg("icons/claude.svg").text_color(PALETTE.blue);

    return h_flex()
      .id("usage")
      .size_full()
      .pl(METRICS.padLeft)
      .pr(PAD_RIGHT)
      .items_center()
      .justify_between()
      .overflow_hidden()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .child(this.ringGroup(claudeWindows, image("icons/claude.svg"), now))
      .child(this.ringGroup(agyWindows, agyIcon, now));
  }
}
