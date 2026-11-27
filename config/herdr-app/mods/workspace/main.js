// 帯の一覧。space → タブ → エージェント → サブエージェント の構造の表示と、作業状態で並べる表示を持つ。
// 行の組み立ては logic.js、記号と色と寸法は ui.js にある
import { View, div, image, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import {
  agents,
  checking,
  exec,
  home,
  nextCommand,
  panes,
  run,
  setAgentOrder,
  spaces,
  terminals,
  theme,
} from "herdr";
import {
  GLYPH,
  METRICS,
  PALETTE,
  STATUS,
  agentIconSpec,
  arcSteps,
  cells,
  contextColor,
  contextPercent,
  isRemoteAddress,
  isRemoteSpace,
  paneLabel,
} from "./ui.js";
import { RETRY_MS, repoRootNow, watchJsonDir } from "./data.js";
import { describe, domainTag } from "./domains.js";
import {
  activityFor,
  agentOrder,
  agentTime,
  buildGroups,
  buildStructure,
  collectSubagents,
  contextFor,
  nestSpaces,
  nextTick,
  tabOpenKey,
  trackAgentTimes,
} from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;

// Moralerspace Neon HW (16px) の Nerd Font グリフは advance (8.4px) より実描画幅が広く、
// x=0 から右にはみ出して描かれるため、advance 幅のまま中央揃えすると右にずれる。
// 実描画幅を要素幅にして中央揃えすることで、SVG アイコン＋輪と中心を揃える
const GLYPH_WIDTH = {
  [GLYPH.spaceClosed]: 12,
  [GLYPH.spaceOpen]: 12,
  [GLYPH.shell]: 13.3,
  [GLYPH.yazi]: 13.3,
  [GLYPH.tabClosed]: 13.3,
  [GLYPH.tabOpen]: 13.3,
};

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

const sameJson = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// herdr のタブの時刻は ms と書かれていないので、秒で来たときは ms に直す
const toMs = (t) => (t == null ? null : t < 1e12 ? t * 1000 : t);

// 状態の印。構造の表示と状態の表示で同じものを使う (印の差し替えはここだけ)
function statusGlyph(status) {
  const s = STATUS[status];
  const box = div().flex_none().w(METRICS.glyphSize).h_full().flex().items_center().justify_center();
  if (!s) return box;
  return box.text_size(METRICS.glyphSize).text_color(PALETTE[s.color]).child(s.glyph);
}

function arcPath(from, to, outer, stroke) {
  const arc = arcSteps(from, to, outer, stroke);
  if (!arc) return null;
  let builder = PathBuilder.stroke(stroke).move_to(...arc.start);
  for (const pt of arc.points) builder = builder.arc_to(arc.r, arc.r, 0, false, true, ...pt);
  return builder.build();
}

// コンテキストの使用率の輪。全周に下地 (surface0) を敷き、12 時から時計回りに使用分を重ねる
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
  if (!spec) return div().w(METRICS.agentIcon).text_size(METRICS.agentIcon).text_color(PALETTE.overlay2).child(GLYPH.terminal);
  if (spec.tint) return svg(spec.src).text_color(spec.color ?? PALETTE.text).w(spec.size).h(spec.size);
  return image(spec.src).w(spec.size).h(spec.size);
}

export default class Workspace extends View {
  init(_props, cx) {
    const view = load("view", "structure");
    this.view = view === "status" ? "status" : "structure";
    const collapsed = load("collapsed", null);
    this.collapsed = new Set(Array.isArray(collapsed) ? collapsed : ["group:idle"]);
    const times = load("times", {});
    this.times = times && typeof times === "object" && !Array.isArray(times) ? times : {};
    this.sessions = {};
    this.repos = {};
    this.reposKey = null;
    this.reposAt = null; // 最後に読み終えた時刻 (ms)
    this.roots = new Map(); // cwd → git のルート (repoRootNow が使う)
    this.cursor = 0;
    this.rows = [];
    this.tick = null;
    this.tickAt = null; // 予約した描き直しの時刻 (ms)
    this.seenAgents = false; // 一度でも agents() が空でなかったか
    this.activePane = new Map(); // タブ -> 最後に focus された端末の pane (タブの名前に使う)
    this.handle = cx.focus_handle();
    this.scroll = ScrollHandle.new();
    this.watch = watchJsonDir(cx, "sessions", (files) => {
      this.sessions = files;
      cx.notify();
    });
    this.activity = {};
    this.activityWatch = watchJsonDir(cx, "activity", (files) => {
      this.activity = files;
      cx.notify();
    });
    if (checking()) return;
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "toggle-view") this.toggleView();
        else if (c === "focus") this.handle.focus();
        cx.notify();
      }
    });
  }

  close() {
    this.watch?.cancel();
    this.activityWatch?.cancel();
    this.tick?.cancel();
    this.tick = null;
  }

  toggleView() {
    this.view = this.view === "structure" ? "status" : "structure";
    this.cursor = 0;
    save("view", this.view);
  }

  toggle(key) {
    if (this.collapsed.has(key)) this.collapsed.delete(key);
    else this.collapsed.add(key);
    save("collapsed", [...this.collapsed]);
  }

  // space ごとの git の場所 (worktree の入れ子に使う)。folder が変わったときに読み直す。
  // git の外 (または時間切れ) の space があれば、RETRY_MS たったら読み直す (後からの git init を拾う)
  refreshRepos(list, cx) {
    const local = list.filter((s) => !isRemoteSpace(s));
    const key = JSON.stringify(local.map((s) => [s.id, s.folder]));
    const missing = this.reposAt != null && local.some((s) => !this.repos[s.id]);
    if (key === this.reposKey && !(missing && Date.now() - this.reposAt >= RETRY_MS)) return;
    this.reposKey = key;
    this.reposAt = null; // 読んでいるあいだは読み直さない
    cx.spawn(async (cx) => {
      const repos = {};
      for (const space of local) {
        try {
          const r = await exec(
            "git",
            ["rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir"],
            { cwd: space.folder, timeout: 3000 },
          );
          const [top, common] = r.stdout.trim().split("\n");
          if (r.code === 0 && top && common) repos[space.id] = { top, common };
        } catch {
          // git の外、または時間切れ
        }
      }
      if (this.reposKey !== key) return;
      this.reposAt = Date.now();
      if (sameJson(repos, this.repos)) return;
      this.repos = repos;
      cx.notify();
    });
  }

  rootOf(cwd, cx) {
    return repoRootNow(this.roots, cwd, cx);
  }

  // タブの名前と記号。rename した名前、最後に focus された pane の名前、最初のエージェントのプログラム名、
  // 最初の端末の pane の名前の順。エージェントの pane の名前はプログラム名
  tabLabel(row, spaceById, allPanes, liveAgents, cx) {
    const activeId = this.activePane.get(row.tabId);
    const active = activeId ? allPanes.find((p) => p.pane === activeId && p.tab === row.tabId && p.terminal) : null;
    const pane = active ?? allPanes.find((p) => p.tab === row.tabId && p.terminal);
    const label = this.paneText(pane, row.spaceId, spaceById, cx);
    if (row.label) return { ...label, text: row.label };
    if (active) {
      const agent = liveAgents.find((a) => a.pane === active.pane);
      return agent?.program?.name ? { ...label, text: agent.program.name } : label;
    }
    if (row.program?.name) return { ...label, text: row.program.name };
    return label;
  }

  // エージェントのいない端末の pane の名前と記号。名前は枠の見出しと同じ決まり
  paneText(pane, spaceId, spaceById, cx) {
    const program = pane?.program;
    const processName = program ? (program.key === "program" ? program.name : program.key) : "";
    if (!pane) return { icon: GLYPH.shell, text: "" };
    const remote = isRemoteSpace(spaceById.get(spaceId)) || isRemoteAddress(pane.pane);
    // 記号も枠の見出しと同じ paneLabel の値を使う
    return paneLabel({
      programKey: program?.key,
      processName,
      shell: Boolean(program?.shell),
      cwd: pane.cwd,
      repoRoot: remote ? null : this.rootOf(pane.cwd, cx),
      home: home(),
    });
  }

  updateTimes(liveAgents, spaceList, now) {
    if (!this.seenAgents) return; // 起動の直後
    const tabs = new Map(spaceList.flatMap((s) => s.tabs.map((t) => [t.id, t])));
    const fallback = {};
    for (const a of liveAgents) {
      const tab = tabs.get(a.tab);
      const since = a.status === "working" ? toMs(tab?.working_since) : null;
      fallback[a.address] = { since: since ?? toMs(tab?.changed_at) };
    }
    const next = trackAgentTimes(this.times, liveAgents, now, fallback);
    if (!sameJson(next, this.times)) {
      this.times = next;
      save("times", next);
    }
  }

  // 時間の文字が次に変わるときに 1 回だけ描き直す。今いるエージェントの記録だけを見る。
  // 予約があっても、それより早く変わる文字ができたら (新しく作業を始めたなど) 予約し直す
  schedule(liveAgents, now, cx) {
    if (checking()) return;
    const live = {};
    for (const a of liveAgents) if (this.times[a.address]) live[a.address] = this.times[a.address];
    const wait = nextTick(live, now);
    if (wait == null) {
      this.tick?.cancel();
      this.tick = null;
      this.tickAt = null;
      return;
    }
    const at = now + wait;
    if (this.tick && this.tickAt <= at) return;
    this.tick?.cancel();
    this.tickAt = at;
    this.tick = cx.timer.after(wait, (cx) => {
      this.tick = null;
      this.tickAt = null;
      cx.notify();
    });
  }

  activate(row) {
    if (!row) return;
    if (row.kind === "space" || row.kind === "group") this.toggle(row.key);
    else if (row.kind === "tab") run("tab.select", { id: row.tabId });
    else if (row.kind === "pane") run("pane.focus", { pane: row.paneId });
    else if (row.kind === "agent" || row.kind === "sub") run("agent.focus", { terminal: row.address });
  }

  key(e, cx) {
    const m = e.modifiers ?? {};
    if (m.control || m.alt || m.platform) return;
    const last = Math.max(0, this.rows.length - 1);
    if (e.key === "j") this.cursor = Math.min(last, this.cursor + 1);
    else if (e.key === "k") this.cursor = Math.max(0, this.cursor - 1);
    else if (e.key === "enter") this.activate(this.rows[this.cursor]);
    else if (e.key === "escape") run("pane.go", { direction: "right" });
    else return;
    if (this.cursor < this.rows.length) this.scroll.scroll_to_item(this.cursor);
    cx.stop_propagation();
    cx.notify();
  }

  // [段 × 字下げ][記号の枠][間][名前 …][右端]
  // baseline: まとまりの見出し。印を木構造の記号の枠ではなく、帯の全体の記号の列 (glyphCol) に置く
  // second: 2 行目の文 (状態の表示のエージェントの行だけ)。名前の文字の頭に揃え、上を 2px 空ける
  row(r, i, { slot, name, right = [], onClick, focused, baseline = false, second = null }) {
    const indent = METRICS.padLeft + r.depth * cells(METRICS.indentCells);
    const line = h_flex()
      .flex_none()
      .w_full()
      .h(METRICS.row)
      .pl(indent)
      .pr(PAD_RIGHT)
      .items_center()
      .child(
        div()
          .relative()
          .flex_none()
          .w(baseline ? METRICS.glyphCol : cells(METRICS.slotCells))
          .h_full()
          .flex()
          .items_center()
          .when(!baseline, (el) => el.justify_center())
          .children(slot),
      )
      .when(!baseline, (el) => el.child(div().flex_none().w(cells(METRICS.gapCells))))
      .child(h_flex().flex_1().min_w(0).gap(cells(1)).items_center().children(name))
      .children(right);
    const nameLeft = indent + (baseline ? METRICS.glyphCol : cells(METRICS.slotCells + METRICS.gapCells));
    const el = second
      ? v_flex()
          .flex_none()
          .w_full()
          .child(line)
          .child(
            div()
              .flex_none()
              .w_full()
              .pt(2)
              .pl(nameLeft)
              .pr(PAD_RIGHT)
              .child(div().truncate().text_color(theme().dim).child(second)),
          )
      : line;
    return el
      .id(`row-${r.key}`)
      .when(focused && i === this.cursor, (el) => el.bg(PALETTE.surface0))
      .on_click((_e, cx) => {
        this.cursor = i;
        onClick?.(cx);
        cx.notify();
      });
  }

  // 分野の札。muted の枠付きの小さな字
  tag(text) {
    const color = theme().muted;
    return div()
      .flex_none()
      .mr(cells(1))
      .px(4)
      .border_1()
      .border_color(color)
      .rounded(3)
      .text_size(METRICS.fontSize - 2)
      .text_color(color)
      .child(text);
  }

  glyph(text, color) {
    const w = GLYPH_WIDTH[text];
    return div()
      .flex_none()
      .when(w != null, (el) => el.w(w))
      .text_size(METRICS.glyphSize)
      .text_color(color)
      .child(text);
  }

  rightSide(r, now) {
    const time = r.kind === "agent" ? agentTime(this.times[r.address], now) : null;
    return [
      ...(time ? [div().flex_none().pr(cells(1)).text_color(PALETTE.subtext0).child(time)] : []),
      statusGlyph(r.status),
    ];
  }

  // 輪とアイコンを記号の枠の中心に合わせて重ねる。輪は枠からはみ出してよい
  agentSlot(r) {
    const slot = [];
    const session = contextFor(r.address, this.sessions);
    const pct = contextPercent(session?.context);
    const offset = (cells(METRICS.slotCells) - METRICS.ring) / 2;
    slot.push(
      div()
        .absolute()
        .left(offset)
        .top((METRICS.row - METRICS.ring) / 2)
        .child(ringElement(pct == null ? 0 : Math.min(1, pct / 100), pct == null ? null : contextColor(pct))),
    );
    slot.push(agentIcon(r.program, session?.model ?? null).flex_none());
    if (r.hasChildren) slot.push(this.chevron(r, r.key));
    return slot;
  }

  // 記号の左の列に置く開閉の矢印
  chevron(r, toggleKey) {
    return div()
          .id(`chev-${r.key}`)
          .absolute()
          .left(-cells(METRICS.indentCells))
          .top(0)
          .w(cells(METRICS.slotCells))
          .h_full()
          .flex()
          .items_center()
          .justify_center()
          .text_size(METRICS.glyphSize)
          .text_color(PALETTE.overlay2)
          .on_click((_e, cx) => {
            cx.stop_propagation();
            this.toggle(toggleKey);
            cx.notify();
          })
          .child(r.open ? GLYPH.chevronDown : GLYPH.chevronRight);
  }

  renderRow(r, i, ctx) {
    const { now, focused } = ctx;
    const base = { focused };
    if (r.kind === "space") {
      return this.row(r, i, {
        ...base,
        slot: [this.glyph(r.open ? GLYPH.spaceOpen : GLYPH.spaceClosed, PALETTE.mauve)],
        name: [div().truncate().text_color(PALETTE.text).child(r.label)],
        right: [statusGlyph(r.status)],
        onClick: () => this.toggle(r.key),
      });
    }
    if (r.kind === "tab") {
      const label = this.tabLabel(r, ctx.spaceById, ctx.panes, ctx.liveAgents, ctx.cx);
      return this.row(r, i, {
        ...base,
        // 複数 pane のタブは開閉で変わるタブの記号 (押すと開閉)、pane が 1 つならその pane の記号 (枠の見出しと同じ)
        slot: [
          r.hasChildren
            ? this.glyph(r.open ? GLYPH.tabOpen : GLYPH.tabClosed, PALETTE.overlay0)
                .id(`tab-toggle-${r.tabId}`)
                .on_click((_e, cx) => {
                  cx.stop_propagation();
                  this.toggle(tabOpenKey(r.tabId));
                  cx.notify();
                })
            : this.glyph(label.icon, PALETTE.overlay0),
        ],
        name: [div().truncate().text_color(PALETTE.subtext0).child(label.text)],
        right: [statusGlyph(r.status)],
        onClick: () => run("tab.select", { id: r.tabId }),
      });
    }
    if (r.kind === "pane") {
      const label = this.paneText(ctx.panes.find((p) => p.pane === r.paneId), r.spaceId, ctx.spaceById, ctx.cx);
      return this.row(r, i, {
        ...base,
        slot: [this.glyph(label.icon, PALETTE.overlay0)],
        name: [div().truncate().text_color(PALETTE.subtext0).child(label.text)],
        onClick: () => run("pane.focus", { pane: r.paneId }),
      });
    }
    if (r.kind === "agent") {
      const name = [div().flex_none().text_color(PALETTE.text).child(r.label)];
      let second = null;
      // 札と 2 行目は状態の表示でだけ出す
      if (this.view === "status") {
        if (r.spaceName) name.push(div().truncate().text_color(PALETTE.overlay2).child(r.spaceName));
        const actions = activityFor(r.address, this.activity, ctx.liveAgents, this.sessions)?.actions;
        const list = Array.isArray(actions) ? actions.filter((a) => a && typeof a === "object") : [];
        const tag = domainTag(list);
        if (tag) name.push(this.tag(tag));
        second = describe(list[0] ?? null);
      }
      return this.row(r, i, {
        ...base,
        second,
        slot: this.agentSlot(r),
        name,
        right: this.rightSide(r, now),
        onClick: () => run("agent.focus", { terminal: r.address }),
      });
    }
    if (r.kind === "sub") {
      return this.row(r, i, {
        ...base,
        slot: [],
        name: [div().truncate().text_color(PALETTE.overlay2).child(r.label)],
        right: [statusGlyph(r.status)],
        onClick: () => run("agent.focus", { terminal: r.address }),
      });
    }
    // まとまりの見出し: 一番左の列に印、名前、右端に数 (畳んだときは数の前に矢印)
    return this.row(r, i, {
      ...base,
      baseline: true,
      slot: [statusGlyph(r.status)],
      name: [div().truncate().font_weight(700).text_color(PALETTE.text).child(r.label)],
      right: [
        ...(r.open ? [] : [this.glyph(GLYPH.chevronRight, PALETTE.overlay2)]),
        div().flex_none().w(METRICS.glyphSize).flex().justify_end().text_color(PALETTE.subtext0).child(String(r.count)),
      ],
      onClick: () => this.toggle(r.key),
    });
  }

  render(cx) {
    const now = Date.now();
    const liveAgents = agents();
    if (liveAgents.length > 0) this.seenAgents = true;
    const spaceList = spaces();
    this.refreshRepos(spaceList, cx);
    this.updateTimes(liveAgents, spaceList, now);
    const subagents = collectSubagents(liveAgents, this.activity, terminals(), this.sessions, now);
    const allPanes = panes();
    for (const p of allPanes) if (p.focused && p.terminal) this.activePane.set(p.tab, p.pane);
    const input = { agents: liveAgents, subagents, sessions: this.sessions, collapsed: this.collapsed };
    const rows =
      this.view === "status"
        ? buildGroups(input)
        : buildStructure({ ...input, nested: nestSpaces(spaceList, this.repos), panes: allPanes.filter((p) => p.terminal) });
    this.rows = rows;
    this.cursor = Math.min(this.cursor, Math.max(0, rows.length - 1));
    setAgentOrder(agentOrder(rows));
    this.schedule(liveAgents, now, cx);
    const ctx = {
      now,
      cx,
      liveAgents,
      focused: this.handle.is_focused(),
      panes: allPanes,
      spaceById: new Map(spaceList.map((s) => [s.id, s])),
    };
    return v_flex()
      .id("workspace")
      .size_full()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx))
      .child(
        v_flex()
          .id("workspace-list")
          .flex_1()
          .min_h(0)
          .overflow_y_scrollbar()
          .track_scroll(this.scroll)
          .children(rows.map((r, i) => this.renderRow(r, i, ctx))),
      );
  }
}
