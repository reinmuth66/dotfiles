// 枠の見出し。エージェントは、使用率の輪で囲んだアイコン、model (無ければプログラム名)、effort、右端に要約までの残り。
// それ以外は記号とフォルダ (paneLabel)。中身の組み立ては logic.js、記号と色と寸法は ui.js にある。
// 同梱の pane mod を元にした。props: { pane, terminal }。押すとその枠に移る
import { View, div, image, svg, PathBuilder } from "gpui-kit";
import { h_flex } from "gpui-base";
import { focused, home, panes, props, run, theme } from "herdr";
import { GLYPH, GLYPH_INK, METRICS, PALETTE, agentIconSpec, arcSteps, isRemoteAddress, tone, toneColor } from "./ui.js";
import { repoRootNow, watchJsonDir } from "./data.js";
import { headerFor, isAgentPane } from "./logic.js";

const FONT = "Moralerspace Neon HW";
// 端末と同じ大きさ (settings.json の font_size)。文字の始まり (padLeft + 輪 + gap = 34px) が端末の 4 文字目の位置に
// 重なるので、同じ大きさにすると下の端末の文字と列が揃う
const TEXT = 13;
const SEP = " · ";

function arcPath(from, to, outer, stroke) {
  const arc = arcSteps(from, to, outer, stroke);
  if (!arc) return null;
  let builder = PathBuilder.stroke(stroke).move_to(...arc.start);
  for (const pt of arc.points) builder = builder.arc_to(arc.r, arc.r, 0, false, true, ...pt);
  return builder.build();
}

// コンテキストの使用率の輪。全周に下地 (surface0) を敷き、12 時から時計回りに使用分を重ねる (workspace と同じ)
function ringElement(fraction, color) {
  const layers = [];
  const add = (from, to, c) => {
    const path = arcPath(from, to, METRICS.ring, METRICS.ringStroke);
    if (path) layers.push(window.paint_path(path, c).absolute().top(0).left(0).size_full());
  };
  add(0, 1, PALETTE.surface0);
  if (fraction > 0 && color) add(0, fraction, color);
  return div().relative().flex_none().w(METRICS.ring).h(METRICS.ring).children(layers);
}

function agentIcon(program, model) {
  const spec = agentIconSpec(program, model);
  if (!spec) return div().text_size(METRICS.agentIcon).text_color(PALETTE.overlay2).child(GLYPH.terminal);
  if (spec.tint) return svg(spec.src).text_color(spec.color ?? PALETTE.text).w(spec.size).h(spec.size);
  return image(spec.src).w(spec.size).h(spec.size);
}

export default class PaneHeader extends View {
  init(_props, cx) {
    this.sessions = {};
    this.roots = new Map(); // cwd → git のルート (repoRootNow が使う)
    this.watch = watchJsonDir(cx, "sessions", (files) => {
      this.sessions = files;
      cx.notify();
    });
  }

  close() {
    this.watch?.cancel();
  }

  rootOf(cwd, cx) {
    return repoRootNow(this.roots, cwd, cx);
  }

  // 輪とアイコンを同じ中心に重ねる
  agentMark(h) {
    return div()
      .relative()
      .flex_none()
      .w(METRICS.ring)
      .h(METRICS.ring)
      .flex()
      .items_center()
      .justify_center()
      .child(div().absolute().top(0).left(0).child(ringElement(h.ring, h.ringColor)))
      .child(agentIcon(h.program, h.model).flex_none());
  }

  agent(el, h, c) {
    return el
      .child(this.agentMark(h))
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .items_center()
          .child(div().flex_none().text_color(c.name).child(h.label))
          .when(Boolean(h.effort), (row) => row.child(div().truncate().text_color(c.extra).child(SEP + h.effort))),
      )
      .when(h.tokens != null, (row) => row.child(div().flex_none().text_color(c.tokens).child(h.tokens)));
  }

  // 記号は送り幅より広く右へはみ出すので、見た目の幅 (GLYPH_INK) の箱に入れてから輪の幅の中央に寄せる
  plain(el, h, c) {
    const ink = GLYPH_INK[h.icon];
    return el
      .child(
        div()
          .flex_none()
          .w(METRICS.ring)
          .flex()
          .justify_center()
          .child(
            div()
              .flex_none()
              .when(ink != null, (g) => g.w(ink))
              .text_size(METRICS.glyphSize)
              .text_color(PALETTE.overlay0)
              .child(h.icon),
          ),
      )
      .child(div().flex_1().min_w(0).truncate().text_color(c.name).child(h.text));
  }

  render(cx) {
    const p = panes().find((x) => x.pane === props()?.pane);
    if (!p) return div();
    // 別のコンピューターの枠では、このコンピューターのファイルと git を読まない (名前とフォルダ名だけ)
    const remote = isRemoteAddress(p.terminal);
    const h = headerFor({
      pane: p,
      session: remote || p.terminal == null ? null : (this.sessions[p.terminal] ?? null),
      repoRoot: remote || isAgentPane(p) ? null : this.rootOf(p.cwd, cx),
      home: home(),
    });
    const t = theme();
    const el = h_flex()
      .id(`pane-header-${p.pane}`)
      .size_full()
      .px(METRICS.padLeft)
      .gap(8)
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .font_family(FONT)
      .text_size(TEXT)
      .text_color(PALETTE.text)
      .on_click(() => run("pane.focus", { pane: p.pane }));
    // focus している枠だけ濃く (TONE)
    const on = focused()?.pane === p.pane;
    const c = { ...tone(on), tokens: toneColor(h.tokensColor, on) };
    return h.kind === "agent" ? this.agent(el, h, c) : this.plain(el, h, c);
  }
}
