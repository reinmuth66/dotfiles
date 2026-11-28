// 帯の一覧。space → タブ → エージェント → サブエージェント の構造の表示と、作業状態で並べる表示を持つ。
// 行の組み立ては logic.js、記号と色と寸法は ui.js にある
import { View, div, image, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import {
  agents,
  checking,
  exec,
  focused,
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
  GLYPH_INK,
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
  tone,
} from "./ui.js";
import { RETRY_MS, repoRootNow, watchJsonDir } from "./data.js";
import { describe, domainTag } from "./domains.js";
import {
  activityFor,
  agentOrder,
  agentTime,
  buildGroups,
  buildStructure,
  closeKey,
  collectSubagents,
  contextFor,
  effectiveCollapsed,
  focusContainers,
  highlightKey,
  isFocusRow,
  moveTarget,
  nestSpaces,
  nextTick,
  openKey,
  pruneHeld,
  stepAgent,
  stepGroup,
  stepSpace,
  stepTab,
  trackAgentTimes,
} from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;

// space の記号の右端から名前までを、tree のフォルダ (閉じた f07b) の記号の右端から名前までに揃える。
// tree は記号を送り幅 (16px で 8.4px) のまま枠の中央に置き、f07b の描画の右端は 14.77px (フォントから測った値)。
// space の記号は GLYPH_INK の幅の箱で枠の中央に置く
const TREE_FOLDER_GAP = cells(METRICS.slotCells + METRICS.gapCells) - ((cells(METRICS.slotCells) - 8.4) / 2 + 14.77);
const SPACE_GAP = (cells(METRICS.slotCells) + GLYPH_INK[GLYPH.space]) / 2 + TREE_FOLDER_GAP - cells(METRICS.slotCells);


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

// コンテキストの使用率の輪。全周に下地を敷き、12 時から時計回りに使用分を重ねる。
// 下地は surface0。ハイライトの行は背景が surface0 なので surface2 にする
function ringElement(fraction, color, highlight) {
  const layers = [];
  const add = (from, to, c) => {
    const path = arcPath(from, to, METRICS.ring, METRICS.ringStroke);
    if (path) layers.push(window.paint_path(path, c).absolute().top(0).left(0).size_full());
  };
  add(0, 1, highlight ? PALETTE.surface2 : PALETTE.surface0);
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
    this.held = new Set(); // focus 中に自分で閉じた鍵
    const times = load("times", {});
    this.times = times && typeof times === "object" && !Array.isArray(times) ? times : {};
    this.sessions = {};
    this.repos = {};
    this.reposKey = null;
    this.reposAt = null; // 最後に読み終えた時刻 (ms)
    this.roots = new Map(); // cwd → git のルート (repoRootNow が使う)
    this.tick = null;
    this.tickAt = null; // 予約した描き直しの時刻 (ms)
    this.seenAgents = false; // 一度でも agents() が空でなかったか
    this.activePane = new Map(); // タブ -> 最後に focus された端末の pane (タブの代表に使う)
    this.scroll = ScrollHandle.new();
    this.lastHighlightIndex = -1;
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
        this.handleCommand(c);
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
    save("view", this.view);
  }

  // 自動で開いた行を閉じる場合もあるため、開閉は反転ではなく明示的に設定する
  setOpen(key, open, containers = []) {
    if (open) {
      this.collapsed.delete(key);
      this.held.delete(key);
    } else {
      this.collapsed.add(key);
      if (containers.includes(key)) this.held.add(key);
    }
    save("collapsed", [...this.collapsed]);
  }

  handleCommand(c) {
    if (c === "toggle-view") {
      this.toggleView();
      return;
    }
    const focus = focused();
    const spaceList = spaces();
    const liveAgents = agents();
    const nested = nestSpaces(spaceList, this.repos);
    const groups = () =>
      buildGroups({ agents: liveAgents, subagents: {}, sessions: this.sessions, collapsed: new Set(), times: this.times });

    if (c === "next" || c === "prev") {
      const dir = c === "next" ? 1 : -1;
      if (this.view === "structure") {
        const id = stepTab(nested, focus, dir);
        if (id != null) run("tab.select", { id });
      } else {
        const terminal = stepAgent(groups(), focus, dir);
        if (terminal != null) run("agent.focus", { terminal });
      }
      return;
    }
    if (c === "next-group" || c === "prev-group") {
      const dir = c === "next-group" ? 1 : -1;
      if (this.view === "structure") {
        const id = stepSpace(nested, focus, dir);
        if (id != null) run("space.select", { id });
      } else {
        const terminal = stepGroup(groups(), focus, dir);
        if (terminal != null) run("agent.focus", { terminal });
      }
      return;
    }
    if (c === "move-down" || c === "move-up" || c === "move-group-down" || c === "move-group-up") {
      if (this.view !== "structure") return;
      const dir = c === "move-down" || c === "move-group-down" ? 1 : -1;
      const level = c === "move-group-down" || c === "move-group-up" ? "space" : "tab";
      const target = moveTarget(nested, focus, dir, level);
      if (target) run(target.command, target.args);
      return;
    }
    if (c === "open" || c === "open-group" || c === "close" || c === "close-group") {
      const level = c === "open-group" || c === "close-group" ? "group" : "small";
      // 開閉できるのは状態の表示だけ
      if (this.view !== "status") return;
      const containers = focusContainers({ view: this.view, agents: liveAgents, focus });
      this.held = pruneHeld(this.held, containers);
      const collapsed = effectiveCollapsed(this.collapsed, containers, this.held);
      const subagents = collectSubagents(liveAgents, this.activity, terminals(), this.sessions, Date.now());
      const rows = buildGroups({ agents: liveAgents, subagents, sessions: this.sessions, collapsed, times: this.times });
      const opening = c === "open" || c === "open-group";
      const key = opening ? openKey(rows, focus, containers, level) : closeKey(rows, focus, containers, level);
      if (key) this.setOpen(key, opening, containers);
    }
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

  // タブの名前と記号。記号は代表の pane のもの、名前は rename した名前か代表の pane の名前
  tabLabel(row, spaceById, allPanes, cx) {
    const pane = allPanes.find((p) => p.pane === row.paneId && p.terminal);
    const label = this.paneText(pane, row.spaceId, spaceById, cx);
    return row.label ? { ...label, text: row.label } : label;
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

  // [段 × 字下げ][記号の枠][間][名前 …][右端]
  // baseline: まとまりの見出し。印を木構造の記号の枠ではなく、帯の全体の記号の列 (glyphCol) に置く
  // second: 2 行目の文 (状態の表示のエージェントの行だけ)。名前の文字の頭に揃え、上を 2px 空ける
  // gap: 記号の枠と名前の間 (px)
  row(r, { slot, name, right = [], onClick, onSlotClick = null, highlight = false, baseline = false, second = null, gap = cells(METRICS.gapCells) }) {
    const indent = METRICS.padLeft + r.depth * cells(METRICS.indentCells);
    const slotBox = div()
      .relative()
      .flex_none()
      .w(baseline ? METRICS.glyphCol : cells(METRICS.slotCells))
      .h_full()
      .flex()
      .items_center()
      .when(!baseline, (el) => el.justify_center())
      .when(onSlotClick, (el) =>
        el.id(`slot-${r.key}`).on_click((_e, cx) => {
          cx.stop_propagation();
          onSlotClick(cx);
          cx.notify();
        }),
      )
      .children(slot);
    const line = h_flex()
      .flex_none()
      .w_full()
      .h(METRICS.row)
      .pl(indent)
      .pr(PAD_RIGHT)
      .items_center()
      .child(slotBox)
      .when(!baseline, (el) => el.child(div().flex_none().w(gap)))
      .child(h_flex().flex_1().min_w(0).gap(cells(1)).items_center().children(name))
      .children(right);
    const nameLeft = indent + (baseline ? METRICS.glyphCol : cells(METRICS.slotCells) + gap);
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
      .when(highlight, (el) => el.bg(PALETTE.surface0))
      .on_click((_e, cx) => {
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
    // 見た目の幅の箱にして中央に寄せ、SVG のアイコンと輪に中心を揃える (GLYPH_INK)
    const w = GLYPH_INK[text];
    return div()
      .flex_none()
      .when(w != null, (el) => el.w(w))
      .text_size(METRICS.glyphSize)
      .text_color(color)
      .child(text);
  }

  rightSide(r, now, c) {
    const time = r.kind === "agent" ? agentTime(this.times[r.address], now) : null;
    return [
      ...(time ? [div().flex_none().pr(cells(1)).text_color(c.extra).child(time)] : []),
      statusGlyph(r.status),
    ];
  }

  // 輪とアイコンを記号の枠の中心に合わせて重ねる。輪は枠からはみ出してよい
  agentSlot(r, highlight) {
    const slot = [];
    const session = contextFor(r.address, this.sessions);
    const pct = contextPercent(session?.context);
    const offset = (cells(METRICS.slotCells) - METRICS.ring) / 2;
    slot.push(
      div()
        .absolute()
        .left(offset)
        .top((METRICS.row - METRICS.ring) / 2)
        .child(ringElement(pct == null ? 0 : Math.min(1, pct / 100), pct == null ? null : contextColor(pct), highlight)),
    );
    slot.push(agentIcon(r.program, session?.model ?? null).flex_none());
    return slot;
  }

  renderRow(r, ctx) {
    const { now } = ctx;
    const base = { highlight: r.key === ctx.highlight };
    const c = tone(isFocusRow(r, ctx.focus));
    if (r.kind === "space") {
      return this.row(r, {
        ...base,
        gap: SPACE_GAP,
        slot: [this.glyph(GLYPH.space, PALETTE.mauve)],
        name: [div().truncate().text_color(c.name).child(r.label)],
        onClick: () => run("space.select", { id: r.spaceId }),
      });
    }
    if (r.kind === "tab") {
      // タブの代表の pane (最後に focus された pane) の記号と名前 (枠の見出しと同じ)
      const label = this.tabLabel(r, ctx.spaceById, ctx.panes, ctx.cx);
      return this.row(r, {
        ...base,
        slot: [this.glyph(label.icon, PALETTE.overlay0)],
        name: [div().truncate().text_color(c.name).child(label.text)],
        right: [statusGlyph(r.status)],
        onClick: () => run("tab.select", { id: r.tabId }),
      });
    }
    if (r.kind === "agent") {
      const name = [div().flex_none().text_color(c.name).child(r.label)];
      let second = null;
      // 札と 2 行目は状態の表示でだけ出す
      if (this.view === "status") {
        if (r.spaceName) name.push(div().truncate().text_color(c.extra).child(r.spaceName));
        const actions = activityFor(r.address, this.activity, ctx.liveAgents, this.sessions)?.actions;
        const list = Array.isArray(actions) ? actions.filter((a) => a && typeof a === "object") : [];
        const tag = domainTag(list);
        if (tag) name.push(this.tag(tag));
        second = describe(list[0] ?? null);
      }
      return this.row(r, {
        ...base,
        second,
        slot: this.agentSlot(r, base.highlight),
        name,
        right: this.rightSide(r, now, c),
        onSlotClick: r.hasChildren ? () => this.setOpen(r.key, !r.open, ctx.containers) : null,
        onClick: () => run("agent.focus", { terminal: r.address }),
      });
    }
    if (r.kind === "sub") {
      return this.row(r, {
        ...base,
        slot: [],
        name: [div().truncate().text_color(c.extra).child(r.label)],
        right: [statusGlyph(r.status)],
        onClick: () => run("agent.focus", { terminal: r.address }),
      });
    }
    // まとまりの見出し: 一番左の列に印、名前、右端に数 (畳んだときは数の前に矢印)
    return this.row(r, {
      ...base,
      baseline: true,
      slot: [statusGlyph(r.status)],
      name: [div().truncate().font_weight(700).text_color(PALETTE.text).child(r.label)],
      right: [
        ...(r.open ? [] : [this.glyph(GLYPH.chevronRight, PALETTE.overlay2)]),
        div().flex_none().w(METRICS.glyphSize).flex().justify_end().text_color(PALETTE.subtext0).child(String(r.count)),
      ],
      onClick: () => this.setOpen(r.key, !r.open, ctx.containers),
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
    const termPanes = allPanes.filter((p) => p.terminal);
    for (const p of allPanes) if (p.focused && p.terminal) this.activePane.set(p.tab, p.pane);
    const nested = nestSpaces(spaceList, this.repos);
    const focus = focused();
    const containers = focusContainers({ view: this.view, agents: liveAgents, focus });
    this.held = pruneHeld(this.held, containers);
    const collapsed = effectiveCollapsed(this.collapsed, containers, this.held);
    const input = { agents: liveAgents, subagents, sessions: this.sessions, collapsed };
    const rows =
      this.view === "status"
        ? buildGroups({ ...input, times: this.times })
        : buildStructure({ ...input, nested, panes: termPanes, activePanes: this.activePane });
    setAgentOrder(agentOrder(rows));
    this.schedule(liveAgents, now, cx);
    const highlight = highlightKey(rows, focus, containers);
    const highlightIndex = highlight == null ? -1 : rows.findIndex((r) => r.key === highlight);
    if (highlightIndex >= 0 && highlightIndex !== this.lastHighlightIndex) {
      this.scroll.scroll_to_item(highlightIndex);
    }
    this.lastHighlightIndex = highlightIndex;
    const ctx = {
      now,
      cx,
      liveAgents,
      focus,
      containers,
      highlight,
      panes: allPanes,
      spaceById: new Map(spaceList.map((s) => [s.id, s])),
    };
    return v_flex()
      .id("workspace")
      .size_full()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .child(
        v_flex()
          .id("workspace-list")
          .flex_1()
          .min_h(0)
          .overflow_y_scrollbar()
          .track_scroll(this.scroll)
          .children(rows.map((r) => this.renderRow(r, ctx))),
      );
  }
}
