import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  AGY_RULES,
  DEFAULT_MODEL,
  buildArgv,
  buildPrompt,
  formatReturn,
  gitHooksEnv,
  isAllowedDir,
  modelFrom,
  outsideWrites,
  parseDenied,
  parseResult,
  parseWorktrees,
  refsChanged,
  refsSnapshot,
  transcriptPath,
  workDirFrom,
} from "./logic.mjs";

const fx = (name) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

test("workDirFrom: 指示の行を取り、なければ cwd", () => {
  assert.equal(workDirFrom("計画: x\n作業ディレクトリ: /r/wt  \n", "/r"), "/r/wt");
  assert.equal(workDirFrom("なし", "/r"), "/r");
});
test("isAllowedDir: cwd の中と worktree の中だけ (Review Focus 4)", () => {
  const wts = ["/r", "/r-wt/feat"];
  assert.equal(isAllowedDir("/r", "/r", wts), true);
  assert.equal(isAllowedDir("/r/sub", "/r", wts), true);
  assert.equal(isAllowedDir("/r-wt/feat/a", "/r", wts), true);
  assert.equal(isAllowedDir("/r-evil", "/r", wts), false);
  assert.equal(isAllowedDir("/r/../etc", "/r", wts), false);
  assert.equal(isAllowedDir("/r-wt", "/r", wts), false);
});
test("parseWorktrees: porcelain の worktree の行", () => {
  assert.deepEqual(parseWorktrees("worktree /r\nHEAD abc\nbranch refs/heads/main\n\nworktree /r-wt/feat\nHEAD def\n"), ["/r", "/r-wt/feat"]);
});
test("modelFrom: 指示の行を取り、なければ hydrogen の high、不正なら error", () => {
  assert.deepEqual(modelFrom("作業ディレクトリ: /r\nモデル: gemini-3.8-flash-high \n"), { model: "gemini-3.8-flash-high" });
  assert.deepEqual(modelFrom("作業ディレクトリ: /r"), { model: "gemini-4-hydrogen-high" });
  assert.equal(DEFAULT_MODEL, "gemini-4-hydrogen-high");
  assert.ok("error" in modelFrom("モデル: x; rm -rf /"));
  assert.ok("error" in modelFrom("モデル: Gemini 4"));
});
test("buildArgv: auto でモデルを明示し、プロンプトは --print= の 1 つの引数", () => {
  const argv = buildArgv("a --output-format b", "/s.json", "gemini-4-hydrogen-high");
  assert.equal(argv.at(-1), "--print=a --output-format b");
  assert.deepEqual(argv.slice(0, 9), ["agy", "--output-format", "json", "--model", "gemini-4-hydrogen-high", "--settings", "/s.json", "--print-timeout", "25m"]);
  assert.ok(!argv.includes("--mode"));
});
test("gitHooksEnv: core.hooksPath を環境で向ける", () => {
  assert.deepEqual(gitHooksEnv("/m/git-hooks"), { GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "core.hooksPath", GIT_CONFIG_VALUE_0: "/m/git-hooks" });
});
test("refsChanged: 増えた、消えた、変わった ref (利用者の決定)", () => {
  const before = refsSnapshot("aaa\n", "refs/heads/main aaa\nrefs/tags/v1 ttt\n");
  assert.deepEqual(refsChanged(before, before), []);
  const after = refsSnapshot("bbb\n", "refs/heads/main bbb\nrefs/heads/x ccc\n");
  assert.deepEqual(refsChanged(before, after).sort(), ["HEAD: aaa -> bbb", "refs/heads/main: aaa -> bbb", "refs/heads/x: - -> ccc", "refs/tags/v1: ttt -> -"]);
});
test("outsideWrites: transcript の書き込みのうち作業ディレクトリの外", () => {
  const line = (name, args) => JSON.stringify({ step_index: 1, tool_calls: [{ name, args }] });
  const t = [
    line("write_file", { Path: JSON.stringify("/r/a.txt"), Content: "\"x\"" }),
    line("write_file", { Path: JSON.stringify("/tmp/outside.txt"), Content: "\"x\"" }),
    line("read_file", { Path: JSON.stringify("/etc/hosts") }),
    line("replace_file_content", { TargetFile: "/r-evil/b" }),
    "not json",
    line("write_file", { Path: JSON.stringify("/tmp/outside.txt") }),
  ].join("\n");
  assert.deepEqual(outsideWrites(t, "/r"), ["/tmp/outside.txt", "/r-evil/b"]);
  assert.deepEqual(outsideWrites("", "/r"), []);
});
test("buildPrompt: 規則を最後に足し、commit の禁止と Status の行を含む (Review Focus 2)", () => {
  const p = buildPrompt("やること");
  assert.ok(p.startsWith("やること") && p.endsWith(AGY_RULES));
  assert.match(AGY_RULES, /commit/);
  assert.match(AGY_RULES, /Status: DONE \| DONE_WITH_CONCERNS \| BLOCKED \| NEEDS_CONTEXT/);
  assert.match(AGY_RULES, /作業ディレクトリの外/);
});
test("parseDenied: deny に当たったものと、聞けずに拒まれたもの (Review Focus 3)", () => {
  const d = parseDenied(JSON.parse(fx("denied.json")), fx("denied.stderr"));
  assert.ok(d.includes("git add hello.txt"));
  assert.ok(d.some((c) => c.startsWith("git commit")));
  assert.equal(new Set(d).size, d.length);
  const s = parseDenied(JSON.parse(fx("soft-denied.json")), fx("soft-denied.stderr"));
  assert.ok(s.includes("command: Bash"));
  assert.ok(parseDenied(null, "jetski: no output produced — x").some((c) => c.startsWith("stderr の知らせ: jetski")));
  assert.deepEqual(parseDenied({ response: "ok", denied_actions: [] }, ""), []);
  assert.deepEqual(parseDenied(null, ""), []);
});
test("parseResult: fixtures の各種類", () => {
  const ok = parseResult(fx("ok.json"), fx("ok.stderr"), 0, null);
  assert.equal(ok.status, "ok");
  assert.equal(ok.digest, JSON.parse(fx("ok.json")).response);
  assert.equal(ok.conversationId, "5b1aa3b1-6c0c-4faa-a479-35529faa3d8c");
  assert.deepEqual(ok.tokens, { input: 42934, output: 3983 });
  assert.deepEqual(ok.refsChanged, []);
  assert.deepEqual(ok.outsideWrites, []);
  assert.deepEqual(ok.denied, []);
  const den = parseResult(fx("denied.json"), fx("denied.stderr"), 0, null);
  assert.equal(den.status, "ok");
  assert.ok(den.denied.length > 0);
  const soft = parseResult(fx("soft-denied.json"), fx("soft-denied.stderr"), 0, null);
  assert.equal(soft.status, "ok");
  assert.ok(soft.denied.length > 0);
  assert.equal(parseResult(fx("auth.json"), "", 1, null).status, "auth");
  const to = parseResult(fx("timeout.json"), fx("timeout.stderr"), 3, null);
  assert.equal(to.status, "timeout");
  assert.equal(to.conversationId, "f73768ca-d6b9-4083-95f9-45a21ddf0d28");
});
test("parseResult: JSON でない、空、シグナル (Review Focus 5)", () => {
  assert.equal(parseResult("panic: x", "trace", 2, null).status, "invalid-output");
  assert.match(parseResult("panic: x", "trace", 2, null).detail, /trace/);
  assert.equal(parseResult("", "", 0, null).status, "empty");
  assert.equal(parseResult("", "", null, "SIGTERM").status, "killed");
});
const R = (o) => ({ status: "ok", digest: "", conversationId: null, tokens: null, denied: [], refsChanged: [], outsideWrites: [], detail: "", ...o });
test("transcriptPath", () => {
  assert.equal(transcriptPath("/h", "c1"), "/h/.gemini/antigravity-cli/brain/c1/.system_generated/logs/transcript.jsonl");
});
test("formatReturn: 形と切り詰め", () => {
  const out = formatReturn(R({ digest: "x".repeat(9000), conversationId: "c1", tokens: { input: 10, output: 2 } }), "/h");
  assert.match(out, /^===DIGEST===\n/);
  assert.match(out, /切り詰めた/);
  assert.match(out, /status: ok\nconversation: c1\ntranscript: \/h\/\.gemini\/antigravity-cli\/brain\/c1\/\.system_generated\/logs\/transcript\.jsonl\ngemini_tokens: 10 \/ 2\ndenied: -\nrefs_changed: -\noutside_writes: -\nverify: git status と git diff を確かめ、完了条件のテストを走らせ、計画書の commit を行う/);
  assert.match(formatReturn(R({ digest: "d", conversationId: "c", denied: ["git commit -m x", "npm test"] }), "/h"), /denied: git commit -m x \/ npm test/);
});
test("formatReturn: refs や外への書き込みがあれば、META の前に警告を書く (利用者の決定)", () => {
  const out = formatReturn(R({ digest: "d", refsChanged: ["refs/heads/main: a -> b"], outsideWrites: ["/tmp/x"] }), "/h");
  assert.match(out, /refs_changed: refs\/heads\/main: a -> b/);
  assert.match(out, /outside_writes: \/tmp\/x/);
  assert.match(out, /警告: agy が git の ref を変えた[\s\S]*===META===/);
  assert.match(out, /警告: agy が作業ディレクトリの外に書いた[\s\S]*===META===/);
});
test("formatReturn: 失敗では git status を促し、認証ならログインを促す (Review Focus 5)", () => {
  const auth = formatReturn(R({ status: "auth" }), "/h");
  assert.match(auth, /agy を対話で起動してログイン/);
  assert.match(auth, /git status/);
  assert.match(formatReturn(R({ status: "spawn-failed", detail: "ENOENT" }), "/h"), /ENOENT/);
  const bad = formatReturn(R({ status: "bad-model", detail: "モデルの指定が不正: x" }), "/h");
  assert.match(bad, /status: bad-model/);
  assert.match(bad, /モデルの指定が不正: x/);
});
