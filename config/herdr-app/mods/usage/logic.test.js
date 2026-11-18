import { test } from "node:test";
import assert from "node:assert/strict";
import { PALETTE } from "./ui.js";
import { nextMode, visibleAgents, windowView } from "./logic.js";

test("nextMode", () => {
  assert.equal(nextMode("active"), "all");
  assert.equal(nextMode("all"), "pinned");
  assert.equal(nextMode("pinned"), "active");
});
test("visibleAgents", () => {
  const files = { "claude-code": {}, codex: {} };
  assert.deepEqual(visibleAgents({ mode: "all", pinned: null, files, activeApp: null, lastApp: null }), ["claude-code", "codex"]);
  assert.deepEqual(visibleAgents({ mode: "active", pinned: null, files, activeApp: null, lastApp: "codex" }), ["codex"]);
  assert.deepEqual(visibleAgents({ mode: "pinned", pinned: "pi", files, activeApp: null, lastApp: null }), []);
});
test("visibleAgents: アクティブは今のタブが先、ファイルのない種類は出さない", () => {
  const files = { codex: {}, "claude-code": {} };
  assert.deepEqual(visibleAgents({ mode: "all", pinned: null, files, activeApp: null, lastApp: null }), ["claude-code", "codex"]);
  assert.deepEqual(visibleAgents({ mode: "active", pinned: null, files, activeApp: "claude-code", lastApp: "codex" }), ["claude-code"]);
  assert.deepEqual(visibleAgents({ mode: "active", pinned: null, files, activeApp: "pi", lastApp: "codex" }), []);
  assert.deepEqual(visibleAgents({ mode: "pinned", pinned: "codex", files, activeApp: "claude-code", lastApp: null }), ["codex"]);
  assert.deepEqual(visibleAgents({ mode: "all", pinned: null, files: {}, activeApp: null, lastApp: null }), []);
});
test("windowView: 超過と色", () => {
  const w = { key: "5h", used_percentage: 95.2, resets_at: 10_000 + 2400, duration: 18000 };
  const v = windowView(w, 10_000);
  assert.equal(v.remaining, "40m");
  assert.ok(Math.abs(v.elapsed - (1 - 2400 / 18000)) < 1e-9);
  assert.equal(v.usedColor, PALETTE.red);
  assert.equal(v.barColor, PALETTE.sky); // 帯は 90% 以上でも区切りの色
  assert.equal(v.overColor, PALETTE.peach); // 95.2 - 86.7 = 8.5 ポイント
  assert.equal(windowView({ ...w, key: "7d", used_percentage: 50, duration: 604800, resets_at: 10_000 + 3 * 86400 + 4 * 3600 }, 10_000).remaining, "3d04h");
});
test("windowView: リセットの時刻を過ぎた値", () => { // Review Focus 4
  const v = windowView({ key: "5h", used_percentage: 95, resets_at: 100, duration: 18000 }, 200);
  assert.equal(v.reset, true);
  assert.equal(v.remaining, null);
});
test("windowView: 区切りごとの色、超過なし、赤の超過、h の形", () => {
  const base = { used_percentage: 10, resets_at: 10_000 + 2 * 3600 + 5 * 60, duration: 18000 };
  const v = windowView({ ...base, key: "5h" }, 10_000);
  assert.equal(v.remaining, "2h05m");
  assert.equal(v.usedColor, PALETTE.sky);
  assert.equal(v.over, 0);
  assert.equal(v.overColor, null);
  assert.equal(v.reset, false);
  assert.equal(v.barColor, PALETTE.sky);
  assert.equal(windowView({ ...base, key: "7d" }, 10_000).usedColor, PALETTE.mauve);
  assert.equal(windowView({ ...base, key: "7d" }, 10_000).barColor, PALETTE.mauve);
  assert.equal(windowView({ ...base, key: "1m" }, 10_000).usedColor, PALETTE.sky);
  const red = windowView({ ...base, key: "7d", used_percentage: 80 }, 10_000); // 経過 約 58%
  assert.equal(red.usedColor, PALETTE.mauve);
  assert.equal(red.overColor, PALETTE.red);
  assert.ok(red.over > 0.1);
});
test("windowView: 経過は 0 から 1、値がないときは null", () => {
  assert.equal(windowView({ key: "5h", used_percentage: 5, resets_at: 10_000 + 99_999, duration: 18000 }, 10_000).elapsed, 0);
  const none = windowView({ key: "5h", used_percentage: 5, resets_at: null, duration: 18000 }, 10_000);
  assert.equal(none.elapsed, null);
  assert.equal(none.remaining, null);
  assert.equal(none.reset, false);
  assert.equal(none.over, 0);
});
