// ツリーの判断。git の状態の読み取り、アイコン、行の平坦化、根、開く道具。herdr に依存しない。
import { GLYPH, PALETTE, isRemoteSpace } from "./ui.js";

// 根の行の数の並び
export const ORDER = ["staged", "added", "modified", "deleted", "untracked", "conflict"];
// 前ほど強い (git.yazi の CODES と同じ)。フォルダは中で一番強いものを引き継ぐ
export const STRENGTH = ["untracked", "modified", "staged", "added", "deleted", "conflict"];

export const GIT_STYLE = {
  staged: { glyph: GLYPH.diffModified, color: PALETTE.blue },
  added: { glyph: GLYPH.diffAdded, color: PALETTE.green },
  modified: { glyph: GLYPH.diffModified, color: PALETTE.yellow },
  deleted: { glyph: GLYPH.diffRemoved, color: PALETTE.red },
  untracked: { glyph: "?", color: PALETTE.overlay2 },
  conflict: { glyph: GLYPH.diffModified, color: PALETTE.peach },
};

function stateOf(x, y) {
  if (x === "?" && y === "?") return "untracked";
  if ((x === "U" || y === "U") || (x === "A" && y === "A") || (x === "D" && y === "D")) return "conflict";
  if (y === "M" || y === "T") return "modified";
  if (y === "D") return "deleted";
  if (y === "A") return "added";
  if (x === "A") return "added";
  if ("MDRCT".includes(x) && x !== " ") return "staged";
  return null;
}

// `git status --porcelain=v1 -z --no-renames --untracked-files=all` の出力から、パスごとの状態を作る
export function parseStatus(z) {
  const out = {};
  for (const entry of String(z ?? "").split("\0")) {
    if (entry.length < 4) continue;
    const state = stateOf(entry[0], entry[1]);
    if (state) out[entry.slice(3)] = state;
  }
  return out;
}

export function folderState(states, folder) {
  const prefix = folder === "" ? "" : `${folder}/`;
  let best = null;
  for (const [rel, state] of Object.entries(states)) {
    if (prefix && !rel.startsWith(prefix)) continue;
    if (best === null || STRENGTH.indexOf(state) < STRENGTH.indexOf(best)) best = state;
  }
  return best;
}

export function counts(states) {
  const n = {};
  for (const state of Object.values(states)) n[state] = (n[state] ?? 0) + 1;
  return ORDER.filter((state) => n[state]).map((state) => ({ state, n: n[state] }));
}

const DEFAULT_ICON = { text: "\u{f0214}", fg: PALETTE.text };

// yazi の表 (files、exts、conds の !dir の順) から、ファイルのアイコンを選ぶ
export function fileIcon(name, table) {
  if (!table) return DEFAULT_ICON;
  const byName = table.files?.find((f) => f.name === name);
  if (byName) return { text: byName.text, fg: byName.fg };
  const dot = name.lastIndexOf(".");
  if (dot > 0) {
    const ext = name.slice(dot + 1).toLowerCase();
    const byExt = table.exts?.find((e) => e.name.toLowerCase() === ext);
    if (byExt) return { text: byExt.text, fg: byExt.fg };
  }
  const fallback = table.conds?.find((c) => c.if === "!dir");
  return fallback ? { text: fallback.text, fg: fallback.fg } : DEFAULT_ICON;
}

// フォルダが先、名前順。showHidden が false なら、`.` で始まるものと ignored を出さない
export function flatten({ children, open, showHidden, ignored }) {
  const rows = [];
  const walk = (dirRel, depth) => {
    const entries = (children[dirRel] ?? [])
      .filter((e) => showHidden || (!e.name.startsWith(".") && !ignored.has(dirRel ? `${dirRel}/${e.name}` : e.name)))
      .sort((a, b) => (a.dir === b.dir ? a.name.localeCompare(b.name) : a.dir ? -1 : 1));
    for (const e of entries) {
      const rel = dirRel ? `${dirRel}/${e.name}` : e.name;
      const isOpen = e.dir && open.has(rel);
      rows.push({ rel, name: e.name, dir: e.dir, depth, open: isOpen });
      if (isOpen) walk(rel, depth + 1);
    }
  };
  walk("", 0);
  return rows;
}

// 根は今見ている枠の場所で決める: 枠の cwd の git のルート、space の folder の git のルート、
// space の folder (空ならホーム) の順。別のコンピューターの space と、space がないときは null
export function treeRoot({ space, repoRoot, cwdRepoRoot = null, home }) {
  if (!space || isRemoteSpace(space)) return null;
  return cwdRepoRoot ?? repoRoot ?? (space.folder || home);
}

// 親の行の位置。rows は 0 が根、その後に flatten の行 (depth を持つ)。根の親はない (null)
export function parentIndex(rows, i) {
  const row = rows[i];
  if (!row || row.kind === "root") return null;
  if (row.depth === 0) return 0;
  for (let j = i - 1; j > 0; j--) if (rows[j].depth === row.depth - 1) return j;
  return 0;
}
