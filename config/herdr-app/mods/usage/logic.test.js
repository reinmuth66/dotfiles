import { test } from "node:test";
import assert from "node:assert/strict";
import { PALETTE } from "./ui.js";
import { dim, parseAgyQuota, pickAgyPool, windowView } from "./logic.js";

const QUOTA = [
  "Gemini Models\tWeekly Limit Remaining\t91%\t2026-12-02T02:45:28Z",
  "Gemini Models\tFive Hour Limit Remaining\t100%\t2026-11-26T09:55:21Z",
  "Claude and GPT models\tWeekly Limit Remaining\t100%\t1970-01-01T00:00:00Z",
  "Claude and GPT models\tFive Hour Limit Remaining\t100%\t1970-01-01T00:00:00Z",
].join("\n");

test("parseAgyQuota: 残りを使用率に直し、枠ごとに分ける", () => {
  const p = parseAgyQuota(QUOTA);
  assert.deepEqual(p.gemini, [
    { key: "5h", used_percentage: 0, resets_at: Date.parse("2026-11-26T09:55:21Z") / 1000, duration: 18000 },
    { key: "7d", used_percentage: 9, resets_at: Date.parse("2026-12-02T02:45:28Z") / 1000, duration: 604800 },
  ]);
  // 1970 年はまだ使っていない窓
  assert.deepEqual(
    p.other.map((w) => [w.key, w.used_percentage, w.resets_at]),
    [
      ["5h", 0, null],
      ["7d", 0, null],
    ],
  );
});
test("parseAgyQuota: 知らない行と壊れた行は飛ばす", () => {
  const p = parseAgyQuota(`Fetching...\nGemini Models\tWeekly Limit Remaining\tx%\t-\n${QUOTA.split("\n")[1]}`);
  assert.deepEqual(
    p.gemini.map((w) => w.key),
    ["5h"],
  );
  assert.deepEqual(p.other, []);
});
test("pickAgyPool: Gemini が尽きたら other、リセットを過ぎたら gemini に戻る", () => {
  const now = 1_000_000;
  const g = (h, d, hReset = now + 3600) => [
    { key: "5h", used_percentage: h, resets_at: hReset, duration: 18000 },
    { key: "7d", used_percentage: d, resets_at: now + 86400, duration: 604800 },
  ];
  assert.equal(pickAgyPool({ gemini: g(40, 80), other: [] }, now), "gemini");
  assert.equal(pickAgyPool({ gemini: g(100, 80), other: [] }, now), "other");
  assert.equal(pickAgyPool({ gemini: g(40, 100), other: [] }, now), "other");
  assert.equal(pickAgyPool({ gemini: g(100, 80, now - 1), other: [] }, now), "gemini");
  assert.equal(pickAgyPool({ gemini: [], other: [] }, now), "gemini");
});
test("windowView: 超過と色", () => {
  const w = { key: "5h", used_percentage: 95.2, resets_at: 10_000 + 2400, duration: 18000 };
  const v = windowView(w, 10_000);
  assert.equal(v.remaining, "40m");
  assert.ok(Math.abs(v.elapsed - (1 - 2400 / 18000)) < 1e-9);
  assert.equal(v.barColor, PALETTE.sky); // 帯は 90% 以上でも区切りの色
  assert.equal(v.remainingColor, dim(PALETTE.sky));
  assert.equal(v.overColor, PALETTE.peach); // 95.2 - 86.7 = 8.5 ポイント
  assert.equal(windowView({ ...w, key: "7d", used_percentage: 50, duration: 604800, resets_at: 10_000 + 3 * 86400 + 4 * 3600 }, 10_000).remaining, "3d04h");
});
test("windowView: リセットの時刻を過ぎたら次の窓を推定する", () => {
  const w = { key: "5h", used_percentage: 95, resets_at: 100, duration: 18000 };
  const v = windowView(w, 200);
  assert.equal(v.used, 0);
  assert.equal(v.over, 0);
  assert.equal(v.overColor, null);
  assert.equal(v.remaining, "4h58m"); // 残り 17900 秒
  assert.ok(Math.abs(v.elapsed - 100 / 18000) < 1e-9);
  assert.equal(windowView(w, 100).remaining, "5h00m"); // ちょうどの時刻
  assert.equal(windowView(w, 100 + 3 * 18000 + 60).remaining, "4h59m"); // 窓を 3 回以上進める
  assert.equal("reset" in v, false);
});
test("windowView: 区切りごとの色、超過なし、赤の超過、h の形", () => {
  const base = { used_percentage: 10, resets_at: 10_000 + 2 * 3600 + 5 * 60, duration: 18000 };
  const v = windowView({ ...base, key: "5h" }, 10_000);
  assert.equal(v.remaining, "2h05m");
  assert.equal(v.over, 0);
  assert.equal(v.overColor, null);
  assert.equal(v.barColor, PALETTE.sky);
  assert.equal(windowView({ ...base, key: "7d" }, 10_000).barColor, PALETTE.mauve);
  assert.equal(windowView({ ...base, key: "1m" }, 10_000).barColor, PALETTE.sky);
  const red = windowView({ ...base, key: "7d", used_percentage: 80 }, 10_000); // 経過 約 58%
  assert.equal(red.overColor, PALETTE.red);
  assert.ok(red.over > 0.1);
});
test("windowView: 経過は 0 から 1、値がないときは null", () => {
  assert.equal(windowView({ key: "5h", used_percentage: 5, resets_at: 10_000 + 99_999, duration: 18000 }, 10_000).elapsed, 0);
  const none = windowView({ key: "5h", used_percentage: 5, resets_at: null, duration: 18000 }, 10_000);
  assert.equal(none.elapsed, null);
  assert.equal(none.remaining, null);
  assert.equal(none.over, 0);
});
