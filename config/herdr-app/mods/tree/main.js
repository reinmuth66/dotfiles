// 帯のツリー。今の space のリポジトリ (なければフォルダ) を根に、開いたフォルダを字下げで並べ、
// git の状態の印と、一番下に今見ているタブのブランチを出す。判断は logic.js、記号と色と寸法は ui.js にある
import * as fs from "fs/promises";
import { View, div } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import { appHome, checking, exec, focused, home, nextCommand, panes, readTextFile, run, setShared, spaces, theme, watchFolder } from "herdr";
import { GLYPH, METRICS, PALETTE, REMOTE_LABEL, cells, isRemoteSpace } from "./ui.js";
import { repoRoot } from "./data.js";
import { GIT_STYLE, counts, fileIcon, flatten, folderState, openerFor, parseStatus, treeRoot } from "./logic.js";

const FONT = "Moralerspace Neon HW";
const PAD_RIGHT = 10;
const PER_FOLDER = 500; // 同梱の files と同じ
const GIT_TIMEOUT = 5000;
const HOME_POLL = 10000;

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

const baseName = (path) => path.replace(/\/+$/, "").split("/").pop() || path;

// 今の space (focused() の space、なければ表示中の space)
function currentSpace() {
  const list = spaces();
  const id = focused()?.space;
  return list.find((s) => s.id === id) ?? list.find((s) => s.active) ?? null;
}

// 今見ているタブの枠のブランチ。focused() の枠、なければそのタブで focus を持つ枠
function currentBranch() {
  const f = focused();
  if (!f) return null;
  const all = panes();
  const pane = (f.pane && all.find((p) => p.pane === f.pane)) || all.find((p) => p.tab === f.tab && p.focused);
  return pane?.branch ?? null;
}

async function readFolder(path) {
  const entries = await fs.readdir(path, { withFileTypes: true });
  const out = [];
  for (const e of entries) {
    if (e.name === ".git") continue;
    // herdr の Dirent は name と isDirectory() だけを持つ (stat も isSymbolicLink もない)
    out.push({ name: e.name, dir: e.isDirectory() });
    if (out.length >= PER_FOLDER) break;
  }
  return out;
}

async function readGit(root) {
  const opts = { cwd: root, timeout: GIT_TIMEOUT };
  // .git の下に何も書かない (索引の鍵、fsmonitor)。書くと見張りがまた読み直す
  const status = await exec(
    "git",
    ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all"],
    opts,
  );
  if (status.code !== 0) return null;
  const ignored = new Set();
  const listed = await exec("git", ["ls-files", "-o", "-i", "--exclude-standard", "--directory", "-z"], opts).catch(() => null);
  if (listed?.code === 0) {
    for (const p of listed.stdout.split("\0")) if (p) ignored.add(p.replace(/\/+$/, ""));
  }
  return { states: parseStatus(status.stdout), ignored };
}

export default class Tree extends View {
  init(_props, cx) {
    this.showHidden = load("showHidden", false) === true;
    this.spaceKey = null; // 根を決めた space (id とフォルダ)
    this.root = null; // 絶対パス。null: 根がない (別のコンピューター、space がない、まだ決めていない)
    this.remote = false;
    this.isRepo = false;
    this.rootOpen = true;
    this.open = new Set();
    this.children = {}; // フォルダ (根からの相対、根は "") → [{ name, dir }]
    this.states = {};
    this.ignored = new Set();
    this.saved = new Map(); // 根 → { open, rootOpen }。space を行き来しても開いたフォルダを覚える
    this.context = null; // 根ごとの読み込みと見張り
    this.icons = null;
    this.rows = [];
    this.cursor = 0;
    this.handle = cx.focus_handle();
    this.scroll = ScrollHandle.new();
    cx.spawn(async (cx) => {
      try {
        const text = await readTextFile(`${appHome()}/data/yazi-icons.json`);
        if (text != null) this.icons = JSON.parse(text);
      } catch {
        // 表がなければ既定のアイコン
      }
      cx.notify();
    });
    if (checking()) return;
    this.poll = cx.timer.every(HOME_POLL, (cx) => {
      if (this.root && this.root === home()) this.reload(cx);
    });
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "focus") this.handle.focus();
        cx.notify();
      }
    });
  }

  close() {
    this.stopContext();
    this.poll?.cancel();
  }

  stopContext() {
    if (!this.context) return;
    this.context.stopped = true;
    this.context.watch?.cancel();
    this.context = null;
  }

  // space が変わったら根を決め直す。git のルートは非同期なので、決まるまでは前の根のまま
  updateRoot(cx) {
    const space = currentSpace();
    const key = space ? JSON.stringify([space.id, space.folder, space.machine]) : null;
    if (key === this.spaceKey) return;
    this.spaceKey = key;
    if (!space || isRemoteSpace(space)) {
      this.setRoot(null, false, Boolean(space), cx);
      return;
    }
    if (checking()) return;
    cx.spawn(async (cx) => {
      const top = space.folder ? await repoRoot(space.folder) : null;
      if (this.spaceKey !== key) return;
      this.setRoot(treeRoot({ space, repoRoot: top, home: home() }), Boolean(top), false, cx);
      cx.notify();
    });
  }

  setRoot(root, isRepo, remote, cx) {
    this.remote = remote;
    if (root === this.root && isRepo === this.isRepo) return;
    if (this.root) this.saved.set(this.root, { open: this.open, rootOpen: this.rootOpen });
    this.stopContext();
    this.root = root;
    this.isRepo = isRepo;
    const saved = root ? this.saved.get(root) : null;
    this.open = new Set(saved?.open);
    this.rootOpen = saved?.rootOpen ?? true;
    this.children = {};
    this.states = {};
    this.ignored = new Set();
    this.cursor = 0;
    if (!root) return;
    this.context = { root, stopped: false, watch: null, loading: false, again: false };
    this.reload(cx);
    this.watchRoot(this.context, cx);
  }

  // ホームは見張らない (ホーム全体の見張りは重い。10 秒ごとに読み直す)
  watchRoot(context, cx) {
    if (context.root === home()) return;
    cx.spawn(async (cx) => {
      while (!context.stopped) {
        try {
          context.watch = watchFolder(context.root);
          const changed = await context.watch;
          if (context.stopped) return;
          if (changed.length === 0) await cx.sleep(2000); // 取り上げられた見張りで空回りしない
          else await cx.sleep(150); // 続けて来る変更をまとめる
          this.reload(cx);
        } catch {
          if (!context.stopped) await cx.sleep(HOME_POLL); // 見張れないときは時間で読み直す
          if (!context.stopped) this.reload(cx);
        }
      }
    });
  }

  // 開いているフォルダと git を読み直す。読んでいる間に頼まれたら、終わってからもう一度読む
  reload(cx) {
    const context = this.context;
    if (!context || checking()) return;
    if (context.loading) {
      context.again = true;
      return;
    }
    context.loading = true;
    cx.spawn(async (cx) => {
      try {
        do {
          context.again = false;
          const children = {};
          for (const rel of ["", ...this.open]) {
            if (context.stopped) return;
            try {
              children[rel] = await readFolder(rel ? `${context.root}/${rel}` : context.root);
            } catch {
              if (rel && !context.stopped) this.open.delete(rel); // 消えたフォルダ
            }
          }
          const git = this.isRepo ? await readGit(context.root).catch(() => null) : null;
          if (context.stopped) return;
          this.children = children;
          this.states = git?.states ?? {};
          this.ignored = git?.ignored ?? new Set();
          cx.notify();
        } while (context.again && !context.stopped);
      } finally {
        context.loading = false;
      }
    });
  }

  loadFolder(rel, cx) {
    const context = this.context;
    if (!context || checking()) return;
    cx.spawn(async (cx) => {
      try {
        const entries = await readFolder(`${context.root}/${rel}`);
        if (context.stopped || !this.open.has(rel)) return;
        this.children = { ...this.children, [rel]: entries };
      } catch {
        if (!context.stopped) this.open.delete(rel);
      }
      cx.notify();
    });
  }

  toggleFolder(rel, cx) {
    if (this.open.has(rel)) {
      for (const f of [...this.open]) if (f === rel || f.startsWith(`${rel}/`)) this.open.delete(f);
    } else {
      this.open.add(rel);
      if (!this.children[rel]) this.loadFolder(rel, cx);
    }
  }

  toggleRoot() {
    this.rootOpen = !this.rootOpen;
    this.cursor = 0;
  }

  absPath(row) {
    return row.kind === "root" ? this.root : `${this.root}/${row.rel}`;
  }

  select(row) {
    if (!row || row.kind !== "entry" || row.dir) return;
    setShared("tree-selection", { tab: focused()?.tab ?? null, path: this.absPath(row), at: Date.now() });
  }

  isIgnored(rel) {
    if (this.ignored.size === 0) return false;
    const parts = rel.split("/");
    for (let i = 1; i <= parts.length; i++) if (this.ignored.has(parts.slice(0, i).join("/"))) return true;
    return false;
  }

  key(e, cx) {
    const m = e.modifiers ?? {};
    if (m.control || m.alt || m.platform) return;
    // カーソルの位置: 0..rows.length-1 は行 (0 は根)、rows.length はブランチの欄 (あるときだけ)
    const last = this.rows.length - 1 + (this.branch ? 1 : 0);
    const row = this.rows[this.cursor];
    if (e.key === "j") {
      this.cursor = Math.min(last, this.cursor + 1);
      this.select(this.rows[this.cursor]);
    } else if (e.key === "k") {
      this.cursor = Math.max(0, this.cursor - 1);
      this.select(this.rows[this.cursor]);
    } else if (e.key === "l" || e.key === "space") {
      if (row?.kind === "root") this.toggleRoot();
      else if (row?.dir) this.toggleFolder(row.rel, cx);
    } else if (e.key === "enter") {
      // ブランチの欄での Enter は、ブランチを選ぶ窓 (後の作業) のために空けておく
      if (row && this.root) {
        const [cmd, ...args] = openerFor(this.absPath(row));
        exec(cmd, args, { timeout: GIT_TIMEOUT }).catch(() => {});
      }
    } else if (e.key === ".") {
      this.showHidden = !this.showHidden;
      save("showHidden", this.showHidden);
    } else if (e.key === "escape") run("pane.go", { direction: "right" });
    else return;
    if (this.cursor < this.rows.length) this.scroll.scroll_to_item(this.cursor);
    cx.stop_propagation();
    cx.notify();
  }

  glyph(text, color) {
    return div()
      .flex_none()
      .w(METRICS.glyphSize)
      .flex()
      .justify_center()
      .text_size(METRICS.glyphSize)
      .text_color(color)
      .child(text);
  }

  cursorBg(el, i, focused) {
    return el.when(focused && i === this.cursor, (x) => x.bg(PALETTE.surface0));
  }

  // 根の行: 帯の全体の基準線 (padLeft) と記号の列 (glyphCol)、右に git の数
  renderRoot(row, focused) {
    const marks = this.isRepo
      ? counts(this.states).map(({ state, n }) =>
          h_flex()
            .flex_none()
            .gap(2)
            .items_center()
            .child(this.glyph(GIT_STYLE[state].glyph, GIT_STYLE[state].color))
            .child(div().text_color(PALETTE.subtext0).child(String(n))),
        )
      : [];
    return this.cursorBg(
      h_flex()
        .id("tree-root")
        .flex_none()
        .w_full()
        .h(METRICS.row)
        .pl(METRICS.padLeft)
        .pr(PAD_RIGHT)
        .items_center()
        .on_click((_e, cx) => {
          this.cursor = 0;
          this.toggleRoot();
          cx.notify();
        }),
      0,
      focused,
    )
      .child(
        div()
          .flex_none()
          .w(METRICS.glyphCol)
          .text_size(METRICS.glyphSize)
          .text_color(PALETTE.peach)
          .child(this.rootOpen ? GLYPH.rootOpen : GLYPH.rootClosed),
      )
      .child(div().flex_1().min_w(0).truncate().font_weight(700).text_color(PALETTE.text).child(row.name))
      .child(h_flex().flex_none().gap(cells(1)).items_center().children(marks));
  }

  // [padLeft][depth+1 × 字下げ][記号の枠][間][名前][右端の git の印]
  renderEntry(row, i, focused) {
    const icon = row.dir
      ? { text: row.open ? GLYPH.folderOpen : GLYPH.folder, fg: PALETTE.blue }
      : fileIcon(row.name, this.icons);
    const state = row.dir ? folderState(this.states, row.rel) : this.states[row.rel];
    const style = state ? GIT_STYLE[state] : null;
    const faded = row.name.startsWith(".") || this.isIgnored(row.rel);
    return this.cursorBg(
      h_flex()
        .id(`tree-${row.rel}`)
        .flex_none()
        .w_full()
        .h(METRICS.treeRow)
        .pl(METRICS.padLeft + (row.depth + 1) * cells(METRICS.indentCells))
        .pr(PAD_RIGHT)
        .items_center()
        .on_click((_e, cx) => {
          this.cursor = i;
          if (row.dir) this.toggleFolder(row.rel, cx);
          else this.select(row);
          cx.notify();
        }),
      i,
      focused,
    )
      .child(
        div()
          .flex_none()
          .w(cells(METRICS.slotCells))
          .h_full()
          .flex()
          .items_center()
          .justify_center()
          .text_size(METRICS.glyphSize)
          .text_color(icon.fg)
          .child(icon.text),
      )
      .child(div().flex_none().w(cells(METRICS.gapCells)))
      .child(
        div()
          .flex_1()
          .min_w(0)
          .truncate()
          .text_color(faded ? PALETTE.overlay0 : PALETTE.text)
          .child(row.name),
      )
      .children(style ? [this.glyph(style.glyph, style.color)] : []);
  }

  // 一番下に固定したブランチの欄。右の空きはブランチの状態 (Issue #97) のため
  renderBranch(branch, focused) {
    const i = this.rows.length;
    return this.cursorBg(
      h_flex()
        .id("tree-branch")
        .flex_none()
        .w_full()
        .h(METRICS.row)
        .pl(METRICS.padLeft)
        .pr(PAD_RIGHT)
        .items_center()
        .border_t(1)
        .border_color(theme().border)
        .on_click((_e, cx) => {
          this.cursor = i;
          cx.notify();
        }),
      i,
      focused,
    )
      .child(
        div()
          .flex_none()
          .w(METRICS.glyphCol)
          .text_size(METRICS.glyphSize)
          .text_color(PALETTE.sky)
          .child(GLYPH.branch),
      )
      .child(div().flex_1().min_w(0).truncate().text_color(PALETTE.text).child(branch));
  }

  render(cx) {
    this.updateRoot(cx);
    const isFocused = this.handle.is_focused();
    const base = v_flex()
      .id("tree")
      .size_full()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx));
    if (this.remote) {
      this.rows = [];
      this.branch = null;
      return base.child(
        h_flex()
          .flex_none()
          .h(METRICS.row)
          .pl(METRICS.padLeft)
          .items_center()
          .text_color(theme().dim)
          .child(REMOTE_LABEL),
      );
    }
    if (!this.root) {
      this.rows = [];
      this.branch = null;
      return base;
    }
    const entries = this.rootOpen
      ? flatten({ children: this.children, open: this.open, showHidden: this.showHidden, ignored: this.ignored })
      : [];
    this.rows = [{ kind: "root", name: baseName(this.root) }, ...entries.map((r) => ({ kind: "entry", ...r }))];
    this.branch = currentBranch();
    const max = this.rows.length - 1 + (this.branch ? 1 : 0);
    this.cursor = Math.min(this.cursor, max);
    return base
      .child(
        v_flex()
          .id("tree-list")
          .flex_1()
          .min_h(0)
          .overflow_y_scrollbar()
          .track_scroll(this.scroll)
          .children(this.rows.map((r, i) => (r.kind === "root" ? this.renderRoot(r, isFocused) : this.renderEntry(r, i, isFocused)))),
      )
      .children(this.branch ? [this.renderBranch(this.branch, isFocused)] : []);
  }
}
