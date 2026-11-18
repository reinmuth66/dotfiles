// herdr アプリの mod が共有する、記号、色、寸法、整形の部品。herdr に依存しない。
// 正本は config/herdr-app/shared/ui.js。mod は自分のフォルダの外を import できないので、
// 使う mod のフォルダに cp で写す (shared.test.js が、写しが正本と同じことを確かめる)。

export const GLYPH = {
  spaceClosed: "\u{f003c}",
  spaceOpen: "\u{f120e}",
  yazi: "\u{f01e5}",
  shell: "\u{f018d}",
  chevronRight: "\u{f0142}",
  chevronDown: "\u{f0140}",
  folder: "\u{f07b}",
  folderOpen: "\u{f07c}",
  rootClosed: "\u{f069d}",
  rootOpen: "\u{f0dcf}",
  diffModified: "\u{f459}",
  diffAdded: "\u{f457}",
  diffRemoved: "\u{f458}",
  branch: "\u{f418}",
  terminal: "\u{f489}",
};

// WezTerm の process_icons から。yazi だけ md_duck
export const PROCESS_ICONS = {
  git: "\u{e702}",
  lazygit: "\u{e702}",
  gh: "\u{e709}",
  lua: "\u{e620}",
  nvim: "\u{e62b}",
  vim: "\u{e62b}",
  python: "\u{e73c}",
  python3: "\u{e73c}",
  ssh: "\u{f233}",
  yazi: GLYPH.yazi,
};

export const STATUS = {
  blocked: { glyph: "\u{f0028}", color: "peach", label: "Waiting" },
  done: { glyph: "\u{f05e0}", color: "green", label: "Done" },
  working: { glyph: "\u{f07c3}", color: "blue", label: "Working" },
  idle: { glyph: "\u{f0376}", color: "overlay0", label: "Idle" },
};
export const STATUS_ORDER = ["blocked", "done", "working", "idle"];

// Catppuccin Macchiato
export const PALETTE = {
  rosewater: "#f4dbd6",
  flamingo: "#f0c6c6",
  pink: "#f5bde6",
  mauve: "#c6a0f6",
  red: "#ed8796",
  maroon: "#ee99a0",
  peach: "#f5a97f",
  yellow: "#eed49f",
  green: "#a6da95",
  teal: "#8bd5ca",
  sky: "#91d7e3",
  sapphire: "#7dc4e4",
  blue: "#8aadf4",
  lavender: "#b7bdf8",
  text: "#cad3f5",
  subtext0: "#a5adcb",
  overlay2: "#939ab7",
  overlay0: "#6e738d",
  surface0: "#363a4f",
};

export const METRICS = {
  fontSize: 12,
  cell: 6.3,
  glyphSize: 16,
  indentCells: 3,
  gapCells: 1,
  slotCells: 2,
  row: 28,
  treeRow: 24,
  padLeft: 10,
  glyphCol: 20,
  ring: 22,
  ringStroke: 2,
};

export const cells = (n) => n * METRICS.cell;

// 仮の名簿 (状態の色 peach、green、blue と被らない色)
export const ROSTER = [
  { name: "Mocha", color: "flamingo" },
  { name: "Latte", color: "rosewater" },
  { name: "Pecan", color: "maroon" },
  { name: "Maple", color: "pink" },
  { name: "Cocoa", color: "mauve" },
  { name: "Ginger", color: "teal" },
  { name: "Olive", color: "sapphire" },
  { name: "Basil", color: "lavender" },
];

// 仮のマーク。"Mocha 2" の番号は除いて名簿を引く
export function mark(name) {
  const base = String(name ?? "").replace(/\s+\d+$/, "");
  const entry = ROSTER.find((e) => e.name === base);
  return { letter: base.charAt(0).toUpperCase(), color: PALETTE[entry ? entry.color : "overlay2"] };
}

export function mostUrgent(statuses) {
  for (const s of STATUS_ORDER) if (statuses.includes(s)) return s;
  return null;
}

export function contextPercent(context) {
  if (!context || !(context.size > 0)) return null;
  return (context.used / context.size) * 100;
}

export function contextColor(pct) {
  if (pct >= 80) return PALETTE.red;
  if (pct >= 50) return PALETTE.peach;
  return PALETTE.green;
}

// 自動の要約 (85%) までに残るトークン数
export function tokensToCompact(context) {
  if (!context || !(context.size > 0)) return null;
  return Math.max(0, Math.floor(context.size * 0.85) - context.used);
}

export function formatTokens(n) {
  return `${(Math.floor(n / 100) / 10).toFixed(1)}K`;
}

export function formatDuration(ms) {
  const total = Math.floor(ms / 1000);
  const pad = (n) => String(n).padStart(2, "0");
  if (total < 60) return `${total}s`;
  const minutes = Math.floor(total / 60);
  if (minutes < 10) return `${minutes}m${pad(total % 60)}s`;
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h${pad(minutes % 60)}m`;
}

// 12 時の位置から時計回りに描く輪の弧。SVG の path (M start A r r 0 largeArc 1 end) に使う
export function ringArc(fraction, outer, stroke) {
  if (!(fraction > 0)) return null;
  const r = (outer - stroke) / 2;
  const cx = outer / 2;
  const cy = outer / 2;
  const start = [cx, cy - r];
  if (fraction >= 0.999) return { r, cx, cy, start, end: start, largeArc: false, full: true };
  const angle = fraction * 2 * Math.PI;
  return {
    r,
    cx,
    cy,
    start,
    end: [cx + r * Math.sin(angle), cy - r * Math.cos(angle)],
    largeArc: fraction > 0.5,
    full: false,
  };
}

const baseName = (path) => path.replace(/\/+$/, "").split("/").pop() || path;

// 枠の見出しの、エージェント以外の 3 行 (プログラム、リポジトリの中のシェル、外のシェル)
export function paneLabel({ processName, shell, cwd, repoRoot, home }) {
  if (!shell) return { icon: (Object.hasOwn(PROCESS_ICONS, processName) ? PROCESS_ICONS[processName] : GLYPH.terminal), text: processName };
  const icon = GLYPH.shell;
  if (!cwd) return { icon, text: processName };
  const trim = (p) => (p.length > 1 ? p.replace(/\/+$/, "") : p);
  const dir = trim(cwd);
  if (repoRoot) {
    const root = trim(repoRoot);
    if (dir === root) return { icon, text: baseName(root) };
    if (dir.startsWith(`${root}/`)) return { icon, text: `${baseName(root)}${dir.slice(root.length)}` };
  }
  if (dir === trim(home)) return { icon, text: "~" };
  return { icon, text: baseName(dir) };
}

export const REMOTE_LABEL = "Other Computer";

// 別のコンピューターの space は machine が null でない
export const isRemoteSpace = (space) => Boolean(space) && space.machine != null;

// 別のコンピューターの端末、タブ、枠の ID は "laptop/t1" の形
export const isRemoteAddress = (id) => String(id).includes("/");
