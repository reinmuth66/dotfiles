// プレビュー。今のタブのエージェント (Claude Code) の編集に追従して差分を出し、ツリーで選ぶと
// そのファイルに固定して全体を出す。状態 (追従か固定か、差分か全体か、履歴の位置) はタブごとに持つ。
// 全体は、Markdown は整形、コードは色付き、画像はアプリのフォルダへの写し、文書は qlmanage の縮小画像、
// 3MF、FreeCAD、KiCad は中の縮小画像か kicad-cli の SVG、それ以外は種類と大きさだけ。判断は logic.js、差分の読み取りは diff.js にある
import * as fs from "fs/promises";
import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, Scrollbar, TextView, v_virtual_list } from "gpui-base";
import { agents, appHome, checking, exec, focused, nextCommand, readTextFile, settings, shared, spaces, theme } from "herdr";
import { METRICS, PALETTE, REMOTE_LABEL, cells, isRemoteAddress, isRemoteSpace } from "./ui.js";
import { RETRY_MS, repoRoot, watchJsonDir } from "./data.js";
import { diffArgs, parseUnifiedDiff } from "./diff.js";
import {
  MAX_TEXT_BYTES,
  agentTerminalFor,
  editTexts,
  editsFor,
  extOf,
  fileKind,
  follow,
  formatSize,
  headerText,
  imagePlan,
  initialTabState,
  languageOf,
  moveHistory,
  pathspecFor,
  pin,
  previewCachePath,
  pruneTargets,
  stripCR,
  thumbnailCommand,
  thumbnailOutput,
  toggleView,
  tooLargeMessage,
  withEdits,
} from "./logic.js";

const FONT = "Moralerspace Neon HW";
const FILE_ICON = "\u{f0214}";
const CACHE_MAX = 200;
const STAT_TIMEOUT = 5000;
const COPY_TIMEOUT = 5000;
const THUMB_TIMEOUT = 15000;
const GIT_TIMEOUT = 10000;
const DIFF_ROW = 20;
const TERMINAL_ID = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;

const baseName = (path) => String(path).split("/").pop() || path;
const dirName = (path) => String(path).replace(/\/[^/]*$/, "") || "/";

function currentSpace() {
  const list = spaces();
  const id = focused()?.space;
  return list.find((s) => s.id === id) ?? list.find((s) => s.active) ?? null;
}

// 大きさと mtime (ミリ秒)。読めなければ null
async function statFile(path) {
  const r = await exec("stat", ["-f", "%z %m", path], { timeout: STAT_TIMEOUT }).catch(() => null);
  if (r?.code !== 0) return null;
  const [size, mtime] = r.stdout.trim().split(" ").map(Number);
  return Number.isFinite(size) ? { size, mtimeMs: mtime * 1000 } : null;
}

// data/preview/ が上限を超えたら、古いものから消す
async function pruneCache(dir) {
  let names;
  try {
    names = await fs.readdir(dir);
  } catch {
    return;
  }
  if (names.length <= CACHE_MAX) return;
  const paths = names.map((n) => `${dir}/${n}`);
  const r = await exec("stat", ["-f", "%m", ...paths], { timeout: STAT_TIMEOUT }).catch(() => null);
  if (r?.code !== 0) return;
  const mtimes = r.stdout.trim().split("\n").map(Number);
  const entries = names.map((name, i) => ({ name, mtime: mtimes[i] ?? 0 }));
  for (const name of pruneTargets(entries, CACHE_MAX)) await fs.unlink(`${dir}/${name}`).catch(() => {});
}

// 読み込みごとに data/preview-tmp/ の下へ自分だけの一時フォルダを作り、fn に渡す。成否によらず消す
async function withTmpDir(fn) {
  const base = `${appHome()}/data/preview-tmp`;
  await fs.mkdir(base, { recursive: true });
  const mk = await exec("mktemp", ["-d", `${base}/load.XXXXXX`], { timeout: COPY_TIMEOUT }).catch(() => null);
  const tmpDir = mk?.code === 0 ? mk.stdout.trim() : null;
  if (!tmpDir) return null;
  try {
    return await fn(tmpDir);
  } finally {
    await exec("rm", ["-rf", tmpDir], { timeout: COPY_TIMEOUT }).catch(() => {});
  }
}

const heads = new Map(); // 根 → { promise, failedAt }

// HEAD があるか (コミットのないリポジトリでは HEAD との差が取れない)。あるものは根ごとにずっと覚え、
// ないもの (または時間切れ) は RETRY_MS だけ覚える (最初のコミットを拾う)
function hasHead(root) {
  const hit = heads.get(root);
  if (hit && (hit.failedAt === null || Date.now() - hit.failedAt < RETRY_MS)) return hit.promise;
  const entry = { promise: null, failedAt: null };
  entry.promise = exec("git", ["rev-parse", "--verify", "-q", "HEAD"], { cwd: root, timeout: GIT_TIMEOUT })
    .then((r) => r.code === 0)
    .catch(() => false)
    .then((ok) => {
      if (!ok) entry.failedAt = Date.now();
      return ok;
    });
  heads.set(root, entry);
  return entry.promise;
}

export default class Preview extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.tabs = {}; // タブ → initialTabState() から作る状態
    this.seenTop = {}; // タブ → 最後に見た、いちばん新しい編集の seq
    this.pinAt = {}; // タブ → 固定した tree-selection の at (同じファイルを選び直したら読み直す)
    // 起動の前に選ばれていたものでは固定しない (既定は追従)
    this.seenAt = shared("tree-selection")?.at ?? null;
    this.edits = []; // 今のタブのエージェントの編集の seq (新しい順)
    this.agent = null; // その端末
    this.key = null; // 出しているものの鍵。同じなら作り直さない
    this.loadKey = null; // 全体表示のパスと mtime。同じなら作り直さない
    this.view = null; // { kind, meta, ... }
    this.code = null; // EditorState
    this.token = 0;
    this.activity = {};
    this.sessions = {};
    this.activityWatch = watchJsonDir(cx, "activity", (files) => {
      this.activity = files;
      cx.notify();
    });
    this.sessionsWatch = watchJsonDir(cx, "sessions", (files) => {
      this.sessions = files;
      cx.notify();
    });
    if (checking()) return;
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "focus") this.handle.focus();
        else this.command(c);
        cx.notify();
      }
    });
  }

  close() {
    this.activityWatch?.cancel();
    this.sessionsWatch?.cancel();
    this.code?.release();
    this.code = null;
  }

  stateOf(tab) {
    if (!this.tabs[tab]) this.tabs[tab] = initialTabState();
    return this.tabs[tab];
  }

  command(c) {
    const tab = focused()?.tab;
    if (!tab || isRemoteAddress(tab)) return;
    const s = this.stateOf(tab);
    if (c === "toggle-view") this.tabs[tab] = toggleView(s);
    else if (c === "follow") this.tabs[tab] = follow(s);
    else if (s.mode !== "follow") return;
    // 編集は新しい順なので、1 つ前 (古いほう) は位置を 1 つ進める
    else if (c === "history-prev") this.tabs[tab] = moveHistory(s, 1, this.edits.length);
    else if (c === "history-next") this.tabs[tab] = moveHistory(s, -1, this.edits.length);
  }

  // tree-selection と activity を受け取り、今のタブで出すものを決める
  sync(tab, cx) {
    const sel = shared("tree-selection");
    if (sel?.path && sel.at !== this.seenAt) {
      this.seenAt = sel.at;
      if (sel.tab === tab) {
        this.tabs[tab] = pin(this.stateOf(tab), sel.path);
        this.pinAt[tab] = sel.at;
      }
    }
    const f = focused();
    this.agent = agentTerminalFor(agents(), f);
    this.edits = editsFor(this.agent, this.activity, this.sessions);
    const s = withEdits(this.stateOf(tab), this.seenTop[tab] ?? null, this.edits);
    this.tabs[tab] = s;
    this.seenTop[tab] = this.edits[0] ?? null;

    if (s.mode === "follow") {
      const seq = this.edits[s.historyIndex] ?? null;
      const meta = { mode: "follow", view: s.view, path: null, index: s.historyIndex, count: this.edits.length };
      const key = `follow\0${this.agent}\0${seq}\0${s.view}\0${s.historyIndex}\0${this.edits.length}`;
      if (key === this.key) return;
      this.key = key;
      if (seq == null) {
        this.show({ kind: "note", text: this.agent ? "編集はまだありません" : "エージェントがいません", meta });
        return;
      }
      this.load(() => this.buildEdit(this.agent, seq, s.view, meta), cx);
      return;
    }
    const meta = { mode: "pinned", view: s.view, path: s.pinned, index: 0, count: 0 };
    const key = `pinned\0${s.pinned}\0${s.view}\0${this.pinAt[tab] ?? ""}`;
    if (key === this.key) return;
    this.key = key;
    this.load(() => (s.view === "diff" ? this.buildHeadDiff(s.pinned, meta) : this.buildFull(s.pinned, meta)), cx);
  }

  setCode(state) {
    if (this.code !== state) this.code?.release();
    this.code = state;
  }

  show(view) {
    this.token++;
    this.setCode(view.kind === "code" ? view.state : null);
    this.view = view;
  }

  load(build, cx) {
    const token = ++this.token;
    cx.spawn(async (cx) => {
      const view = await build();
      if (token !== this.token) {
        if (view.state && view.state !== this.code) view.state.release();
        return;
      }
      this.setCode(view.kind === "code" ? view.state : null);
      this.view = view;
      cx.notify();
    });
  }

  // 文字列を全体表示にする。Markdown は整形、それ以外は色付きのコード。NUL を含めば種類と大きさだけ
  textView(path, text, meta, size) {
    if (text.includes("\0")) return { kind: "info", ext: extOf(path), size, note: null, meta };
    if (fileKind(path) === "markdown") return { kind: "markdown", text, meta };
    const t = theme();
    const state = EditorState.new({
      language: languageOf(path),
      value: text,
      readonly: true,
      font_family: settings().font_family,
      syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, number: t.ansi3, function: t.ansi4, type: t.ansi6 },
    });
    return { kind: "code", state, meta };
  }

  // 追従: data/edits/<端末>/<seq>.json の記録。差分は前後から作る (git のリポジトリでなくても出る)
  async buildEdit(agent, seq, view, meta) {
    const note = (text, path = null) => ({ kind: "note", text, meta: { ...meta, path } });
    if (!TERMINAL_ID.test(agent)) return note("読めません");
    let rec = null;
    try {
      const text = await readTextFile(`${appHome()}/data/edits/${agent}/${seq}.json`);
      rec = text == null ? null : JSON.parse(text);
    } catch {
      rec = null; // 書き直しの合間に古い記録が消えた、または大きすぎて読めない
    }
    if (!rec || typeof rec.path !== "string") return note("この編集の記録はもうありません");
    const path = rec.path;
    const texts = editTexts(rec);
    if (!texts) return note(tooLargeMessage, path);
    const m = { ...meta, path };
    if (view === "full") return this.textView(path, texts.after, m, texts.after.length);
    const rows = await this.editDiff(texts);
    if (!rows) return note("差分を出せません", path);
    if (rows.length === 0) return note("差はありません", path);
    return { kind: "diff", rows, meta: m };
  }

  async editDiff({ before, after }) {
    const rows = await withTmpDir(async (dir) => {
      const a = `${dir}/tmp-a`;
      const b = `${dir}/tmp-b`;
      await fs.writeFile(a, before);
      await fs.writeFile(b, after);
      const { cmd, args } = diffArgs({ mode: "edit", a, b });
      const r = await exec(cmd, args, { cwd: dir, timeout: GIT_TIMEOUT }).catch(() => null);
      // --no-index は差があると 1 で終わる
      if (r?.code !== 0 && r?.code !== 1) return null;
      return parseUnifiedDiff(r.stdout);
    }).catch(() => null);
    return rows ?? null;
  }

  // 固定の差分: git の HEAD との差。git のない場所では全体のまま
  async buildHeadDiff(path, meta) {
    const root = await repoRoot(dirName(path));
    if (!root) return this.buildFull(path, { ...meta, view: "full" });
    const note = (text) => ({ kind: "note", text, meta });
    const spec = pathspecFor(path, root);
    const { cmd, args, cwd } = diffArgs({ mode: "head", root, path: spec, hasHead: await hasHead(root) });
    const r = await exec(cmd, args, { cwd, timeout: GIT_TIMEOUT }).catch(() => null);
    if (r?.code !== 0) return note("差分を出せません");
    const rows = parseUnifiedDiff(r.stdout);
    if (rows.length > 0) return { kind: "diff", rows, meta };
    const ls = await exec("git", ["--no-optional-locks", "ls-files", "--", spec], { cwd: root, timeout: GIT_TIMEOUT }).catch(() => null);
    if (ls?.code === 0 && ls.stdout.trim() === "") return note("git で管理されていません");
    return note("HEAD との差はありません");
  }

  // 固定の全体
  async buildFull(path, meta) {
    const kind = fileKind(path);
    const ext = extOf(path);
    const info = (stat, note) => ({ kind: "info", ext, size: stat?.size ?? null, note, meta });
    const stat = await statFile(path);
    if (!stat) return info(null, "読めません");
    const key = `${path}\0${stat.mtimeMs}`;
    if (key === this.loadKey && this.view?.fullKey === key) return { ...this.view, meta };
    this.loadKey = key;
    const keyed = (view) => ({ ...view, fullKey: key });
    try {
      if (kind === "markdown" || kind === "code") {
        if (stat.size > MAX_TEXT_BYTES) return info(stat, "大きすぎて表示できません");
        const text = await readTextFile(path);
        if (text == null) return info(stat, "読めません");
        return keyed(this.textView(path, text, meta, stat.size));
      }
      const plan = imagePlan(path);
      if (plan) {
        const home = appHome();
        const dir = `${home}/data/preview`;
        const dest = previewCachePath(home, path, stat.mtimeMs, plan.ext);
        if (!(await fs.exists(dest))) {
          await fs.mkdir(dir, { recursive: true });
          if (!(await this.makeImage(plan.method, path, dest))) return info(stat, null);
          await pruneCache(dir);
        }
        return keyed({ kind: "image", rel: dest.slice(home.length + 1), meta });
      }
    } catch {
      return info(stat, "読めません");
    }
    return info(stat, null);
  }

  // 一時フォルダで写し (cp)、PNG への変換 (sips)、縮小画像 (qlmanage、モデル) を作ってから、mv で写しの場所へ置く。
  // 途中で失敗しても写しの場所には書きかけが残らない
  async makeImage(method, path, dest) {
    const ok = await withTmpDir(async (tmpDir) => {
      let made = null;
      if (method === "copy") {
        made = `${tmpDir}/copy`;
        const r = await exec("cp", [path, made], { timeout: COPY_TIMEOUT }).catch(() => null);
        if (r?.code !== 0) return false;
      } else if (method === "convert") {
        made = `${tmpDir}/convert.png`;
        const r = await exec("sips", ["-s", "format", "png", path, "--out", made], { timeout: THUMB_TIMEOUT }).catch(() => null);
        if (r?.code !== 0) return false;
      } else if (method === "model") {
        // 3MF と FreeCAD は zip の中の縮小画像、KiCad は kicad-cli の SVG。KiCad がなければ exec が失敗する
        const out = `${tmpDir}/model.${extOf(dest)}`;
        const c = thumbnailCommand(path, out);
        if (!c) return false;
        const r = await exec(c.cmd, c.args, { timeout: c.timeout }).catch(() => null);
        if (r?.code !== 0) return false;
        made = thumbnailOutput(path, out);
      } else {
        // qlmanage は <名前>.png を書く
        const r = await exec("qlmanage", ["-t", "-s", "800", "-o", tmpDir, path], { timeout: THUMB_TIMEOUT }).catch(() => null);
        if (r?.code !== 0) return false;
        made = `${tmpDir}/${baseName(path)}.png`;
      }
      if (!(await fs.exists(made))) return false;
      const mv = await exec("mv", ["-f", made, dest], { timeout: COPY_TIMEOUT }).catch(() => null);
      return mv?.code === 0;
    });
    return ok === true;
  }

  renderHeader() {
    const meta = this.view?.meta;
    if (!meta) return null;
    const h = headerText(meta);
    const dim = theme().dim;
    return h_flex()
      .flex_none()
      .h(METRICS.row)
      .pl(METRICS.padLeft)
      .pr(METRICS.padLeft)
      .gap(8)
      .items_center()
      .child(div().flex_none().text_color(meta.mode === "follow" ? PALETTE.blue : PALETTE.peach).child(h.mode))
      .child(div().flex_1().min_w(0).truncate().text_color(PALETTE.text).child(h.name))
      .child(div().flex_none().text_color(dim).child(h.view))
      .children(h.position ? [div().flex_none().text_color(dim).child(h.position)] : []);
  }

  renderDiff(rows) {
    const dim = theme().dim;
    let maxLine = 1;
    let maxText = 0;
    for (const r of rows) {
      maxLine = Math.max(maxLine, r.old ?? 0, r.new ?? 0);
      maxText = Math.max(maxText, r.text.length);
    }
    const numW = cells(String(maxLine).length + 1);
    const width = numW * 2 + cells(maxText + 6);
    const row = (r) => {
      if (r.kind === "hunk") {
        return div().w_full().h(DIFF_ROW).flex_none().px(METRICS.padLeft).truncate().text_color(dim).child(r.text);
      }
      const num = (n) => div().w(numW).flex_none().text_right().text_color(dim).child(n == null ? "" : String(n));
      return h_flex()
        .w_full()
        .h(DIFF_ROW)
        .flex_none()
        .items_center()
        .when(r.kind === "add", (e) => e.bg(`${PALETTE.green}26`))
        .when(r.kind === "del", (e) => e.bg(`${PALETTE.red}26`))
        .child(num(r.old))
        .child(num(r.new))
        .child(div().flex_1().min_w(0).pl(cells(2)).whitespace_nowrap().child(stripCR(r.text).replaceAll("\t", "    ")));
    };
    return div()
      .flex_1()
      .min_h(0)
      .relative()
      .child(
        div()
          .id("preview-diff-x")
          .size_full()
          .overflow_x_scrollbar()
          .child(
            div()
              .w_full()
              .min_w(width)
              .h_full()
              .child(
                v_virtual_list("preview-diff", rows.length, DIFF_ROW, (i) => String(i), (range) =>
                  rows.slice(range.start, range.end).map(row),
                ).size_full(),
              ),
          ),
      )
      .child(Scrollbar.vertical("preview-diff").viewport_from_layout().absolute().inset_0());
  }

  renderBody() {
    const v = this.view;
    const t = theme();
    const note = (text) => div().p(METRICS.padLeft).text_color(t.dim).child(text);
    if (!v) return note("読み込み中");
    if (v.kind === "note") return note(v.text);
    if (v.kind === "diff") return this.renderDiff(v.rows);
    if (v.kind === "markdown") {
      return div()
        .id("preview-body")
        .flex_1()
        .min_h(0)
        .px(METRICS.padLeft)
        .child(TextView.markdown("preview-md", v.text).selectable(true).scrollable(true).size_full());
    }
    if (v.kind === "code" && this.code) return Editor.new(this.code).flex_1().min_h(0);
    if (v.kind === "image") {
      return div().flex_1().min_h(0).p(METRICS.padLeft).child(image(v.rel).size_full());
    }
    return v_flex()
      .flex_1()
      .min_h(0)
      .items_center()
      .justify_center()
      .gap(6)
      .px(METRICS.padLeft)
      .text_center()
      .text_color(t.dim)
      .child(div().text_size(48).child(FILE_ICON))
      .child(div().child(`${v.ext ? v.ext.toUpperCase() : "ファイル"} · ${formatSize(v.size)}`))
      .children(v.note ? [div().child(v.note)] : []);
  }

  render(cx) {
    const base = v_flex()
      .id("preview")
      .size_full()
      .font_family(FONT)
      .text_size(METRICS.fontSize)
      .text_color(PALETTE.text)
      .track_focus(this.handle);
    const tab = focused()?.tab ?? null;
    if (isRemoteSpace(currentSpace()) || (tab && isRemoteAddress(tab))) {
      return base.child(h_flex().flex_none().h(METRICS.row).pl(METRICS.padLeft).items_center().text_color(theme().dim).child(REMOTE_LABEL));
    }
    if (!tab) return base;
    this.sync(tab, cx);
    const header = this.renderHeader();
    return base.children(header ? [header] : []).child(this.renderBody());
  }
}
