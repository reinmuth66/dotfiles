// herdr-record.mjs: Claude Code の行動、編集、サブエージェントを herdr-app の data/ に書き出す
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { editContents, kindOf, record } from "./herdr-record.mjs";

const script = join(dirname(fileURLToPath(import.meta.url)), "herdr-record.mjs");
const tmp = mkdtempSync(join(tmpdir(), "herdr-record-"));
const app = join(tmp, "app");
const file = join(tmp, "target.txt");

const readJson = (rel) => JSON.parse(readFileSync(join(app, rel), "utf8"));
const env = (id = "t1") => ({ HC_TERMINAL_ID: id, HERDR_APP_HOME: app, HOME: tmp });
const post = (tool, input, response = {}) => ({
  hook_event_name: "PostToolUse",
  session_id: "abc",
  cwd: "/r",
  tool_name: tool,
  tool_input: input,
  tool_response: response,
});

function runProcess(event, e, path = script) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [path], { env: { PATH: process.env.PATH, ...e } });
    let stdout = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.on("close", (code) => resolve({ code, stdout }));
    child.stdin.end(typeof event === "string" ? event : JSON.stringify(event));
  });
}

test("Edit の前後と行動を書く", () => {
  writeFileSync(file, "after\n");
  record(post("Edit", { file_path: file, old_string: "before", new_string: "after" }, { originalFile: "before\n" }), env(), 1000);
  const a = readJson("data/activity/t1.json");
  assert.deepEqual([a.terminal, a.session_id, a.cwd], ["t1", "abc", "/r"]);
  assert.deepEqual([a.actions[0].tool, a.actions[0].kind, a.actions[0].path, a.actions[0].at], ["Edit", "edit", file, 1000]);
  const e = readJson(`data/edits/t1/${a.edits[0]}.json`);
  assert.deepEqual([e.seq, e.at, e.path], [a.edits[0], 1000, file]);
  assert.deepEqual([e.before, e.after, e.too_large], ["before\n", "after\n", false]);
});

test("Bash のコマンドは 1 行目を 120 文字まで", () => {
  record(post("Bash", { command: "nix flake check\necho done" }), env(), 2000);
  const a = readJson("data/activity/t1.json");
  assert.deepEqual([a.actions[0].command, a.actions[0].kind, a.actions[0].path], ["nix flake check", "bash", null]);
  record(post("Bash", { command: "y".repeat(300) }), env(), 2001);
  assert.equal(readJson("data/activity/t1.json").actions[0].command.length, 120);
  assert.equal(readJson("data/activity/t1.json").actions.length, 3);
});

test("行動は 20 件、編集は 10 件まで。外れた編集のファイルは消す", () => {
  for (let i = 0; i < 25; i++) record(post("Write", { file_path: file, content: `${i}` }, {}), env("t5"), i);
  const a = readJson("data/activity/t5.json");
  assert.equal(a.actions.length, 20);
  assert.equal(a.actions[0].at, 24);
  assert.equal(a.edits.length, 10);
  assert.deepEqual(a.edits, [25, 24, 23, 22, 21, 20, 19, 18, 17, 16]);
  assert.equal(readdirSync(join(app, "data/edits/t5")).length, 10);
  const e = readJson("data/edits/t5/25.json");
  assert.deepEqual([e.before, e.after], ["", "24"]);
});

test("大きな編集は中身を持たない", () => {
  record(post("Write", { file_path: file, content: "x".repeat(1024 * 1024) }, {}), env("t6"), 1);
  const e = readJson(`data/edits/t6/${readJson("data/activity/t6.json").edits[0]}.json`);
  assert.deepEqual([e.before, e.after, e.too_large], [null, null, true]);
});

test("エスケープで JSON が 900 KiB を超える編集も中身を持たない", () => {
  const content = '"\n'.repeat(300 * 1024); // 中身は 600 KiB、JSON では 1200 KiB を超える
  assert.ok(Buffer.byteLength(content) < 900 * 1024);
  record(post("Write", { file_path: file, content }, {}), env("t14"), 1);
  const a = readJson("data/activity/t14.json");
  const path = join(app, `data/edits/t14/${a.edits[0]}.json`);
  assert.ok(readFileSync(path).length < 900 * 1024);
  const e = readJson(`data/edits/t14/${a.edits[0]}.json`);
  assert.deepEqual([e.before, e.after, e.too_large, e.seq], [null, null, true, a.edits[0]]);
});

test("NotebookEdit は行動だけ記録する", () => {
  record(post("NotebookEdit", { notebook_path: "/r/a.ipynb", new_source: "x" }), env("t8"), 1);
  const a = readJson("data/activity/t8.json");
  assert.deepEqual([a.actions[0].kind, a.actions[0].path, a.edits], ["edit", "/r/a.ipynb", []]);
});

test("サブエージェントの開始と終了", () => {
  record({ hook_event_name: "SubagentStart", session_id: "abc", cwd: "/r", agent_id: "a1", agent_type: "Explore" }, env("t7"), 10);
  assert.equal(readJson("data/activity/t7.json").subagents[0].status, "working");
  record({ hook_event_name: "SubagentStop", session_id: "abc", cwd: "/r", agent_id: "a1", agent_type: "Explore" }, env("t7"), 20);
  assert.deepEqual(readJson("data/activity/t7.json").subagents[0], { id: "a1", type: "Explore", status: "done", started_at: 10, ended_at: 20 });
});

test("終わったサブエージェントは 10 件まで、動いているものは残す", () => {
  const ev = (name, id) => ({ hook_event_name: name, session_id: "abc", cwd: "/r", agent_id: id, agent_type: "Explore" });
  record(ev("SubagentStart", "w"), env("t10"), 0);
  for (let i = 0; i < 12; i++) {
    record(ev("SubagentStart", `d${i}`), env("t10"), i + 1);
    record(ev("SubagentStop", `d${i}`), env("t10"), i + 2);
  }
  const s = readJson("data/activity/t10.json").subagents;
  assert.equal(s.filter((x) => x.status === "done").length, 10);
  assert.deepEqual(
    s.filter((x) => x.status === "working").map((x) => x.id),
    ["w"],
  );
  assert.equal(s.some((x) => x.id === "d0" || x.id === "d1"), false);
});

test("SessionStart の clear で空にする", () => {
  record({ hook_event_name: "SessionStart", session_id: "new", cwd: "/r", source: "clear" }, env("t1"), 3000);
  const a = readJson("data/activity/t1.json");
  assert.deepEqual([a.actions, a.edits, a.subagents, a.session_id], [[], [], [], "new"]);
  assert.equal(existsSync(join(app, "data/edits/t1")), false);
});

test("SessionStart で、7 日より古い他の端末の activity、edits、sessions を消す", () => {
  const home = join(tmp, "prune");
  const d = join(home, "data");
  const e = { HC_TERMINAL_ID: "cur", HERDR_APP_HOME: home, HOME: tmp };
  const now = Date.now();
  const old = (now - 8 * 24 * 3600 * 1000) / 1000;
  const recent = (now - 6 * 24 * 3600 * 1000) / 1000;
  const put = (rel, age, dir = false) => {
    const p = join(d, rel);
    if (dir) {
      mkdirSync(p, { recursive: true });
      writeFileSync(join(p, "1.json"), "{}");
    } else {
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, "{}");
    }
    utimesSync(p, age, age);
  };
  for (const t of ["old", "new", "cur"]) {
    const age = t === "new" ? recent : old;
    put(`activity/${t}.json`, age);
    put(`sessions/${t}.json`, age);
    put(`edits/${t}`, age, true);
  }
  // data/ の外を指すリンクはたどらず消さない。ID の形でない名前、ロック中の端末も消さない
  const outside = join(tmp, "prune-outside");
  mkdirSync(outside, { recursive: true });
  writeFileSync(join(outside, "keep.json"), "{}");
  symlinkSync(outside, join(d, "edits/link"));
  put("sessions/.x.json", old);
  put("activity/locked.json", old);
  mkdirSync(join(d, "activity/.locked.lock"));

  record({ hook_event_name: "SessionStart", session_id: "s", cwd: "/r", source: "startup" }, e, now);
  const ls = (rel) => readdirSync(join(d, rel)).sort();
  assert.deepEqual(ls("activity"), [".locked.lock", "cur.json", "locked.json", "new.json"]);
  assert.deepEqual(ls("sessions"), [".x.json", "cur.json", "new.json"]);
  assert.deepEqual(ls("edits"), ["link", "new"]); // cur は SessionStart で空にした
  assert.equal(existsSync(join(outside, "keep.json")), true);
});

test("PostToolUse では古いファイルを消さない", () => {
  const home = join(tmp, "prune-post");
  const p = join(home, "data/sessions/old.json");
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, "{}");
  const old = (Date.now() - 8 * 24 * 3600 * 1000) / 1000;
  utimesSync(p, old, old);
  record(post("Read", { file_path: file }), { HC_TERMINAL_ID: "cur", HERDR_APP_HOME: home, HOME: tmp }, Date.now());
  assert.equal(existsSync(p), true);
});

test("SessionStart の resume では消さない", () => {
  record({ hook_event_name: "SessionStart", session_id: "abc", cwd: "/r", source: "resume" }, env("t5"), 3000);
  assert.equal(readJson("data/activity/t5.json").actions.length, 20);
  assert.equal(readdirSync(join(app, "data/edits/t5")).length, 10);
});

test("形に合わない HC_TERMINAL_ID では何も書かない", () => {
  for (const id of ["../x", "", "a/b", "-x", ".x"]) record(post("Read", { file_path: file }), env(id), 1);
  record(post("Read", { file_path: file }), { HERDR_APP_HOME: app, HOME: tmp }, 1);
  assert.equal(existsSync(join(app, "data/x.json")), false);
  assert.deepEqual(
    readdirSync(join(app, "data/activity")).filter((f) => !/^t\d+\.json$/.test(f)),
    [],
  );
});

test("HERDR_APP_HOME がなければ ~/.config/herdr-app に書く", () => {
  record(post("Read", { file_path: file }), { HC_TERMINAL_ID: "h1", HOME: tmp }, 1);
  assert.equal(existsSync(join(tmp, ".config/herdr-app/data/activity/h1.json")), true);
});

test("ロックが取れなければ何も書かない。60 秒より古いロックは消して取る", () => {
  const lock = join(app, "data/activity/.t11.lock");
  mkdirSync(lock, { recursive: true });
  const t0 = Date.now();
  record(post("Read", { file_path: file }), env("t11"), 1);
  assert.ok(Date.now() - t0 >= 1900);
  assert.equal(existsSync(join(app, "data/activity/t11.json")), false);
  const old = (Date.now() - 120_000) / 1000;
  utimesSync(lock, old, old);
  record(post("Read", { file_path: file }), env("t11"), 2);
  assert.equal(readJson("data/activity/t11.json").actions.length, 1);
  assert.equal(existsSync(lock), false);
});

test("kindOf と editContents", () => {
  assert.deepEqual(
    ["Edit", "MultiEdit", "NotebookEdit", "Write", "Read", "Grep", "Glob", "WebSearch", "WebFetch", "Bash", "Task", "mcp__x"].map(kindOf),
    ["edit", "edit", "edit", "write", "read", "search", "search", "web", "web", "bash", "other", "other"],
  );
  assert.equal(editContents(post("NotebookEdit", { notebook_path: "/r/a.ipynb" })), null);
  assert.equal(editContents(post("Read", { file_path: file })), null);
  assert.deepEqual(editContents(post("Write", { file_path: "/r/a", content: "b" }, { originalFile: "a" })), { path: "/r/a", before: "a", after: "b" });
});

test("同時に 10 個走っても、行動が 10 件残り、JSON が壊れない", async () => {
  const rs = await Promise.all(Array.from({ length: 10 }, (_, i) => runProcess(post("Read", { file_path: `${file}${i}` }), env("t9"))));
  for (const r of rs) assert.deepEqual([r.code, r.stdout], [0, ""]);
  assert.equal(readJson("data/activity/t9.json").actions.length, 10);
});

test("古いロックを 10 個が同時に見ても、行動が 10 件残る", async () => {
  const lock = join(app, "data/activity/.t15.lock");
  mkdirSync(lock, { recursive: true });
  const old = (Date.now() - 120_000) / 1000;
  utimesSync(lock, old, old);
  const rs = await Promise.all(Array.from({ length: 10 }, (_, i) => runProcess(post("Read", { file_path: `${file}${i}` }), env("t15"))));
  for (const r of rs) assert.deepEqual([r.code, r.stdout], [0, ""]);
  assert.equal(readJson("data/activity/t15.json").actions.length, 10);
  assert.deepEqual(
    readdirSync(join(app, "data/activity")).filter((f) => f.includes("t15") && f !== "t15.json"),
    [],
  );
});

test("直接実行: 壊れた入力でも標準出力に何も出さず 0 で終わる", async () => {
  for (const input of ["not json", "", "null", "[]"]) {
    assert.deepEqual(await runProcess(input, env("t12")), { code: 0, stdout: "" });
  }
  assert.deepEqual(await runProcess(post("Read", { file_path: file }), { HC_TERMINAL_ID: "t12", HERDR_APP_HOME: "/dev/null/x", HOME: tmp }), {
    code: 0,
    stdout: "",
  });
});

test("直接実行: シンボリックリンク越しでも動く", async () => {
  const link = join(tmp, "link-herdr-record.mjs");
  symlinkSync(script, link);
  assert.deepEqual(await runProcess(post("Read", { file_path: file }), env("t13"), link), { code: 0, stdout: "" });
  assert.equal(readJson("data/activity/t13.json").actions.length, 1);
});
