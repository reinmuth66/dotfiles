// プレビュー。ツリーで選んだファイル (shared("tree-selection")) が今見ているタブのものなら、その全体を出す。
// Markdown は整形、コードは色付き、画像はアプリのフォルダへの写し、文書は qlmanage の縮小画像、
// それ以外は種類と大きさだけ。判断は logic.js にある。追従と差分は後の Task で足す
import * as fs from "fs/promises";
import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, TextView } from "gpui-base";
import { appHome, checking, exec, focused, nextCommand, readTextFile, settings, shared, spaces, theme } from "herdr";
import { METRICS, PALETTE, REMOTE_LABEL, isRemoteSpace } from "./ui.js";
import { MAX_TEXT_BYTES, extOf, fileKind, formatSize, imagePlan, languageOf, previewCachePath, pruneTargets } from "./logic.js";

const FONT = "Moralerspace Neon HW";
const FILE_ICON = "\u{f0214}";
const CACHE_MAX = 200;
const STAT_TIMEOUT = 5000;
const COPY_TIMEOUT = 5000;
const THUMB_TIMEOUT = 15000;

const baseName = (path) => String(path).split("/").pop() || path;

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

export default class Preview extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.byTab = new Map(); // タブ → ツリーで選んだパス
    this.seenAt = null; // 最後に受け取った tree-selection の at
    this.path = null; // 出しているファイル
    this.loadKey = null; // path と mtime。同じなら作り直さない
    this.view = null; // { kind: "loading" | "markdown" | "code" | "image" | "info", ... }
    this.code = null; // EditorState
    this.token = 0;
    if (checking()) return;
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "focus") this.handle.focus();        cx.notify();
      }
    });
  }

  close() {
    this.code?.release();
    this.code = null;
  }

  // tree-selection を受け取り、今のタブで出すパスを決める
  sync(cx) {
    const sel = shared("tree-selection");
    let fresh = false;
    if (sel?.path && sel.at !== this.seenAt) {
      this.seenAt = sel.at;
      this.byTab.set(sel.tab, sel.path);
      fresh = sel.tab === (focused()?.tab ?? null);
    }
    const path = this.byTab.get(focused()?.tab ?? null) ?? null;
    if (path !== this.path || fresh) this.load(path, cx);
  }

  setCode(state) {
    if (this.code !== state) this.code?.release();
    this.code = state;
  }

  load(path, cx) {
    const changed = path !== this.path;
    this.path = path;
    const token = ++this.token;
    if (!path) {
      this.setCode(null);
      this.loadKey = null;
      this.view = null;
      return;
    }
    if (changed) this.view = { kind: "loading" };
    cx.spawn(async (cx) => {
      const view = await this.build(path);
      if (token !== this.token) {
        if (view.state && view.state !== this.code) view.state.release();
        return;
      }
      if (view.kind === "code") this.setCode(view.state);
      else this.setCode(null);
      this.view = view;
      cx.notify();
    });
  }

  async build(path) {
    const kind = fileKind(path);
    const ext = extOf(path);
    const info = (stat, note) => ({ kind: "info", ext, size: stat?.size ?? null, note });
    const stat = await statFile(path);
    if (!stat) return info(null, "読めません");
    const key = `${path}\0${stat.mtimeMs}`;
    if (key === this.loadKey && this.view && this.view.kind !== "loading") return this.view;
    this.loadKey = key;
    try {
      if (kind === "markdown" || kind === "code") {
        if (stat.size > MAX_TEXT_BYTES) return info(stat, "大きすぎて表示できません");
        const text = await readTextFile(path);
        if (text == null) return info(stat, "読めません");
        if (text.includes("\0")) return info(stat, null);
        if (kind === "markdown") return { kind: "markdown", text };
        const t = theme();
        const state = EditorState.new({
          language: languageOf(path),
          value: text,
          readonly: true,
          font_family: settings().font_family,
          syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, number: t.ansi3, function: t.ansi4, type: t.ansi6 },
        });
        return { kind: "code", state };
      }
      const plan = imagePlan(path);
      if (plan) {
        const home = appHome();
        const dir = `${home}/data/preview`;
        const dest = previewCachePath(home, path, stat.mtimeMs, plan.ext);
        if (!(await fs.exists(dest))) {
          await fs.mkdir(dir, { recursive: true });
          if (!(await this.makeImage(plan.method, path, dest, home))) return info(stat, null);
          await pruneCache(dir);
        }
        return { kind: "image", rel: dest.slice(home.length + 1) };
      }
    } catch {
      return info(stat, "読めません");
    }
    return info(stat, null);
  }

  // 読み込みごとに data/preview-tmp/ の下へ自分だけの一時フォルダを作り、そこで写し (cp)、
  // PNG への変換 (sips)、縮小画像 (qlmanage) を作ってから、mv で写しの場所へ置く。
  // 途中で失敗しても写しの場所には書きかけが残らない。一時フォルダは成否によらず消す
  async makeImage(method, path, dest, home) {
    const base = `${home}/data/preview-tmp`;
    await fs.mkdir(base, { recursive: true });
    const mk = await exec("mktemp", ["-d", `${base}/load.XXXXXX`], { timeout: COPY_TIMEOUT }).catch(() => null);
    const tmpDir = mk?.code === 0 ? mk.stdout.trim() : null;
    if (!tmpDir) return false;
    try {
      let made = null;
      if (method === "copy") {
        made = `${tmpDir}/copy`;
        const r = await exec("cp", [path, made], { timeout: COPY_TIMEOUT }).catch(() => null);
        if (r?.code !== 0) return false;
      } else if (method === "convert") {
        made = `${tmpDir}/convert.png`;
        const r = await exec("sips", ["-s", "format", "png", path, "--out", made], { timeout: THUMB_TIMEOUT }).catch(() => null);
        if (r?.code !== 0) return false;
      } else {
        // qlmanage は <名前>.png を書く
        const r = await exec("qlmanage", ["-t", "-s", "800", "-o", tmpDir, path], { timeout: THUMB_TIMEOUT }).catch(() => null);
        if (r?.code !== 0) return false;
        made = `${tmpDir}/${baseName(path)}.png`;
      }
      if (!(await fs.exists(made))) return false;
      const mv = await exec("mv", ["-f", made, dest], { timeout: COPY_TIMEOUT }).catch(() => null);
      return mv?.code === 0;
    } finally {
      await exec("rm", ["-rf", tmpDir], { timeout: COPY_TIMEOUT }).catch(() => {});
    }
  }

  renderHeader() {
    return h_flex()
      .flex_none()
      .h(METRICS.row)
      .pl(METRICS.padLeft)
      .pr(METRICS.padLeft)
      .gap(8)
      .items_center()
      .child(div().flex_1().min_w(0).truncate().text_color(PALETTE.text).child(baseName(this.path)))
      .child(div().flex_none().text_color(PALETTE.peach).child("固定"));
  }

  renderBody() {
    const v = this.view;
    const t = theme();
    const note = (text) => div().p(METRICS.padLeft).text_color(t.dim).child(text);
    if (!v || v.kind === "loading") return note("読み込み中");
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
    if (isRemoteSpace(currentSpace())) {
      return base.child(h_flex().flex_none().h(METRICS.row).pl(METRICS.padLeft).items_center().text_color(theme().dim).child(REMOTE_LABEL));
    }
    this.sync(cx);
    if (!this.path) return base;
    return base.child(this.renderHeader()).child(this.renderBody());
  }
}
