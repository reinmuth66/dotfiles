// 利用制限の表示の組み立て。herdr に依存しない (node --test で試す)
import { PALETTE } from "./ui.js";

export function dim(color) {
  return `${color}99`;
}

const AGY_WINDOWS = [
  { match: "Five Hour", key: "5h", duration: 18000 },
  { match: "Weekly", key: "7d", duration: 604800 },
];
const WINDOW_ORDER = { "5h": 0, "7d": 1 };

// agy-quota 出力を解析し、gemini と other に分けて 5h, 7d の順で返す
export function parseAgyQuota(text) {
  const pools = { gemini: [], other: [] };
  for (const line of String(text ?? "").split("\n")) {
    const parts = line.split("\t");
    if (parts.length !== 4) continue;
    const [group, label, pctStr, resetStr] = parts;
    const win = AGY_WINDOWS.find((w) => label.includes(w.match));
    if (!win) continue;
    const m = pctStr.trim().match(/^(\d+(?:\.\d+)?)%$/);
    if (!m) continue;
    const ms = Date.parse(resetStr.trim());
    const pool = group.startsWith("Gemini") ? pools.gemini : pools.other;
    pool.push({
      key: win.key,
      used_percentage: 100 - Number(m[1]),
      resets_at: Number.isFinite(ms) && ms > 0 ? ms / 1000 : null,
      duration: win.duration,
    });
  }
  const byKey = (a, b) => WINDOW_ORDER[a.key] - WINDOW_ORDER[b.key];
  pools.gemini.sort(byKey);
  pools.other.sort(byKey);
  return pools;
}

export function pickAgyPool(pools, nowSec) {
  const gemini = Array.isArray(pools?.gemini) ? pools.gemini : [];
  return gemini.some((w) => windowView(w, nowSec).used >= 100) ? "other" : "gemini";
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
    remainingColor: dim(barColor),
    overColor: over > 0 ? (over < 0.1 ? PALETTE.peach : PALETTE.red) : null,
  };
}
