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
    listFiles("app/data/sessions").filter((f) => !["t1.json", "t2.json", "t5h.json"].includes(f)),
    [],
  );
  assert.deepEqual(listFiles("app/data"), ["limits", "sessions"]);
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
