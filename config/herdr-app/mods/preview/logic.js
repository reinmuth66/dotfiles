// プレビューの判断。ファイルの種類、色付けの言語、縮小画像の置き場所、タブごとの状態。herdr には依存しない。
// EditorState の language に渡す名前のうち、拡張子と名前が違うもの (herdr の files の mod の表に nix を足した)。
// 表にない拡張子は拡張子そのものを渡す (languageOf)
export const LANGUAGE = {
  ts: "js",
  tsx: "js",
  mts: "js",
  cts: "js",
  jsx: "js",
  mjs: "js",
  toml: "yaml",
  jsonc: "json",
  svelte: "html",
  vue: "html",
  nix: "ruby",
};

const MARKDOWN = new Set(["md", "markdown"]);
const CSV = new Set(["csv", "tsv"]);
const IMAGE = new Set(["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic"]);
const DOCUMENT = new Set(["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "pages", "numbers", "key"]);
const MODEL = new Set(["stl", "3mf", "step", "stp", "fcstd", "kicad_pcb", "kicad_sch", "kicad_pro"]);
const ARCHIVE = new Set(["zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "dmg", "iso"]);

// readTextFile の上限 (1 MiB)。超えるファイルは「大きすぎて表示できません」と大きさを出す
export const MAX_TEXT_BYTES = 1024 * 1024;

// 文字として読むファイルの読み方。上限を超えるとき、CSV と TSV は先頭だけ ("head")、ほかは読まない ("too-large")
export function readPlan(kind, size) {
  if (size <= MAX_TEXT_BYTES) return "full";
  return kind === "csv" ? "head" : "too-large";
}

// 先頭だけ読んだ文字列から、途中で切れた最後の行を落とす。改行がなければそのまま
export function cutToLastLine(text) {
  const i = text.lastIndexOf("\n");
  return i < 0 ? text : text.slice(0, i + 1);
}

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
  if (CSV.has(ext)) return "csv";
  if (ext === "json") return "json";
  if (IMAGE.has(ext)) return "image";
  if (DOCUMENT.has(ext)) return "document";
  if (MODEL.has(ext)) return "model";
  if (ARCHIVE.has(ext)) return "other";
  // 色付けされない拡張子も Editor で出す。バイナリは読んだあとの NUL で見分ける (main.js)
  return "code";
}

// 区切り文字。tsv はタブ、ほかは ,
export const separatorOf = (path) => (extOf(path) === "tsv" ? "\t" : ",");

// GPUI が読めない画像 (HEIC、TIFF) は sips で PNG に直す
const CONVERT = new Set(["heic", "tiff"]);

const KICAD_CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli";
const dirOf = (path) => String(path).replace(/\/[^/]*$/, "") || "/";
// zip の中の縮小画像を取り出す。画像は文字ではないので exec の標準出力では受けず、シェルでファイルに書く
const unzipTo = (script, path, out) => ({ cmd: "sh", args: ["-c", script, "sh", path, out], timeout: 5000 });

// モデルの縮小画像を out に作るコマンド。STL と STEP は f3d が nixpkgs の darwin で作れないので扱わない (null)。
// 3MF は Bambu Studio などが Metadata/thumbnail.png を書かず plate_1.png だけを書くので、そちらも見る。
// KiCad の基板は層の指定が要る。回路図は --output にフォルダを取り、<元の名前>.svg を書く (thumbnailOutput)
export function thumbnailCommand(path, out) {
  switch (extOf(path)) {
    case "3mf":
      return unzipTo(
        'unzip -p "$1" Metadata/thumbnail.png > "$2" 2>/dev/null || unzip -p "$1" Metadata/plate_1.png > "$2"',
        path,
        out,
      );
    case "fcstd":
      return unzipTo('unzip -p "$1" thumbnails/Thumbnail.png > "$2"', path, out);
    case "kicad_pcb":
      return {
        cmd: KICAD_CLI,
        args: [
          "pcb",
          "export",
          "svg",
          "--mode-single",
          "--layers",
          "F.Cu,B.Cu,F.SilkS,Edge.Cuts",
          "--exclude-drawing-sheet",
          "--fit-page-to-board",
          "--output",
          out,
          path,
        ],
        timeout: 15000,
      };
    case "kicad_sch":
      return { cmd: KICAD_CLI, args: ["sch", "export", "svg", "--output", dirOf(out), path], timeout: 15000 };
    default:
      return null;
  }
}

// thumbnailCommand が実際に書くファイル
export function thumbnailOutput(path, out) {
  if (extOf(path) !== "kicad_sch") return out;
  const name = baseName(path);
  return `${dirOf(out)}/${name.slice(0, name.lastIndexOf("."))}.svg`;
}

// 画像として出すファイルの作り方と、写しの拡張子。画像として出さないものは null
export function imagePlan(path) {
  const kind = fileKind(path);
  const ext = extOf(path);
  if (kind === "document") return { method: "thumbnail", ext: "png" };
  if (kind === "model") {
    if (!thumbnailCommand(path, "")) return null;
    return { method: "model", ext: ext.startsWith("kicad_") ? "svg" : "png" };
  }
  if (kind !== "image") return null;
  return CONVERT.has(ext) ? { method: "convert", ext: "png" } : { method: "copy", ext };
}

export function languageOf(path) {
  const ext = extOf(path);
  return LANGUAGE[ext] ?? (ext || "text");
}

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
// パスと mtime から名前を決めるので、ファイルが変わらなければ同じ写しを使い回す。
// data/<mod の名前>/ は herdr が mod の localStorage に使うので、別の名前のフォルダに置く
export const PREVIEW_CACHE_DIR = "data/preview-cache";
export function previewCachePath(appHome, path, mtimeMs, ext) {
  const key = `${path}\0${mtimeMs}`;
  return `${appHome}/${PREVIEW_CACHE_DIR}/${fnv1a(key, 0x811c9dc5)}${fnv1a(key, 0x050c5d1f)}.${ext}`;
}

// previewCachePath が作った名前か (16 桁の 16 進と拡張子)
export const isCacheFile = (name) => /^[0-9a-f]{16}\.[a-z0-9_]+$/.test(name);

export function formatSize(bytes) {
  if (bytes == null || !Number.isFinite(bytes)) return "?";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
}

// 写しが max 件を超えたら、古いもの (mtime が小さいもの) から消す名前。
// 自分が作った名前 (isCacheFile) だけを数え、ほかのファイルは消さない
export function pruneTargets(entries, max) {
  const own = entries.filter((e) => isCacheFile(e.name));
  if (own.length <= max) return [];
  return own
    .sort((a, b) => a.mtime - b.mtime)
    .slice(0, own.length - max)
    .map((e) => e.name);
}

// タブごとの状態。view は "file" だけ。file は出しているファイル
export const initialTabState = () => ({ view: "file", file: null });

// 今のタブのエージェントの端末。複数なら focused().terminal と同じもの、なければ最初のもの
export function agentTerminalFor(agents, focused) {
  if (!focused?.tab) return null;
  const inTab = agents.filter((a) => a.tab === focused.tab);
  if (inTab.length === 0) return null;
  return (inTab.find((a) => a.address === focused.terminal) ?? inTab[0]).address;
}

// JSON は 2 字下げで整形する。読めなければ (壊れた JSON、jsonc) 元の文字のまま
export function formatJson(text) {
  try {
    return JSON.stringify(JSON.parse(text), null, 2);
  } catch {
    return text;
  }
}

// フォルダの README の名前。この順で最初に見つかったもの (大文字と小文字は区別しない)。返すのは names の中の元の綴り
const README_NAMES = ["readme.md", "readme.markdown", "readme"];
export function readmeName(names) {
  for (const want of README_NAMES) {
    const found = names.find((n) => n.toLowerCase() === want);
    if (found) return found;
  }
  return null;
}

// 開いたツールの窓 (openOverlay の popup) の場所と大きさ。
// area (ポインタが preview を通ったときに覚えた、窓の中の位置と大きさ) があればそれ。無ければレイアウトの
// 一番上の段から preview-area の左端 (前の兄弟の px と区切りの幅の和) と幅を出し、高さは窓いっぱい (1)。
// それも分からなければ真ん中に出す
const OPEN_FALLBACK = { width: 0.5, height: 0.9 };
export function openPlace(area, layout) {
  if (area) return { at: { x: area.x, y: area.y }, width: area.width, height: area.height };
  const children = layout?.children ?? [];
  const i = children.findIndex((c) => c.id === "preview-area");
  const width = children[i]?.size?.px;
  if (i < 0 || !width) return OPEN_FALLBACK;
  const divider = layout.divider?.width ?? 0;
  let x = 0;
  for (const c of children.slice(0, i)) {
    if (c.hidden) continue;
    if (!c.size?.px) return OPEN_FALLBACK;
    x += c.size.px + divider;
  }
  return { at: { x, y: 0 }, width, height: 1 };
}
