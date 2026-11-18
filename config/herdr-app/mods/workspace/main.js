// 帯の一覧。space → タブ → エージェント → サブエージェント の構造の表示と、作業状態で並べる表示を持つ。
// 行の組み立ては logic.js、記号と色と寸法は ui.js にある
import { View, div, PathBuilder } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import { agents, checking, exec, home, nextCommand, panes, run, setAgentOrder, setShared, shared, spaces } from "herdr";
import {
  GLYPH,
  METRICS,
  PALETTE,
  ROSTER,
  STATUS,
  cells,
  contextColor,
  contextPercent,
  isRemoteAddress,
  isRemoteSpace,
  mark,
  paneLabel,
  ringArc,
} from "./ui.js";
import { repoRoot, watchJsonDir } from "./data.js";
import {
  agentOrder,
  agentTime,
  assignNames,
  buildGroups,
  buildStructure,
  contextFor,
  nestSpaces,
  nextTick,
  trackAgentTimes,
} from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;

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

// コンテキストの使用率の輪。外径 METRICS.ring、12 時から時計回りに fraction の長さ
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
    this.roots = new Map(); // cwd → git のルート (null: git の外)。undefined のあいだは読んでいる
    this.cursor = 0;
    this.rows = [];
    this.tick = null;
    this.handle = cx.focus_handle();
    this.scroll = ScrollHandle.new();
    this.watch = watchJsonDir(cx, "sessions", (files) => {
      this.sessions = files;
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

  // space ごとの git の場所 (worktree の入れ子に使う)。folder が変わったときだけ読み直す
  refreshRepos(list, cx) {
    const local = list.filter((s) => !isRemoteSpace(s));
    const key = JSON.stringify(local.map((s) => [s.id, s.folder]));
    if (key === this.reposKey) return;
    this.reposKey = key;
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
      this.repos = repos;
      cx.notify();
    });
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

  // エージェントのいないタブの名前と記号。名前は枠の見出しと同じ決まり、rename した名前が先
  tabLabel(row, spaceById, allPanes, cx) {
    const pane = allPanes.find((p) => p.tab === row.tabId && p.terminal);
    const program = pane?.program;
    const processName = program ? (program.key === "program" ? program.name : program.key) : "";
    const icon = processName === "yazi" ? GLYPH.yazi : GLYPH.shell;
    if (row.label) return { icon, text: row.label };
    if (!pane) return { icon, text: "" };
    const remote = isRemoteSpace(spaceById.get(row.spaceId)) || isRemoteAddress(pane.pane);
    const label = paneLabel({
      programKey: program?.key,
      processName,
      shell: Boolean(program?.shell),
      cwd: pane.cwd,
      repoRoot: remote ? null : this.rootOf(pane.cwd, cx),
      home: home(),
    });
    return { icon, text: label.text };
  }

  updateNames(liveAgents) {
    const prev = shared("agent-names") ?? {};
    // 起動の直後は agents() が空のことがある。そのときに名前を全部捨てない
    if (liveAgents.length === 0) return prev;
    const names = assignNames(
      prev,
      liveAgents.map((a) => a.address),
      ROSTER.map((r) => r.name),
    );
    if (!sameJson(names, prev)) setShared("agent-names", names);
    return names;
  }

  updateTimes(liveAgents, spaceList, now) {
    if (liveAgents.length === 0 && Object.keys(this.times).length > 0) return; // 起動の直後
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

  // 時間の文字が変わるときに 1 回だけ描き直す。予約があれば作り直さない
  schedule(now, cx) {
    if (this.tick || checking()) return;
    const wait = nextTick(this.times, now);
    if (wait == null) return;
    this.tick = cx.timer.after(wait, (cx) => {
      this.tick = null;
      cx.notify();
    });
  }

  activate(row) {
    if (!row) return;
    if (row.kind === "space" || row.kind === "group") this.toggle(row.key);
    else if (row.kind === "tab") run("tab.select", { id: row.tabId });
    else if (row.kind === "agent" || row.kind === "sub") run("agent.focus", { terminal: row.address });
  }

  key(e, cx) {
    const m = e.modifiers ?? {};
    if (m.control || m.alt || m.platform) return;
    const last = this.rows.length - 1;
    if (e.key === "j") this.cursor = Math.min(last, this.cursor + 1);
    else if (e.key === "k") this.cursor = Math.max(0, this.cursor - 1);
    else if (e.key === "enter") this.activate(this.rows[this.cursor]);
    else if (e.key === "escape") run("pane.go", { direction: "right" });
    else return;
    this.scroll.scroll_to_item(this.cursor);
    cx.stop_propagation();
    cx.notify();
  }

  // [段 × 字下げ][記号の枠][間][名前 …][右端]
  row(r, i, { slot, name, right = [], onClick, focused }) {
    return h_flex()
      .id(`row-${r.key}`)
      .flex_none()
      .w_full()
      .h(METRICS.row)
      .pl(METRICS.padLeft + r.depth * cells(METRICS.indentCells))
      .pr(PAD_RIGHT)
      .items_center()
      .when(focused && i === this.cursor, (el) => el.bg(PALETTE.surface0))
      .on_click((_e, cx) => {
        this.cursor = i;
        onClick?.(cx);
        cx.notify();
      })
      .child(
        div()
          .relative()
          .flex_none()
          .w(cells(METRICS.slotCells))
          .h_full()
          .flex()
          .items_center()
          .justify_center()
          .children(slot),
      )
      .child(div().flex_none().w(cells(METRICS.gapCells)))
      .child(h_flex().flex_1().min_w(0).gap(cells(1)).items_center().children(name))
      .children(right);
  }

  glyph(text, color) {
    return div().flex_none().text_size(METRICS.glyphSize).text_color(color).child(text);
  }

  rightSide(r, now) {
    const time = r.kind === "agent" ? agentTime(this.times[r.address], now) : null;
    return [
      ...(time ? [div().flex_none().pr(cells(1)).text_color(PALETTE.subtext0).child(time)] : []),
      statusGlyph(r.status),
    ];
  }

  // 輪とマークを記号の枠の中心に合わせて重ねる。輪は枠からはみ出してよい
  agentSlot(r) {
    const m = mark(r.label);
    const slot = [div().font_weight(700).text_color(m.color).child(m.letter)];
    const session = contextFor(r.address, this.sessions);
    const pct = contextPercent(session?.context);
    if (pct != null) {
      const offset = (cells(METRICS.slotCells) - METRICS.ring) / 2;
      slot.push(
        div()
          .absolute()
          .left(offset)
          .top((METRICS.row - METRICS.ring) / 2)
          .child(ringElement(Math.min(1, pct / 100), contextColor(pct))),
      );
    }
    if (r.hasChildren) {
      slot.push(
        div()
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
            this.toggle(r.key);
            cx.notify();
          })
          .child(r.open ? GLYPH.chevronDown : GLYPH.chevronRight),
      );
    }
    return slot;
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
      const label = this.tabLabel(r, ctx.spaceById, ctx.panes, ctx.cx);
      return this.row(r, i, {
        ...base,
        slot: [this.glyph(label.icon, PALETTE.overlay0)],
        name: [div().truncate().text_color(PALETTE.subtext0).child(label.text)],
        right: [statusGlyph(r.status)],
        onClick: () => run("tab.select", { id: r.tabId }),
      });
    }
    if (r.kind === "agent") {
      const name = [div().flex_none().text_color(mark(r.label).color).child(r.label)];
      if (this.view === "status" && r.spaceName) name.push(div().truncate().text_color(PALETTE.overlay2).child(r.spaceName));
      return this.row(r, i, {
        ...base,
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
    const spaceList = spaces();
    this.refreshRepos(spaceList, cx);
    const names = this.updateNames(liveAgents);
    this.updateTimes(liveAgents, spaceList, now);
    const input = { agents: liveAgents, subagents: {}, names, collapsed: this.collapsed };
    const rows =
      this.view === "status"
        ? buildGroups(input)
        : buildStructure({ ...input, nested: nestSpaces(spaceList, this.repos) });
    this.rows = rows;
    this.cursor = Math.min(this.cursor, Math.max(0, rows.length - 1));
    setAgentOrder(agentOrder(rows));
    this.schedule(now, cx);
    const ctx = {
      now,
      cx,
      focused: this.handle.is_focused(),
      panes: panes(),
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
