// 利用制限 (5h、7d など)。data/limits/<種類>.json を見張り、種類ごとに名前の行と帯の行を出す。
// 出す種類は 3 つのモード (アクティブ、すべて、指定) で選び、usage.cycle-mode で切り替える。
// 表示の組み立ては logic.js、色と寸法は ui.js にある
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, checking, focused, nextCommand, theme } from "herdr";
import { METRICS, PALETTE, cells } from "./ui.js";
import { watchJsonDir } from "./data.js";
import { windowView } from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;
const PAD_Y = 6; // 上下の余白。レイアウトの高さ = METRICS.row × 行の数 + PAD_Y × 2
const BAR_HEIGHT = 6;
const MARK_HEIGHT = 12; // 経過の位置の縦線
const MODES = ["active", "all", "pinned"];

function load(key, fallback) {
  try {
    const text = localStorage.getItem(key);
    return text == null ? fallback : JSON.parse(text);
  } catch {
    return fallback;
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // 覚えられなくても表示はする
  }
}

const pct = (fraction) => `${Math.min(100, Math.max(0, fraction * 100))}%`;

export default class Usage extends View {
  init(_props, cx) {
    const mode = load("mode", "active");
    this.mode = MODES.includes(mode) ? mode : "active";
    const pinned = load("pinned", null);
    this.pinned = typeof pinned === "string" ? pinned : null;
    const lastApp = load("lastApp", null);
    this.lastApp = typeof lastApp === "string" ? lastApp : null;
    this.files = {};
    this.shown = []; // 直前に描いた種類 (pinned に入るときに使う)
    this.watch = watchJsonDir(cx, "limits", (files) => {
      this.files = files;
      cx.notify();
    });
    if (checking()) return;
    // 経過と残り時間を進める
    this.timer = cx.timer.every(60_000, (cx) => cx.notify());
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "cycle-mode") this.cycleMode();
        cx.notify();
      }
    });
  }

  close() {
    this.watch?.cancel();
    this.timer?.cancel();
  }

  cycleMode() {
    this.mode = "all";
    save("mode", this.mode);
    if (this.mode === "pinned" && this.shown.length > 0) {
      this.pinned = this.shown[0];
      save("pinned", this.pinned);
    }
  }

  // 今のタブのエージェントの種類。見えたら lastApp として覚える
  activeApp() {
    const f = focused();
    if (!f) return null;
    const inTab = agents().filter((a) => a.tab === f.tab && a.app);
    const agent = inTab.find((a) => a.focused) ?? inTab[0];
    const app = agent?.app ?? null;
    if (app && app !== this.lastApp) {
      this.lastApp = app;
      save("lastApp", app);
    }
    return app;
  }

  nameRow(name, t) {
    return h_flex().flex_none().h(METRICS.row).items_center().text_color(t.muted).child(div().truncate().child(name));
  }

  // 背景の棒に使用分を区切りの色で塗り、経過の位置に縦線、縦線より右の使用分を超過の色で塗る
  bar(v) {
    const track = div().relative().flex_1().min_w(0).h(BAR_HEIGHT).rounded(BAR_HEIGHT / 2).bg(PALETTE.surface0);
    const fill = (left, width, color) =>
      div().absolute().top(0).left(pct(left)).w(pct(width)).h_full().rounded(BAR_HEIGHT / 2).bg(color);
    const parts = [fill(0, v.used / 100, v.barColor)];
    if (v.elapsed != null) {
      if (v.overColor) parts.push(fill(v.elapsed, v.over, v.overColor));
      parts.push(
        div()
          .absolute()
          .top((BAR_HEIGHT - MARK_HEIGHT) / 2)
          .left(pct(v.elapsed))
          .w(1)
          .h(MARK_HEIGHT)
          .bg(PALETTE.text),
      );
    }
    return track.children(parts);
  }

  // 5h ━━━━│━━━   3% 4h50m。使用率は "100%" の幅を取って右に、残り時間は "4h50m" の幅を取って左に寄せ、
  // 帯の右端を行ごとに揃える。帯が残りの幅を埋める
  barRow(w, now, t) {
    const v = windowView(w, now);
    return h_flex()
      .flex_none()
      .h(METRICS.row)
      .items_center()
      .gap(cells(1))
      .child(div().flex_none().font_weight(700).text_color(v.barColor).child(String(w.key)))
      .child(h_flex().flex_1().min_w(0).items_center().child(this.bar(v)))
      .child(div().flex_none().w(cells(4)).flex().justify_end().text_color(v.usedColor).child(`${Math.round(v.used)}%`))
      .child(div().flex_none().w(cells(5)).text_color(t.dim).child(v.remaining ?? ""));
  }

  render() {
    const t = theme();
    const now = Date.now() / 1000;
    const list = Object.keys(this.files).sort();
    this.shown = list;
    const rows = [];
    for (const name of list) {
      const file = this.files[name] ?? {};
      rows.push(this.nameRow(file.name ?? name, t));
      for (const w of Array.isArray(file.windows) ? file.windows : []) rows.push(this.barRow(w, now, t));
    }
    return v_flex()
      .id("usage")
      .size_full()
      .pl(METRICS.padLeft)
      .pr(PAD_RIGHT)
      .py(PAD_Y)
      .overflow_hidden()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .children(rows);
  }
}
