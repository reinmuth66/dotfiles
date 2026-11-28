// 大きさを変えるモードと、帯の 3 通りの切り替え、wtr の出し入れ。
// レイアウトの floating に置く。モードの間だけ「RESIZE」と描き、それ以外は何も描かない。
// コマンド: resize-mode.start (モードに入る)、resize-mode.cycle-sidebar (帯の出し分け)、resize-mode.wtr (wtr の出し入れ)
// 判断は logic.js にある。ここは herdr とのやり取りだけ。

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { checking, focused, layout, nextCommand, run, theme } from "herdr";
import { keyToMove, nextSize, nextSidebarMode, wtrStep, LIMITS, STEP } from "./logic.js";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

function currentFocus() {
  const f = focused();
  return { pane: f?.pane ?? null, terminal: f?.terminal ?? null };
}

function focusTarget(back) {
  if (back?.pane) run("pane.focus", { pane: back.pane });
  else if (back?.terminal) run("pane.focus", { terminal: back.terminal });
  else return false;
  return true;
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
    this.wtrBack = null; // wtr を開く前のフォーカス
    this.sidebarMode = loadSidebarMode();
    if (checking()) return;
    applySidebarMode(this.sidebarMode);
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "start") this.start(cx);
        else if (c === "cycle-sidebar") this.cycleSidebar();
        else if (c === "wtr") this.toggleWtr(cx);
        else if (c === "focus" && this.active) this.handle.focus();
        cx.notify();
      }
    });
  }

  start(cx) {
    if (!this.active) this.back = currentFocus();
    this.active = true;
    this.handle.focus();
    // 描く前は focus を受ける要素がないので、描いたあとにもう一度取る
    cx.timer.after(16, () => this.active && this.handle.focus());
    // クリックなどでフォーカスが外へ出たら、モードを畳む (RESIZE の表示を残さない)
    if (!this.watching) {
      this.watching = true;
      cx.timer.every(200, (cx) => {
        if (this.active && this.focusedOnce && !this.handle.is_focused()) {
          this.collapse();
          cx.notify();
        }
        if (this.active && this.handle.is_focused()) this.focusedOnce = true;
      });
    }
  }

  // フォーカスは動かさずに、モードだけを畳む (修飾キー付きの操作や、外へのクリックのとき)
  collapse() {
    this.active = false;
    this.back = null;
    this.focusedOnce = false;
  }

  exit() {
    this.focusedOnce = false;
    this.active = false;
    const back = this.back;
    this.back = null;
    if (!focusTarget(back)) run("pane.go", { direction: "left" });
  }

  toggleWtr(cx) {
    const area = find(layout(), "preview-area");
    if (!area) return;
    const step = wtrStep({
      hidden: Boolean(area.hidden),
      active: area.active ?? null,
      onWtr: focused()?.terminal === "wtr",
    });
    if (step === "show") {
      this.wtrBack = currentFocus();
      run("layout.show", { id: "preview-area" });
      run("layout.select", { stack: "preview-area", child: "wtr" });
      // 欄が出た直後でないと pane.focus が no such pane で失敗する
      cx.timer.after(50, () => run("pane.focus", { terminal: "wtr" }));
    } else if (step === "focus") {
      this.wtrBack = currentFocus();
      run("pane.focus", { terminal: "wtr" });
    } else {
      run("layout.hide", { id: "preview-area" });
      const back = this.wtrBack;
      this.wtrBack = null;
      if (!focusTarget(back)) run("pane.go", { direction: "left" });
    }
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
    const move = keyToMove(e.key, e.modifiers ?? {});
    if (!move) return;
    if (move === "collapse") {
      // キーは止めずに global の操作 (cmd-l の pane.go など) に渡す
      this.collapse();
      cx.notify();
      return;
    }
    if (move === "exit") this.exit();
    // focus はこの mod にあるので、モードに入る前の pane を名指しする
    else if (move.target === "pane") {
      if (this.back?.pane) run("pane.resize", { direction: move.direction, pane: this.back.pane, px: STEP });
    } else resize(LIMITS[move.target], move.delta);
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
