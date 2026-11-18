// 枠の見出し。エージェントは、使用率の輪で囲んだマーク、名前、model、effort、右端に要約までの残り。
// それ以外は記号とフォルダ (paneLabel)。中身の組み立ては logic.js、記号と色と寸法は ui.js にある。
// 同梱の pane mod を元にした。props: { pane, terminal }。押すとその枠に移る
import { View, div, PathBuilder } from "gpui-kit";
import { h_flex } from "gpui-base";
import { home, panes, props, run, shared, theme } from "herdr";
import { METRICS, PALETTE, isRemoteAddress, mark, ringArc } from "./ui.js";
import { repoRoot, watchJsonDir } from "./data.js";
import { headerFor, isAgentPane } from "./logic.js";

const FONT = "Moralerspace Neon HW";
const TEXT = 12;
const SEP = " · ";

// コンテキストの使用率の輪。外径 METRICS.ring、12 時から時計回りに fraction の長さ (workspace と同じ)
function ringElement(fraction, color) {
  const box = div().relative().flex_none().w(METRICS.ring).h(METRICS.ring);
  const arc = ringArc(fraction, METRICS.ring, METRICS.ringStroke);
  if (!arc) return box;
  const { r, cx, cy, start, end, largeArc, full } = arc;
  let builder = PathBuilder.stroke(METRICS.ringStroke).move_to(...start);
  if (full) builder = builder.arc_to(r, r, 0, false, true, cx, cy + r).arc_to(r, r, 0, false, true, ...start);
  else builder = builder.arc_to(r, r, 0, largeArc, true, ...end);
  return box.child(window.paint_path(builder.build(), color).absolute().top(0).left(0).size_full());
}

export default class PaneHeader extends View {
  init(_props, cx) {
    this.sessions = {};
    this.roots = new Map(); // cwd → git のルート (null: git の外)。undefined のあいだは読んでいる
    this.watch = watchJsonDir(cx, "sessions", (files) => {
      this.sessions = files;
      cx.notify();
    });
  }

  close() {
    this.watch?.cancel();
  }

  rootOf(cwd, cx) {
    if (!cwd) return null;
    if (this.roots.has(cwd)) return this.roots.get(cwd) ?? null;
    this.roots.set(cwd, undefined);
    cx.spawn(async (cx) => {
      this.roots.set(cwd, await repoRoot(cwd));
      cx.notify();
    });
    return null;
  }

  // 輪とマークを同じ中心に重ねる
  agentMark(h) {
    const m = mark(h.name);
    const box = div()
      .relative()
      .flex_none()
      .w(METRICS.ring)
      .h(METRICS.ring)
      .flex()
      .items_center()
      .justify_center()
      .child(div().font_weight(700).text_color(m.color).child(m.letter));
    if (h.ring == null) return box;
    return box.child(div().absolute().top(0).left(0).child(ringElement(h.ring, h.ringColor)));
  }

  agent(el, h) {
    const detail = [h.model, h.effort].filter((s) => s != null && s !== "");
    return el
      .child(this.agentMark(h))
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .items_center()
          .child(div().flex_none().text_color(mark(h.name).color).child(h.name))
          .when(detail.length > 0, (row) =>
            row.child(div().truncate().text_color(PALETTE.subtext0).child(SEP + detail.join(SEP))),
          ),
      )
      .when(h.tokens != null, (row) => row.child(div().flex_none().text_color(h.tokensColor).child(h.tokens)));
  }

  plain(el, h) {
    return el
      .child(
        div()
          .flex_none()
          .w(METRICS.ring)
          .flex()
          .justify_center()
          .text_size(METRICS.glyphSize)
          .text_color(PALETTE.overlay0)
          .child(h.icon),
      )
      .child(div().flex_1().min_w(0).truncate().text_color(PALETTE.subtext0).child(h.text));
  }

  render(cx) {
    const p = panes().find((x) => x.pane === props()?.pane);
    if (!p) return div();
    // 別のコンピューターの枠では、このコンピューターのファイルと git を読まない (名前とフォルダ名だけ)
    const remote = isRemoteAddress(p.terminal);
    const names = shared("agent-names") ?? {};
    const h = headerFor({
      pane: p,
      session: remote || p.terminal == null ? null : (this.sessions[p.terminal] ?? null),
      name: p.terminal == null ? null : (names[p.terminal] ?? null),
      repoRoot: remote || isAgentPane(p) ? null : this.rootOf(p.cwd, cx),
      home: home(),
    });
    const t = theme();
    const el = h_flex()
      .id(`pane-header-${p.pane}`)
      .size_full()
      .px(10)
      .gap(8)
      .items_center()
      .bg(t.background)
      .border_b(1)
      .border_color(t.border)
      .font_family(FONT)
      .text_size(TEXT)
      .text_color(PALETTE.text)
      .on_click(() => run("pane.focus", { pane: p.pane }));
    return h.kind === "agent" ? this.agent(el, h) : this.plain(el, h);
  }
}
