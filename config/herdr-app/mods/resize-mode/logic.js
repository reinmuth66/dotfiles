// 大きさを変えるモードの判断。herdr に依存しない (node --test で試す)

// 1 回に動かす量 (px)
export const STEP = 20;

// キーは WezTerm の resize_pane と同じ: u 上、o 左、a 下、i 右
const MOVES = {
  o: { target: "vertical", delta: -STEP },
  i: { target: "vertical", delta: STEP },
  u: { target: "horizontal", delta: -STEP },
  a: { target: "horizontal", delta: STEP },
};

// 押したキーを、境目の動きか、モードを抜けること ("exit") に変える。関係ないキーは null
export function keyToMove(key) {
  if (key === "enter" || key === "escape") return "exit";
  const move = MOVES[key];
  return move ? { ...move } : null;
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
