// 利用制限の表示の組み立て。herdr に依存しない (node --test で試す)
import { PALETTE } from "./ui.js";

const MODES = ["active", "all", "pinned"];

// active → all → pinned → active
export function nextMode(mode) {
  const i = MODES.indexOf(mode);
  return MODES[(i + 1) % MODES.length];
}

// 出すエージェントの種類。どれもファイル (data/limits/<種類>.json) があるものだけ
export function visibleAgents({ mode, pinned, files, activeApp, lastApp }) {
  const has = (name) => name != null && Object.hasOwn(files, name);
  if (mode === "all") return Object.keys(files).sort();
  if (mode === "pinned") return has(pinned) ? [pinned] : [];
  const name = activeApp ?? lastApp;
  return has(name) ? [name] : [];
}

// statusline.sh の format_countdown と同じ形 (3d04h、2h05m、40m)
function formatCountdown(secs) {
  const pad = (n) => String(n).padStart(2, "0");
  const d = Math.floor(secs / 86400);
  const h = Math.floor((secs % 86400) / 3600);
  const m = Math.floor((secs % 3600) / 60);
  if (d > 0) return `${d}d${pad(h)}h`;
  if (h > 0) return `${h}h${pad(m)}m`;
  return `${m}m`;
}

const BASE_COLOR = { "5h": "sky", "7d": "mauve" };

// 1 本の帯の値。used は使用率 (%)、elapsed と over は 0 から 1 の割合。
// リセットの時刻を過ぎていたら、statusline が書き直すまで次の窓 (使用率 0) を推定して出す
export function windowView(w, nowSec) {
  const known = w.resets_at != null && w.duration > 0;
  const passed = known && nowSec >= w.resets_at;
  const resetsAt = passed ? w.resets_at + w.duration * (Math.floor((nowSec - w.resets_at) / w.duration) + 1) : w.resets_at;
  const used = passed ? 0 : Number(w.used_percentage) || 0;
  const elapsed = known ? Math.min(1, Math.max(0, 1 - (resetsAt - nowSec) / w.duration)) : null;
  const over = elapsed == null ? 0 : Math.max(0, used / 100 - elapsed);
  const barColor = PALETTE[BASE_COLOR[w.key] ?? "sky"];
  return {
    used,
    elapsed,
    over,
    remaining: known ? formatCountdown(Math.floor(resetsAt - nowSec)) : null,
    barColor, // 帯の使用分の色。90% 以上でも区切りの色のまま
    usedColor: used >= 90 ? PALETTE.red : barColor,
    overColor: over > 0 ? (over < 0.1 ? PALETTE.peach : PALETTE.red) : null,
  };
}
