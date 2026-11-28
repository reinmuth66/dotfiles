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

// h と l はプレビューの幅、Shift を付けると帯の幅、j と k は帯の中の一覧の高さ
const MOVES = {
  h: { target: "preview", delta: STEP },
  l: { target: "preview", delta: -STEP },
  j: { target: "workspace", delta: STEP },
  k: { target: "workspace", delta: -STEP },
};

// 押したキーを、境目の動き、モードを抜けること ("exit")、モードを畳んでキーを素通しにすること
// ("collapse") に変える。関係ないキーは null
export function keyToMove(key, modifiers = {}) {
  if (modifiers.control || modifiers.alt || modifiers.platform) return "collapse";
  if (key === "enter" || key === "escape") return "exit";
  const move = MOVES[key];
  if (!move) return null;
  if (modifiers.shift && (key === "h" || key === "l")) {
    return { target: "sidebar", delta: -move.delta };
  }
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

// wtr の出し入れの次の一手を決める
export function wtrStep({ hidden, active, onWtr }) {
  if (hidden || active !== "wtr") return "show";
  if (!onWtr) return "focus";
  return "hide";
}
