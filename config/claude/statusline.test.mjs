// statusline.sh: herdr の中では、利用制限とコンテキストを JSON に書き出して、何も表示しない
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "statusline.sh");
const tmp = mkdtempSync(join(tmpdir(), "statusline-"));

const fixture = {
  session_id: "abc",
  cwd: "/tmp",
  model: { display_name: "Opus 5.5" },
  effort: { level: "high" },
  context_window: {
    context_window_size: 200000,
    current_usage: { input_tokens: 600, cache_creation_input_tokens: 1000, cache_read_input_tokens: 75000 },
  },
  rate_limits: {
    five_hour: { used_percentage: 95.2, resets_at: 1763410000 },
    seven_day: { used_percentage: 93.0, resets_at: 1763900000 },
  },
};

function run(input, id) {
  const env = { PATH: process.env.PATH, HOME: tmp, HERDR_APP_HOME: join(tmp, "app") };
  if (id !== undefined) env.HC_TERMINAL_ID = id;
  return spawnSync("bash", [script], { input: JSON.stringify(input), env, encoding: "utf8" });
}
const readJson = (rel) => JSON.parse(readFileSync(join(tmp, rel), "utf8"));
const listFiles = (rel) => {
  try {
    return readdirSync(join(tmp, rel));
  } catch {
    return [];
  }
};

test("herdr の中では書き出して、何も表示しない", () => {
  const r = run(fixture, "t1");
  assert.equal(r.stdout, "");
  const s = readJson("app/data/sessions/t1.json");
  assert.deepEqual([s.terminal, s.model, s.effort, s.context.used, s.context.size], ["t1", "Opus 5.5", "high", 76600, 200000]);
  const l = readJson("app/data/limits/claude-code.json");
  assert.deepEqual(
    l.windows.map((w) => [w.key, w.used_percentage, w.duration]),
    [
      ["5h", 95.2, 18000],
      ["7d", 93, 604800],
    ],
  );
});

test("リセット後に 5h の値が来なくても、5h を使用率 0 で残す", () => {
  run({ ...fixture, rate_limits: { seven_day: fixture.rate_limits.seven_day } }, "t5h");
  const l = readJson("app/data/limits/claude-code.json");
  assert.deepEqual(
    l.windows.map((w) => [w.key, w.used_percentage, w.resets_at, w.duration]),
    [
      ["5h", 0, null, 18000],
      ["7d", 93, 1763900000, 604800],
    ],
  );
});

test("止まったセッションの古い値で、新しい使用率を上書きしない", () => {
  const now = Math.floor(Date.now() / 1000);
  const limits = (h, d, dReset = now + 86400) => ({
    rate_limits: {
      five_hour: { used_percentage: h, resets_at: now + 3600 },
      seven_day: { used_percentage: d, resets_at: dReset },
    },
  });
  const windows = () => readJson("app/data/limits/claude-code.json").windows.map((w) => [w.key, w.used_percentage]);
  run({ ...fixture, ...limits(40, 80) }, "fresh");
  run({ ...fixture, ...limits(30, 78) }, "stale");
  assert.deepEqual(windows(), [
    ["5h", 40],
    ["7d", 80],
  ]);
  // 5h の値が無い古いセッションも、まだ続いている 5h を 0 にしない
  run({ ...fixture, rate_limits: { seven_day: { used_percentage: 78, resets_at: now + 86400 } } }, "stale");
  assert.deepEqual(windows(), [
    ["5h", 40],
    ["7d", 80],
  ]);
  // 次の窓に入れば、使用率が下がっても新しい値を使う
  run({ ...fixture, ...limits(45, 2, now + 86400 + 604800) }, "fresh");
  assert.deepEqual(windows(), [
    ["5h", 45],
    ["7d", 2],
  ]);
});

test("effort と current_usage がなければ null", () => {
  run({ ...fixture, effort: undefined, context_window: { context_window_size: 200000, current_usage: null } }, "t2");
  const s = readJson("app/data/sessions/t2.json");
  assert.equal(s.effort, null);
  assert.equal(s.context, null);
});

test("形に合わない HC_TERMINAL_ID では何も書かない", () => {
  // Review Focus 2
  for (const id of ["../x", "", "t 1", ".hidden"]) {
    const r = run(fixture, id);
    assert.equal(r.stdout, "");
  }
  assert.deepEqual(
    listFiles("app/data/sessions").filter((f) => !["t1.json", "t2.json", "t5h.json", "fresh.json", "stale.json"].includes(f)),
    [],
  );
  assert.deepEqual(listFiles("app/data"), ["limits", "sessions"]);
});

test("herdr の中 (agy): model.effort、context_window_size 0、quota を扱う", () => {
  const now = Math.floor(Date.now() / 1000);
  const hReset = new Date((now + 3600) * 1000).toISOString().replace(/\.\d+Z$/, "Z");
  const dReset = new Date((now + 86400) * 1000).toISOString().replace(/\.\d+Z$/, "Z");
  const agyFixture = {
    session_id: "agy-1",
    cwd: "/tmp",
    product: "antigravity",
    model: { id: "Gemini 4 Argon (Medium)", display_name: "Gemini 4 Argon (Medium)", effort: "medium" },
    context_window: {
      context_window_size: 1048576,
      current_usage: { input_tokens: 60000, cache_creation_input_tokens: 0, cache_read_input_tokens: 20000 },
    },
    quota: {
      "gemini-5h": { remaining_fraction: 0.84, reset_time: hReset, reset_in_seconds: 3600 },
      "gemini-weekly": { remaining_fraction: 0.95, reset_time: dReset, reset_in_seconds: 86400 },
      "3p-5h": { remaining_fraction: 1, reset_time: "1970-01-01T00:00:00Z", reset_in_seconds: 0 },
      "3p-weekly": { remaining_fraction: 1, reset_time: "1970-01-01T00:00:00Z", reset_in_seconds: 0 },
    },
  };
  const r = run(agyFixture, "t-agy");
  assert.equal(r.stdout, "");
  const s = readJson("app/data/sessions/t-agy.json");
  assert.deepEqual([s.model, s.effort, s.context.used, s.context.size], ["Gemini 4 Argon", "medium", 80000, 1048576]);

  const l = readJson("app/data/limits/agy.json");
  assert.equal(l.agent, "agy");
  assert.deepEqual(
    l.pools.gemini.map((w) => [w.key, Math.round(w.used_percentage), w.resets_at, w.duration]),
    [
      ["5h", 16, now + 3600, 18000],
      ["7d", 5, now + 86400, 604800],
    ],
  );
  assert.deepEqual(
    l.pools.other.map((w) => [w.key, Math.round(w.used_percentage), w.resets_at, w.duration]),
    [
      ["5h", 0, null, 18000],
      ["7d", 0, null, 604800],
    ],
  );

  // 止まったセッションの古い値で新しい使用率を上書きしない
  run(
    {
      ...agyFixture,
      quota: {
        ...agyFixture.quota,
        "gemini-5h": { remaining_fraction: 0.9, reset_time: hReset, reset_in_seconds: 3600 },
      },
    },
    "t-agy-stale",
  );
  assert.equal(Math.round(readJson("app/data/limits/agy.json").pools.gemini[0].used_percentage), 16);

  run({ ...agyFixture, context_window: { context_window_size: 0, current_usage: { input_tokens: 10 } } }, "t-agy-zero");
  assert.equal(readJson("app/data/sessions/t-agy-zero.json").context, null);

  // モデル切替直後に model.effort が欠けたり古い値と食い違っても、model から effort 表記を落とす
  run({ ...agyFixture, model: { id: "Gemini 4 Neon (High)", display_name: "Gemini 4 Neon (High)" } }, "t-agy-no-effort");
  const sNoEffort = readJson("app/data/sessions/t-agy-no-effort.json");
  assert.deepEqual([sNoEffort.model, sNoEffort.effort], ["Gemini 4 Neon", "high"]);

  run(
    { ...agyFixture, model: { id: "Gemini 4 Neon (High)", display_name: "Gemini 4 Neon (High)", effort: "medium" } },
    "t-agy-mismatch",
  );
  const sMismatch = readJson("app/data/sessions/t-agy-mismatch.json");
  assert.equal(sMismatch.model, "Gemini 4 Neon");

  // effort 以外の括弧表記 (1M context など) は残す
  run({ ...fixture, model: { display_name: "Opus 4.6 (1M context)" } }, "t-claude-ctx");
  assert.equal(readJson("app/data/sessions/t-claude-ctx.json").model, "Opus 4.6 (1M context)");
});

test("herdr の中 (agy): cycle_mode だけを右端に表示し、default (未設定) では出さない", () => {
  const base = { product: "antigravity", terminal_width: 20 };
  const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*m/g, "");
  assert.equal(run(base, "t-mode-default").stdout, "");

  const rAuto = run({ ...base, cycle_mode: "auto" }, "t-mode-auto");
  assert.equal(stripAnsi(rAuto.stdout), `${" ".repeat(16)}auto\n`);
  assert.match(rAuto.stdout, /\x1b\[38;2;238;212;159m/);

  const rPlan = run({ ...base, cycle_mode: "plan" }, "t-mode-plan");
  assert.equal(stripAnsi(rPlan.stdout), `${" ".repeat(16)}plan\n`);
  assert.match(rPlan.stdout, /\x1b\[38;2;138;173;244m/);

  const rAccept = run({ ...base, cycle_mode: "accept-edits" }, "t-mode-accept");
  assert.equal(stripAnsi(rAccept.stdout), `${" ".repeat(8)}accept-edits\n`);
  assert.match(rAccept.stdout, /\x1b\[38;2;166;218;149m/);
});

test("herdr の外では今までどおり表示する", () => {
  const r = run(fixture, undefined);
  assert.match(r.stdout, /Opus 5\.5/);
});

test("書きかけの一時ファイルを残さない", () => {
  assert.deepEqual(
    listFiles("app/data/sessions").filter((f) => f.startsWith(".")),
    [],
  );
  assert.deepEqual(
    listFiles("app/data/limits").filter((f) => f.startsWith(".")),
    [],
  );
});
