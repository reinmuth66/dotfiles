import { test } from "node:test";
import assert from "node:assert/strict";
import { REFS_ARGS, failureReason, filterBranches, parseRefs, switchPlan } from "./branches.js";

const out = [
  "refs/heads/feature/a\0feature/a\0",
  "refs/heads/main\0main\0/r",
  "refs/heads/wt\0wt\0/w/wt",
  "refs/remotes/origin/HEAD\0origin\0",
  "refs/remotes/origin/main\0origin/main\0",
  "refs/remotes/origin/fix 日本語\0origin/fix 日本語\0",
  "",
].join("\n");

test("REFS_ARGS", () => {
  assert.deepEqual(REFS_ARGS, ["for-each-ref", "--sort=-committerdate", "--format=%(refname)%00%(refname:short)%00%(worktreepath)", "refs/heads", "refs/remotes"]);
});
test("parseRefs: 今のブランチが先、手元、リモートにだけあるもの", () => {
  const b = parseRefs(out, "main", "/r");
  assert.deepEqual(b.map((x) => [x.name, x.kind, x.current]), [["main", "local", true], ["feature/a", "local", false], ["wt", "local", false], ["fix 日本語", "remote", false]]);
  assert.equal(b.find((x) => x.name === "wt").worktree, "/w/wt");
  assert.equal(b.find((x) => x.name === "main").worktree, null); // 自分の場所 (root) は worktree として扱わない
  assert.equal(b.at(-1).remote, "origin");
  assert.equal(b[0].remote, null);
});
test("filterBranches", () => {
  const b = parseRefs(out, "main", "/r");
  assert.deepEqual(filterBranches(b, "FEA a").map((x) => x.name), ["feature/a"]);
  assert.equal(filterBranches(b, "").length, 4);
});
test("switchPlan", () => {
  const b = Object.fromEntries(parseRefs(out, "main", "/r").map((x) => [x.name, x]));
  const base = { agents: [], root: "/r", spaces: [{ id: "s2", folder: "/w/wt" }] };
  assert.deepEqual(switchPlan({ ...base, branch: b.main }), { action: "none" });
  assert.deepEqual(switchPlan({ ...base, branch: b["feature/a"] }), { action: "git", args: ["switch", "feature/a"] });
  assert.deepEqual(switchPlan({ ...base, branch: b["fix 日本語"] }), { action: "git", args: ["switch", "--track", "origin/fix 日本語"] });
  assert.deepEqual(switchPlan({ ...base, branch: b.wt }), { action: "space", id: "s2" });
  assert.deepEqual(switchPlan({ ...base, spaces: [], branch: b.wt }), { action: "refuse", reason: "wt の worktree で使われています" });
  const agents = [{ name: "Latte", status: "idle", cwd: "/r" }, { name: "Mocha", status: "working", cwd: "/r/modules" }, { name: "Pecan", status: "working", cwd: "/rr" }];
  assert.deepEqual(switchPlan({ ...base, agents, branch: b["feature/a"] }), { action: "refuse", reason: "Mocha が作業中です" });
  assert.deepEqual(switchPlan({ ...base, agents: [{ name: "Latte", status: "blocked", cwd: "/r" }], branch: b["feature/a"] }), { action: "refuse", reason: "Latte が入力待ちです" });
  assert.deepEqual(switchPlan({ ...base, agents: [{ name: "Pecan", status: "working", cwd: "/rr" }, { name: "X", status: "working", cwd: null }], branch: b["feature/a"] }), { action: "git", args: ["switch", "feature/a"] });
});
test("switchPlan: - で始まる手元のブランチは git の引数にしない", () => {
  const branch = { name: "--orphan=x", kind: "local", remote: null, current: false, worktree: null };
  assert.deepEqual(switchPlan({ branch, agents: [], root: "/r", spaces: [] }), { action: "refuse", reason: "--orphan=x は切り替えられません" });
  const remote = { name: "-x", kind: "remote", remote: "origin", current: false, worktree: null };
  assert.deepEqual(switchPlan({ branch: remote, agents: [], root: "/r", spaces: [] }), { action: "git", args: ["switch", "--track", "origin/-x"] });
});
test("failureReason", () => {
  const stderr = "error: Your local changes to the following files would be overwritten by checkout:\n\ta.nix\nAborting\n";
  assert.equal(failureReason(stderr), "Your local changes to the following files would be overwritten by checkout:");
  assert.equal(failureReason("fatal: invalid reference: x\n"), "fatal: invalid reference: x");
  assert.equal(failureReason(""), "切り替えられませんでした");
});
