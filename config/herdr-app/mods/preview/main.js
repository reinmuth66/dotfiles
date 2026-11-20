// プレビュー。tree で選んだファイルを、herdr の組み込みの部品で出す。状態 (出しているファイル) はタブごとに持つ。
// コードと JSON は Editor (色付け、行番号、折り返し)、Markdown と CSV と TSV は TextView.markdown、
// 画像はアプリのフォルダへの写し、文書は qlmanage の縮小画像、3MF、FreeCAD、KiCad は中の縮小画像か kicad-cli の SVG、
// それ以外は種類と大きさだけ。フォルダは中の README を Markdown で出す。判断は logic.js、表への変換は table.js にある
import * as fs from "fs/promises";
import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, TextView } from "gpui-base";
import { appHome, checking, exec, focused, nextCommand, readTextFile, settings, shared, spaces, theme, watchFolder } from "herdr";
import { METRICS, PALETTE, REMOTE_LABEL, isRemoteAddress, isRemoteSpace } from "./ui.js";
import {
  MAX_TEXT_BYTES,
  PREVIEW_CACHE_DIR,
  extOf,
  fileKind,
  formatJson,
  formatSize,
  cutToLastLine,
  imagePlan,
  initialTabState,
  isCacheFile,
  languageOf,
  previewCachePath,
  pruneTargets,
  readPlan,
  readmeName,
  separatorOf,
  thumbnailCommand,
  thumbnailOutput,
} from "./logic.js";
import { TABLE_MAX_ROWS, parseDelimited, toMarkdownTable } from "./table.js";

const FONT = "Moralerspace Neon HW";
const FILE_ICON = "\u{f0214}";
const CACHE_MAX = 200;
const STAT_TIMEOUT = 5000;
const COPY_TIMEOUT = 5000;
const THUMB_TIMEOUT = 15000;
const FILE_POLL_MS = 10000; // 出しているファイルを見張れないときに読み直す間隔

// Markdown の外枠。GitHub に寄せた値 (見て直してよい)
const MARKDOWN = { font: "Hiragino Sans", size: 14, line: 14 * 1.5, maxWidth: 880, padX: 16, padY: 12 };
const TRUNCATED_NOTE = `先頭の ${TABLE_MAX_ROWS} 行だけを出しています。O で csvlens を開けます`;

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

// data/preview-cache/ の写しが上限を超えたら、古いものから消す (自分が作った名前のものだけ)
async function pruneCache(dir) {
  let names;
  try {
    names = await fs.readdir(dir);
  } catch {
    return;
  }
  names = names.filter(isCacheFile);
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

export default class Preview extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.tabs = {}; // タブ → initialTabState() から作る状態
    this.selAt = {}; // タブ → 最後に受けた tree-selection の at (同じファイルを選び直したら読み直す)
    // 起動の前に選ばれていたものは出さない
    this.seenAt = shared("tree-selection")?.at ?? null;
    this.dirToken = 0; // フォルダの README を探している間に、別のものを選ばれたら捨てる
    this.key = null; // 出しているものの鍵。同じなら作り直さない
    this.loadKey = null; // ファイルのパスと mtime。同じなら作り直さない
    this.view = null; // { kind, path, ... }
    this.code = null; // EditorState
    this.token = 0;
    this.fileWatch = null; // 出しているファイルの見張り。{ path, stopped, pending }
    this.fileRev = 0; // 出しているファイルが変わった回数。鍵に入れて読み直させる
    if (checking()) return;
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        // focus 以外 (作業履歴の切り替えなど) は、ファイルの表示では何もしない
        if (c === "focus") this.handle.focus();
        cx.notify();
      }
    });
  }

  close() {
    this.stopFileWatch();
    this.code?.release();
    this.code = null;
  }

  stateOf(tab) {
    if (!this.tabs[tab]) this.tabs[tab] = initialTabState();
    return this.tabs[tab];
  }

  // 今のタブで出しているファイル。なければ null
  filePath() {
    const tab = focused()?.tab;
    if (!tab || isRemoteAddress(tab)) return null;
    return this.stateOf(tab).file;
  }

  // tree-selection を受け取り、今のタブで出すファイルを決める。そのうえで出すものを読む
  sync(tab, cx) {
    const sel = shared("tree-selection");
    if (sel?.path && sel.at !== this.seenAt) {
      this.seenAt = sel.at;
      if (sel.tab === tab) {
        if (sel.dir) this.selectFolder(tab, sel, cx);
        else this.setFile(tab, sel.path, sel.at);
      }
    }
    const file = this.stateOf(tab).file;
    if (file == null) {
      this.stopFileWatch();
      if (this.key === "none") return;
      this.key = "none";
      this.show({ kind: "note", text: "tree でファイルを選ぶと表示します" });
      return;
    }
    this.watchFile(file, cx);
    const key = `${file}\0${this.selAt[tab] ?? ""}\0${this.fileRev}`;
    if (key === this.key) return;
    this.key = key;
    this.load(() => this.buildFile(file), cx);
  }

  setFile(tab, path, at) {
    this.dirToken++;
    this.stateOf(tab).file = path;
    this.selAt[tab] = at;
  }

  // フォルダは、中に README があればそれを Markdown で出す。なければ今の表示のまま (tree が中身を見せている)
  selectFolder(tab, sel, cx) {
    const token = ++this.dirToken;
    cx.spawn(async (cx) => {
      let names;
      try {
        names = await fs.readdir(sel.path);
      } catch {
        return;
      }
      if (token !== this.dirToken) return;
      const readme = readmeName(names);
      if (!readme) return;
      this.setFile(tab, `${sel.path}/${readme}`, sel.at);
      cx.notify();
    });
  }

  // 出しているファイルのフォルダを見張り、そのファイルが変わったら fileRev を進めて読み直す。
  // 同じファイルのあいだは見張り続け、別のファイル、別のコンピューター、close() で止める
  watchFile(path, cx) {
    if (this.fileWatch?.path === path) return;
    this.stopFileWatch();
    if (checking()) return;
    const w = { path, stopped: false, pending: null };
    this.fileWatch = w;
    const folder = dirName(path);
    const name = baseName(path);
    cx.spawn(async (cx) => {
      while (!w.stopped) {
        let changed;
        try {
          w.pending = watchFolder(folder);
          changed = await w.pending;
        } catch {
          // 見張れない (見張りの数の上限など)。時間で読み直す (mtime が同じなら作り直さない)
          if (!w.stopped) await cx.sleep(FILE_POLL_MS);
          changed = [path];
        }
        if (w.stopped) break;
        if (changed.length === 0) {
          await cx.sleep(FILE_POLL_MS); // フォルダが消えて即座に返るときに、空回りしない
          continue;
        }
        // フォルダそのもの (全部を読み直す合図) か、同じ名前のファイル (/private などの別名も拾う)
        if (changed.some((p) => p === folder || p === path || baseName(p) === name)) {
          this.fileRev++;
          cx.notify();
        }
      }
    });
  }

  stopFileWatch() {
    if (!this.fileWatch) return;
    this.fileWatch.stopped = true;
    this.fileWatch.pending?.cancel();
    this.fileWatch = null;
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

  // 読み取り専用の Editor。syntax は macchiato の 12 の役割
  codeView(path, language, value) {
    const t = theme();
    const state = EditorState.new({
      language,
      value,
      readonly: true,
      soft_wrap: true,
      line_numbers: true,
      folding: false,
      font_family: settings().font_family,
      syntax: {
        keyword: PALETTE.mauve,
        string: PALETTE.green,
        comment: t.dim,
        function: PALETTE.blue,
        type: PALETTE.yellow,
        number: PALETTE.peach,
        constant: PALETTE.peach,
        variable: PALETTE.text,
        operator: PALETTE.sky,
        punctuation: t.dim,
        boolean: PALETTE.peach,
        "string.escape": PALETTE.pink,
      },
    });
    return { kind: "code", state, path };
  }

  // 文字列を表示にする。NUL を含めば種類と大きさだけ
  // cut は、大きなファイルの先頭だけを読んだとき真 (表の下に注記を出す)
  textView(path, text, size, cut = false) {
    if (text.includes("\0")) return { kind: "info", ext: extOf(path), size, note: null, path };
    switch (fileKind(path)) {
      case "markdown":
        return { kind: "markdown", text, path, truncated: false };
      case "csv": {
        const { markdown, truncated } = toMarkdownTable(parseDelimited(text, separatorOf(path)), TABLE_MAX_ROWS);
        return { kind: "markdown", text: markdown, path, truncated: truncated || cut };
      }
      case "json":
        return this.codeView(path, "json", formatJson(text));
      default:
        return this.codeView(path, languageOf(path), text);
    }
  }

  async buildFile(path) {
    const kind = fileKind(path);
    const ext = extOf(path);
    const info = (stat, note) => ({ kind: "info", ext, size: stat?.size ?? null, note, path });
    const stat = await statFile(path);
    if (!stat) return info(null, "読めません");
    const key = `${path}\0${stat.mtimeMs}`;
    if (key === this.loadKey && this.view?.fullKey === key) return this.view;
    this.loadKey = key;
    const keyed = (view) => ({ ...view, fullKey: key });
    try {
      if (kind === "markdown" || kind === "csv" || kind === "json" || kind === "code") {
        const plan = readPlan(kind, stat.size);
        if (plan === "too-large") return info(stat, "大きすぎて表示できません");
        if (plan === "head") {
          // 大きな CSV と TSV は先頭だけ読み、途中で切れた最後の行は落とす
          const r = await exec("head", ["-c", String(MAX_TEXT_BYTES), path], { timeout: COPY_TIMEOUT }).catch(() => null);
          if (r?.code !== 0) return info(stat, "読めません");
          return keyed(this.textView(path, cutToLastLine(r.stdout), stat.size, true));
        }
        const text = await readTextFile(path);
        if (text == null) return info(stat, "読めません");
        return keyed(this.textView(path, text, stat.size));
      }
      const plan = imagePlan(path);
      if (plan) {
        const home = appHome();
        const dir = `${home}/${PREVIEW_CACHE_DIR}`;
        const dest = previewCachePath(home, path, stat.mtimeMs, plan.ext);
        if (!(await fs.exists(dest))) {
          await fs.mkdir(dir, { recursive: true });
          if (!(await this.makeImage(plan.method, path, dest))) return info(stat, null);
          await pruneCache(dir);
        }
        return keyed({ kind: "image", rel: dest.slice(home.length + 1), path });
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

  // 見出しの段。「ファイル」とファイル名だけ
  renderHeader() {
    const file = this.filePath();
    return h_flex()
      .flex_none()
      .h(METRICS.row)
      .pl(METRICS.padLeft)
      .pr(METRICS.padLeft)
      .gap(8)
      .items_center()
      .child(div().flex_none().text_color(PALETTE.blue).child("ファイル"))
      .child(div().flex_1().min_w(0).truncate().text_color(PALETTE.text).child(file ? baseName(file) : ""));
  }

  // Markdown の外枠。文字は GitHub に寄せ、本文の幅を絞って中央に置く。FONT の決め打ちはここで上書きする
  renderMarkdown(v) {
    const column = v_flex()
      .id("preview-markdown")
      .w_full()
      .max_w(MARKDOWN.maxWidth)
      .h_full()
      .px(MARKDOWN.padX)
      .py(MARKDOWN.padY)
      .font_family(MARKDOWN.font)
      .text_size(MARKDOWN.size)
      .line_height(MARKDOWN.line)
      .child(TextView.markdown("preview-md", v.text).selectable(true).scrollable(true).flex_1().min_h(0).w_full())
      .children(v.truncated ? [div().flex_none().pt(8).text_color(theme().dim).child(TRUNCATED_NOTE)] : []);
    return h_flex().flex_1().min_h(0).justify_center().child(column);
  }

  renderBody() {
    const v = this.view;
    const t = theme();
    const note = (text) => div().p(METRICS.padLeft).text_color(t.dim).child(text);
    // タブを切り替えた直後など、見出しのファイルと出ている表示が違う間は、前のファイルを出さない
    if (!v || (v.path ?? null) !== this.filePath()) return note("読み込み中");
    if (v.kind === "note") return note(v.text);
    if (v.kind === "markdown") return this.renderMarkdown(v);
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

  // ファイルの表示の本体 (見出しの段と中身)
  renderFile() {
    return v_flex().flex_1().min_h(0).child(this.renderHeader()).child(this.renderBody());
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
      this.stopFileWatch();
      return base.child(h_flex().flex_none().h(METRICS.row).pl(METRICS.padLeft).items_center().text_color(theme().dim).child(REMOTE_LABEL));
    }
    if (!tab) {
      this.stopFileWatch();
      return base;
    }
    this.sync(tab, cx);
    return base.child(this.renderFile());
  }
}
