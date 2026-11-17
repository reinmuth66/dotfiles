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

// キーは WezTerm の resize_pane と同じ: u 上、o 左、a 下、i 右。
// o と i はプレビューの幅、Shift を付けると帯の幅、u と a は帯の中の一覧の高さ
const MOVES = {
  o: { target: "preview", delta: -STEP },
  i: { target: "preview", delta: STEP },
  u: { target: "workspace", delta: -STEP },
  a: { target: "workspace", delta: STEP },
};

// 押したキーを、境目の動き、モードを抜けること ("exit")、モードを畳んでキーを素通しにすること
// ("collapse") に変える。関係ないキーは null
export function keyToMove(key, modifiers = {}) {
  if (modifiers.control || modifiers.alt || modifiers.platform) return "collapse";
  if (key === "enter" || key === "escape") return "exit";
  const move = MOVES[key];
  if (!move) return null;
  if (modifiers.shift && (key === "o" || key === "i")) return { ...move, target: "sidebar" };
  return { ...move };
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
