// 利用制限 (5h、7d)。data/limits/{claude-code,agy}.json を見張り、2 つの二重の円で出す。
// agy の値は 5 分ごとに `agy -p /quota` で取って agy.json に書く。
// 表示の組み立ては logic.js、色と寸法は ui.js にある
import * as fs from "fs/promises";
import { View, div, image, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { appHome, checking, exec, readTextFile, writeTextFile } from "herdr";
import { METRICS, PALETTE, cells } from "./ui.js";
import { watchJsonDir } from "./data.js";
import { parseAgyQuota, pickAgyPool, windowView } from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;
const RING_OUTER = 48; // 5h (外側の輪) の直径
const RING_INNER = 34; // 7d (内側の輪) の直径
const RING_STROKE = 3;
const ICON_SIZE = 18; // agy のマーク
const CLAUDE_ICON_SIZE = 22; // Claude Code のキャラ。横長なので一回り大きくする (内側の輪の内径は 28)
const RING_GAP = 6; // 円と数字の間。円 48 + 間 6 + 数字 15 × 2 = 84 (枠の中の高さ)
const AGY_INTERVAL = 5 * 60_000;
const AGY_TIMEOUT = 60_000;

// 12 時を 0、時計回りに 1 周を 1 とする角度の円周上の点
function ringPoint(cx, cy, r, fraction) {
  const angle = fraction * 2 * Math.PI;
  return [cx + r * Math.sin(angle), cy - r * Math.cos(angle)];
}

// from から to まで (0 から 1) の弧を描く。arc_to は半周の弧で半径がずれて描かれるので、
// 1 回の arc_to は 1/8 周以下にする
function arcPath(from, to, outer, stroke) {
  const a = Math.max(0, from);
  const b = Math.min(1, to);
  if (!(b - a > 0)) return null;
  const r = (outer - stroke) / 2;
  const c = outer / 2;
  // 1/8 周以下の弧に分けて arc_to でつなぐ (直線でつなぐと角が見える)
  const steps = Math.max(1, Math.ceil((b - a) * 8));
  let builder = PathBuilder.stroke(stroke).move_to(...ringPoint(c, c, r, a));
  for (let i = 1; i <= steps; i++) builder = builder.arc_to(r, r, 0, false, true, ...ringPoint(c, c, r, a + ((b - a) * i) / steps));
  return builder.build();
}

// 1 本の輪。全周の下地の上に、経過の位置から 100% までを残り時間の薄い色で敷き、
// 0 から使用分を窓の色で、経過の位置より先の使用分を超過の色で重ねる
function ringLayer(view, outer) {
  const offset = (RING_OUTER - outer) / 2;
  const layers = [];
  const add = (from, to, color) => {
    const path = arcPath(from, to, outer, RING_STROKE);
    if (path) layers.push(window.paint_path(path, color).absolute().top(0).left(0).size_full());
  };
  add(0, 1, PALETTE.surface0);
  if (view) {
    const used = view.used / 100;
    if (view.elapsed != null) {
      add(view.elapsed, 1, view.remainingColor);
      add(0, Math.min(used, view.elapsed), view.barColor);
      if (view.overColor) add(view.elapsed, used, view.overColor);
    } else {
      add(0, used, view.barColor);
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

  // 二重の円 (中央にマーク) と、その下の「使用率 残り時間」の 2 行 (上が 5h、下が 7d)
  ringGroup(windows, icon, now) {
    const w5 = findWindow(windows, "5h");
    const w7 = findWindow(windows, "7d");
    const v5 = w5 ? windowView(w5, now) : null;
    const v7 = w7 ? windowView(w7, now) : null;
    const ring = div()
      .relative()
      .flex_none()
      .w(RING_OUTER)
      .h(RING_OUTER)
      .child(ringLayer(v5, RING_OUTER))
      .child(ringLayer(v7, RING_INNER))
      .child(div().absolute().inset_0().flex().items_center().justify_center().child(icon.flex_none()));
    const row = (v) =>
      h_flex()
        .h(15)
        .items_center()
        .gap(cells(1))
        // 使用率は "100%" の幅で右寄せ、残り時間は "16h42m" の幅で左寄せにして、行ごとに位置を揃える
        .child(
          h_flex()
            .flex_none()
            .w(cells(4))
            .justify_end()
            .text_color(v ? v.barColor : PALETTE.text)
            .child(v ? `${Math.round(v.used)}%` : ""),
        )
        .child(div().flex_none().w(cells(6)).text_color(v ? v.remainingColor : PALETTE.text).child(v?.remaining ?? ""));
    return v_flex().flex_none().items_center().child(ring).child(div().h(RING_GAP)).child(row(v5)).child(row(v7));
  }

  render() {
    const now = Date.now() / 1000;
    const claudeWindows = this.files["claude-code"]?.windows;
    const agyPools = this.files["agy"]?.pools;
    const agyPool = pickAgyPool(agyPools, now);
    const agyWindows = agyPools?.[agyPool];
    const claudeIcon = () => image("icons/claude.svg").w(CLAUDE_ICON_SIZE).h(CLAUDE_ICON_SIZE);
    const agyIcon =
      agyPool === "gemini"
        ? image("icons/antigravity.svg").w(ICON_SIZE).h(ICON_SIZE)
        : svg("icons/claude.svg").text_color(PALETTE.blue).w(CLAUDE_ICON_SIZE).h(CLAUDE_ICON_SIZE);

    return h_flex()
      .id("usage")
      .size_full()
      .pl(METRICS.padLeft)
      .pr(PAD_RIGHT)
      .items_center()
      .justify_around()
      .overflow_hidden()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .child(this.ringGroup(claudeWindows, claudeIcon(), now))
      .child(this.ringGroup(agyWindows, agyIcon, now));
  }
}
