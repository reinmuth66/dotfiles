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
  tabClosed: "\u{f0570}",
  tabOpen: "\u{f00c7}",
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
  fontSize: 13,
  cell: 6.9,
  glyphSize: 16,
  indentCells: 3,
  gapCells: 1,
  slotCells: 2,
  row: 28,
  treeRow: 24,
  padLeft: 10,
  glyphCol: 20,
  ring: 16,
  ringStroke: 1.5,
  agentIcon: 9,
  claudeIcon: 10,
};

export const cells = (n) => n * METRICS.cell;

const CLAUDE_MODEL = /\b(claude|opus|sonnet|haiku)\b/i;

// エージェントのアイコン。usage と同じ SVG を使う (claude は横長なので一回り大きく、agy で Claude 系のモデルは青)
export function agentIconSpec(program, model = null) {
  const key = program?.key ?? "";
  const name = String(program?.name ?? "").toLowerCase();
  if (key === "claude" || program?.icon === "icons/claude.svg") {
    return { src: "icons/claude.svg", tint: false, color: null, size: METRICS.claudeIcon };
  }
  if (key === "agy" || key === "antigravity" || name === "agy" || name === "antigravity" || program?.icon === "icons/antigravity.svg") {
    if (typeof model === "string" && CLAUDE_MODEL.test(model)) {
      return { src: "icons/claude.svg", tint: true, color: PALETTE.blue, size: METRICS.claudeIcon };
    }
    return { src: "icons/antigravity.svg", tint: false, color: null, size: METRICS.agentIcon };
  }
  if (program?.icon) {
    return { src: program.icon, tint: Boolean(program.tint), color: program.color ?? null, size: METRICS.agentIcon };
  }
  return null;
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

// 秒は出さない (0m、12m、1h05m)
export function formatDuration(ms) {
  const minutes = Math.floor(ms / 60_000);
  const pad = (n) => String(n).padStart(2, "0");
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h${pad(minutes % 60)}m`;
}

// 12 時を 0、時計回りに 1 周を 1 とする角度の円周上の点
export function ringPoint(cx, cy, r, fraction) {
  const angle = fraction * 2 * Math.PI;
  return [cx + r * Math.sin(angle), cy - r * Math.cos(angle)];
}

// from から to まで (0 から 1) の弧を、1/8 周以下の点列に分ける (gpui の arc_to は半周で半径がずれる)
export function arcSteps(from, to, outer, stroke) {
  const a = Math.max(0, from);
  const b = Math.min(1, to);
  if (!(b - a > 0)) return null;
  const r = (outer - stroke) / 2;
  const c = outer / 2;
  const steps = Math.max(1, Math.ceil((b - a) * 8));
  const start = ringPoint(c, c, r, a);
  const points = [];
  for (let i = 1; i <= steps; i++) points.push(ringPoint(c, c, r, a + ((b - a) * i) / steps));
  return { r, start, points };
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
