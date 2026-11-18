// プレビューの判断。ファイルの種類、色付けの言語、縮小画像の置き場所、タブごとの状態。herdr には依存しない。

// EditorState の language に渡す名前。表にない拡張子は "text"
export const LANGUAGE = {
  nix: "nix",
  js: "js",
  ts: "js",
  tsx: "js",
  mjs: "js",
  cjs: "js",
  jsx: "js",
  json: "json",
  toml: "toml",
  yaml: "yaml",
  yml: "yaml",
  lua: "lua",
  bash: "bash",
  sh: "bash",
  zsh: "bash",
  css: "css",
  html: "html",
  md: "markdown",
  markdown: "markdown",
  rs: "rust",
  py: "python",
  go: "go",
};

const MARKDOWN = new Set(["md", "markdown"]);
const IMAGE = new Set(["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic"]);
const DOCUMENT = new Set(["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "pages", "numbers", "key"]);
const MODEL = new Set(["stl", "3mf", "step", "stp", "fcstd", "kicad_pcb", "kicad_sch", "kicad_pro"]);
const TEXT = new Set(["txt", "json", "toml", "yaml", "yml", "lua", "sh", "nix", "js", "ts", "css", "html"]);

// readTextFile の上限 (1 MiB)。超えるファイルは「大きすぎて表示できません」と大きさを出す
export const MAX_TEXT_BYTES = 1024 * 1024;
export const tooLargeMessage = "大きすぎて差分を出せません";

const baseName = (path) => String(path).split("/").pop() ?? "";

// 小文字の拡張子。拡張子のない名前と、. で始まるだけの名前 (.zshrc) は ""
export function extOf(path) {
  const name = baseName(path);
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
}

export function fileKind(path) {
  const ext = extOf(path);
  if (MARKDOWN.has(ext)) return "markdown";
  if (IMAGE.has(ext)) return "image";
  if (DOCUMENT.has(ext)) return "document";
  if (MODEL.has(ext)) return "model";
  if (ext === "" || ext in LANGUAGE || TEXT.has(ext)) return "code";
  return "other";
}

// GPUI が読めない画像 (HEIC、TIFF) は sips で PNG に直す
const CONVERT = new Set(["heic", "tiff"]);

// 画像として出すファイルの作り方と、写しの拡張子。画像として出さないものは null
export function imagePlan(path) {
  const kind = fileKind(path);
  const ext = extOf(path);
  if (kind === "document") return { method: "thumbnail", ext: "png" };
  if (kind !== "image") return null;
  return CONVERT.has(ext) ? { method: "convert", ext: "png" } : { method: "copy", ext };
}

export const languageOf =(path) => LANGUAGE[extOf(path)] ?? "text";

// FNV-1a (32 ビット) を 2 回、別の種で回して 16 桁の 16 進にする
function fnv1a(text, seed) {
  let h = seed >>> 0;
  for (const ch of text) {
    let c = ch.codePointAt(0);
    while (c > 0) {
      h ^= c & 0xff;
      h = Math.imul(h, 0x01000193) >>> 0;
      c >>>= 8;
    }
  }
  return h.toString(16).padStart(8, "0");
}

// image() はアプリのフォルダの中しか読めないので、写しをここに置く。
// パスと mtime から名前を決めるので、ファイルが変わらなければ同じ写しを使い回す
export function previewCachePath(appHome, path, mtimeMs, ext) {
  const key = `${path}\0${mtimeMs}`;
  return `${appHome}/data/preview/${fnv1a(key, 0x811c9dc5)}${fnv1a(key, 0x050c5d1f)}.${ext}`;
}

export function formatSize(bytes) {
  if (bytes == null || !Number.isFinite(bytes)) return "?";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
}

// 写しが max 件を超えたら、古いもの (mtime が小さいもの) から消す名前
export function pruneTargets(entries, max) {
  if (entries.length <= max) return [];
  return [...entries]
    .sort((a, b) => a.mtime - b.mtime)
    .slice(0, entries.length - max)
    .map((e) => e.name);
}

// タブごとの状態。追従中は差分、固定すると全体が既定
export const initialTabState = () => ({ mode: "follow", pinned: null, view: "diff", historyIndex: 0 });
export const pin = (state, path) => ({ ...state, mode: "pinned", pinned: path, view: "full" });
export const follow = (state) => ({ ...state, mode: "follow", view: "diff", historyIndex: 0 });
export const toggleView = (state) => ({ ...state, view: state.view === "diff" ? "full" : "diff" });
export function moveHistory(state, delta, length) {
  const last = Math.max(0, length - 1);
  return { ...state, historyIndex: Math.min(last, Math.max(0, state.historyIndex + delta)) };
}
