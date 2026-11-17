// 大きさを変えるモードと、帯の 3 通りの切り替え。
// レイアウトの floating に置く。モードの間だけ「RESIZE」と描き、それ以外は何も描かない。
// コマンド: resize-mode.start (モードに入る)、resize-mode.cycle-sidebar (帯の出し分け)
// 判断は logic.js にある。ここは herdr とのやり取りだけ。

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { checking, focused, layout, nextCommand, run, theme } from "herdr";
import { keyToMove, nextSize, nextSidebarMode } from "./logic.js";

// 境目ごとの、動かすブロックと、レイアウトに値がないときの大きさ
const SIDEBAR = { id: "sidebar", min: 160, max: 480, fallback: 240 };
const PREVIEW = { id: "preview-area", min: 160, max: 1200, fallback: 480 };
const WORKSPACE = { id: "workspace", min: 80, max: 1200, fallback: 300 };

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// spec のブロックを delta だけ動かす。下限と上限はレイアウトの min/max を優先する
function resize(spec, delta) {
  const node = find(layout(), spec.id);
  if (!node) return;
  const min = Math.max(spec.min, node.min ?? 0);
  const max = Math.min(spec.max, node.max ?? Infinity);
  const current = node.size?.px ?? spec.fallback;
  run("layout.resize", { id: spec.id, px: nextSize(current, delta, min, max) });
}

// 帯の出し分け: both は両方、list は一覧 (workspace) だけ、tree はツリーだけ
function applySidebarMode(mode) {
  run(mode === "tree" ? "layout.hide" : "layout.show", { id: "workspace" });
  run(mode === "list" ? "layout.hide" : "layout.show", { id: "tree" });
}

function loadSidebarMode() {
  try {
    return localStorage.getItem("sidebar-mode") ?? "both";
  } catch {
    return "both";
  }
}

export default class ResizeMode extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.active = false;
    this.back = null; // モードに入る前のフォーカス
    this.sidebarMode = loadSidebarMode();
    if (checking()) return;
    applySidebarMode(this.sidebarMode);
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "start") this.start(cx);
        else if (c === "cycle-sidebar") this.cycleSidebar();
        else if (c === "focus" && this.active) this.handle.focus();
        cx.notify();
      }
    });
  }

  start(cx) {
    if (!this.active) {
      const f = focused();
      this.back = { pane: f?.pane ?? null, terminal: f?.terminal ?? null };
    }
    this.active = true;
    this.handle.focus();
    // 描く前は focus を受ける要素がないので、描いたあとにもう一度取る
    cx.timer.after(16, () => this.active && this.handle.focus());
  }

  // 枠にも端末のブロックにもフォーカスがなければ、帯の mod にあったとみなす
  inSidebar() {
    return !this.back?.pane && !this.back?.terminal;
  }

  exit() {
    this.active = false;
    const back = this.back;
    this.back = null;
    if (back?.pane) run("pane.focus", { pane: back.pane });
    else if (back?.terminal) run("pane.focus", { terminal: back.terminal });
    else run("pane.go", { direction: "left" });
  }

  cycleSidebar() {
    this.sidebarMode = nextSidebarMode(this.sidebarMode);
    try {
      localStorage.setItem("sidebar-mode", this.sidebarMode);
    } catch {
      // 覚えられなくても切り替えはする
    }
    applySidebarMode(this.sidebarMode);
  }

  key(e, cx) {
    const m = e.modifiers ?? {};
    if (m.control || m.alt || m.platform) return;
    const move = keyToMove(e.key);
    if (!move) return;
    if (move === "exit") this.exit();
    else if (move.target === "vertical") resize(this.inSidebar() ? SIDEBAR : PREVIEW, move.delta);
    else resize(WORKSPACE, move.delta);
    cx.stop_propagation();
    cx.notify();
  }

  render() {
    if (!this.active) return div();
    const t = theme();
    return h_flex()
      .id("resize-mode")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx))
      .h(22)
      .px(10)
      .items_center()
      .text_size(11)
      .font_semibold()
      .text_color(t.accent)
      .child("RESIZE");
  }
}
