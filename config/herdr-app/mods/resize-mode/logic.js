// 大きさを変えるモードの判断。herdr に依存しない (node --test で試す)

// 1 回に動かす量 (px)
export const STEP = 20;

// 動かすブロックと、下限と上限、レイアウトに px の値がないときの大きさ。
// プレビューの上限は、エージェントの枠が潰れないよう 900 に抑える (同梱の main の右パネルと同じ)
export const LIMITS = {
  sidebar: { id: "sidebar", min: 160, max: 480, fallback: 240 },
  preview: { id: "preview-area", min: 160, max: 900, fallback: 480 },
  workspace: { id: "workspace", min: 80, max: 1200, fallback: 300 },
};

// u / a / o / i は、focus していた pane の境目を上 / 下 / 左 / 右へ動かす (pane.resize)。
// Shift を付けた ijkl は、j と l がプレビューの幅、i と k が帯の中の一覧の高さ。y と h は帯の幅 (狭く / 広く)
const PANE_MOVES = { u: "up", a: "down", o: "left", i: "right" };
const SHIFT_MOVES = {
  j: { target: "preview", delta: STEP },
  l: { target: "preview", delta: -STEP },
  k: { target: "workspace", delta: STEP },
  i: { target: "workspace", delta: -STEP },
};
const SIDEBAR_MOVES = {
  y: { target: "sidebar", delta: -STEP },
  h: { target: "sidebar", delta: STEP },
};

// 押したキーを、境目の動き、モードを抜けること ("exit")、モードを畳んでキーを素通しにすること
// ("collapse") に変える。関係ないキーは null
export function keyToMove(key, modifiers = {}) {
  if (modifiers.control || modifiers.alt || modifiers.platform) return "collapse";
  if (key === "enter" || key === "escape") return "exit";
  if (Object.hasOwn(SIDEBAR_MOVES, key)) return { ...SIDEBAR_MOVES[key] };
  if (modifiers.shift) return Object.hasOwn(SHIFT_MOVES, key) ? { ...SHIFT_MOVES[key] } : null;
  return Object.hasOwn(PANE_MOVES, key) ? { target: "pane", direction: PANE_MOVES[key] } : null;
}

// 今の大きさに delta を足し、下限と上限で止める
export function nextSize(current, delta, min, max) {
  return Math.min(max, Math.max(min, current + delta));
}

// 帯の 3 通り: 両方 -> 一覧だけ -> ツリーだけ -> 両方
const SIDEBAR_MODES = ["both", "list", "tree"];

export function nextSidebarMode(mode) {
  const i = SIDEBAR_MODES.indexOf(mode);
  return SIDEBAR_MODES[(i + 1) % SIDEBAR_MODES.length];
}

// wtr の出し入れの次の一手を決める
export function wtrStep({ hidden, active, onWtr }) {
  if (hidden || active !== "wtr") return "show";
  if (!onWtr) return "focus";
  return "hide";
}
