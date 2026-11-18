import { test } from "node:test";
import assert from "node:assert/strict";
import { nestSpaces, contextFor, assignNames, trackAgentTimes, agentTime, nextTick, buildStructure, buildGroups, agentOrder, collectSubagents, activityFor } from "./logic.js";

const sp = (id, tabs, extra = {}) => ({ id, name: id, folder: `/r/${id}`, status: null, tabs, ...extra });
const tab = (id, extra = {}) => ({ id, name: id, named: false, status: null, working_since: null, changed_at: null, ...extra });
const ag = (address, tabId, status = "idle") => ({ address, tab: tabId, space: "s1", space_name: "dotfiles", tab_name: tabId, status });

test("nestSpaces: worktree は元の space の下", () => {
  const spaces = [sp("wt", []), sp("main", []), sp("other", [])];
  const repos = { wt: { top: "/w/feat", common: "/r/main/.git" }, main: { top: "/r/main", common: "/r/main/.git" }, other: null };
  assert.deepEqual(nestSpaces(spaces, repos).map((n) => [n.space.id, n.depth]), [["main", 0], ["wt", 1], ["other", 0]]);
});
test("nestSpaces: 元の space がなければ depth 0 のまま", () => {
  const spaces = [sp("wt", [])];
  const repos = { wt: { top: "/w/feat", common: "/r/gone/.git" } };
  assert.deepEqual(nestSpaces(spaces, repos).map((n) => [n.space.id, n.depth]), [["wt", 0]]);
});
test("別のコンピューターの space と端末", () => { // Review Focus 6
  const spaces = [sp("main", []), sp("laptop/wt", [], { machine: "laptop" })];
  const repos = { main: { top: "/r/main", common: "/r/main/.git" }, "laptop/wt": { top: "/w/feat", common: "/r/main/.git" } };
  assert.deepEqual(nestSpaces(spaces, repos).map((n) => n.depth), [0, 0]);
  const sessions = { t1: { model: "Opus 5.5" } };
  assert.equal(contextFor("laptop/t1", sessions), null);
  assert.equal(contextFor("t1", sessions).model, "Opus 5.5");
  assert.equal(contextFor("t2", sessions), null);
});
test("assignNames: 生きている端末の名前は変わらず、空いた名前を前から使う", () => {
  const r = ["Mocha", "Latte"];
  assert.deepEqual(assignNames({ t1: "Latte" }, ["t1", "t2"], r), { t1: "Latte", t2: "Mocha" });
  assert.deepEqual(assignNames({ t1: "Mocha", t2: "Latte" }, ["t1", "t2", "t3"], r), { t1: "Mocha", t2: "Latte", t3: "Mocha 2" });
  assert.deepEqual(assignNames({ t1: "Mocha", t9: "Latte" }, ["t1"], r), { t1: "Mocha" }); // Review Focus 4
});
test("assignNames: 全部使われていたら番号付きの名前を名簿の順に", () => {
  const r = ["Mocha", "Latte"];
  const prev = { t1: "Mocha", t2: "Latte", t3: "Mocha 2" };
  assert.deepEqual(assignNames(prev, ["t1", "t2", "t3", "t4"], r).t4, "Latte 2");
});
test("trackAgentTimes と agentTime", () => {
  let recs = trackAgentTimes({}, [{ address: "t1", status: "working" }], 1000, { t1: { since: 0 } });
  assert.equal(agentTime(recs.t1, 61_000), "1m01s");
  recs = trackAgentTimes(recs, [{ address: "t1", status: "done" }], 192_000, {});
  assert.equal(agentTime(recs.t1, 999_999), "3m12s"); // かかった時間 = 192_000 - since (fallback の 0)
  recs = trackAgentTimes(recs, [{ address: "t1", status: "idle" }], 200_000, {});
  assert.equal(agentTime(recs.t1, 300_000), null);
  assert.deepEqual(trackAgentTimes(recs, [], 0, {}), {});
});
test("trackAgentTimes: 同じ状態なら since を変えず、blocked は経過を出し、working に戻ると workedMs を消す", () => {
  let recs = trackAgentTimes({}, [{ address: "t1", status: "blocked" }], 5000, { t1: { since: 2000 } });
  recs = trackAgentTimes(recs, [{ address: "t1", status: "blocked" }], 9000, {});
  assert.equal(recs.t1.since, 2000);
  assert.equal(agentTime(recs.t1, 12_000), "10s");
  recs = trackAgentTimes(recs, [{ address: "t1", status: "working" }], 13_000, {});
  assert.deepEqual(recs.t1, { status: "working", since: 13_000, workedMs: null });
  recs = trackAgentTimes(recs, [{ address: "t1", status: "done" }], 20_000, {});
  recs = trackAgentTimes(recs, [{ address: "t1", status: "working" }], 30_000, {});
  assert.equal(recs.t1.workedMs, null);
  // fallback がなければ now から始める。初めて見る done は時間を出さない
  recs = trackAgentTimes({}, [{ address: "t2", status: "done" }], 7000, {});
  assert.equal(recs.t2.since, 7000);
  assert.equal(agentTime(recs.t2, 8000), null);
  assert.equal(agentTime(undefined, 8000), null);
});
test("nextTick", () => {
  assert.equal(nextTick({ t1: { status: "idle", since: 0 } }, 5000), null);
  assert.equal(nextTick({ t1: { status: "working", since: 0 } }, 5_400), 1000);
  assert.equal(nextTick({ t1: { status: "working", since: 0 } }, 12 * 60_000 + 30_000), 30_000); // 分の表示になったら次の分まで
  assert.equal(nextTick({ t1: { status: "working", since: 0 }, t2: { status: "blocked", since: 0 } }, 12 * 60_000 + 30_000 - 0), 30_000);
  assert.equal(nextTick({ t1: { status: "working", since: 0 }, t2: { status: "blocked", since: 45_000 } }, 12 * 60_000 + 30_000), 15_000);
});
test("buildStructure: エージェントが 1 つのタブは畳む", () => {
  const nested = [{ space: sp("s1", [tab("a"), tab("b"), tab("c", { named: true, name: "logs" })]), depth: 0 }];
  const rows = buildStructure({ nested, agents: [ag("t1", "a", "working")], subagents: {}, names: { t1: "Mocha" }, collapsed: new Set() });
  assert.deepEqual(rows.map((r) => [r.kind, r.depth, r.label]), [["space", 0, "s1"], ["agent", 1, "Mocha"], ["tab", 1, null], ["tab", 1, "logs"]]);
  assert.equal(rows[0].status, "working");
  assert.deepEqual(rows.map((r) => r.key), ["space:s1", "agent:t1", "tab:b", "tab:c"]);
});
test("buildStructure: サブエージェントがいれば展開し、畳める", () => {
  const nested = [{ space: sp("s1", [tab("a")]), depth: 0 }];
  const base = { nested, agents: [ag("t1", "a", "working")], subagents: { t1: [{ id: "x", type: "Explore" }] }, names: { t1: "Mocha" } };
  assert.deepEqual(buildStructure({ ...base, collapsed: new Set() }).map((r) => r.kind), ["space", "tab", "agent", "sub"]);
  assert.deepEqual(buildStructure({ ...base, collapsed: new Set(["agent:t1"]) }).map((r) => r.kind), ["space", "tab", "agent"]);
  assert.deepEqual(buildStructure({ ...base, collapsed: new Set(["space:s1"]) }).map((r) => r.kind), ["space"]);
  const rows = buildStructure({ ...base, collapsed: new Set() });
  assert.equal(rows[2].hasChildren, true);
  assert.equal(rows[2].open, true);
  assert.equal(rows[3].key, "sub:t1:x");
  assert.equal(rows[3].label, "Explore");
});
test("buildStructure: エージェントが 2 つのタブは下に並べ、worktree は字下げ、名前がなければ tab_name", () => {
  const nested = [
    { space: sp("s1", [tab("a")]), depth: 0 },
    { space: sp("s2", [tab("z")]), depth: 1 },
  ];
  const agents = [ag("t1", "a", "idle"), ag("t2", "a", "blocked"), { ...ag("t3", "z", "done"), space: "s2" }];
  const rows = buildStructure({ nested, agents, subagents: {}, names: { t1: "Mocha" }, collapsed: new Set() });
  assert.deepEqual(rows.map((r) => [r.kind, r.depth, r.label]), [
    ["space", 0, "s1"], ["tab", 1, null], ["agent", 2, "Mocha"], ["agent", 2, "a"],
    ["space", 1, "s2"], ["agent", 2, "z"],
  ]);
  assert.equal(rows[0].status, "blocked");
  assert.equal(rows[1].status, "blocked");
  assert.equal(rows[4].status, "done");
});
test("buildGroups と agentOrder: 入力待ちが先、Idle は畳める", () => {
  const agents = [ag("t1", "a", "working"), ag("t2", "b", "blocked"), ag("t3", "c", "idle")];
  const rows = buildGroups({ agents, subagents: {}, names: { t1: "Mocha", t2: "Latte", t3: "Pecan" }, collapsed: new Set(["group:idle"]) });
  assert.deepEqual(rows.map((r) => r.key), ["group:blocked", "agent:t2", "group:working", "agent:t1", "group:idle"]);
  assert.equal(rows.at(-1).count, 1);
  assert.equal(rows.at(-1).open, false);
  assert.deepEqual(agentOrder(rows), ["t2", "t1"]);
});
test("buildGroups: サブエージェントは depth 2、エージェントのいないまとまりは出さない", () => {
  const agents = [ag("t1", "a", "working")];
  const rows = buildGroups({ agents, subagents: { t1: [{ id: "x", type: "Explore" }] }, names: {}, collapsed: new Set() });
  assert.deepEqual(rows.map((r) => [r.key, r.depth]), [["group:working", 0], ["agent:t1", 1], ["sub:t1:x", 2]]);
  assert.equal(rows[1].spaceName, "dotfiles");
  assert.equal(rows[0].open, true);
  assert.deepEqual(buildGroups({ agents: [], subagents: {}, names: {}, collapsed: new Set() }), []);
});

test("collectSubagents: 作業中の Claude Code のサブエージェントと hc run の端末", () => {
  const live = [ag("t1", "tab1", "working"), ag("t2", "tab2"), ag("laptop/t3", "tab3")];
  const activity = {
    t1: { subagents: [
      { id: "a1", type: "Explore", status: "working" },
      { id: "a2", type: "Plan", status: "done" },
    ] },
    t3: { subagents: [{ id: "x", type: "Explore", status: "working" }] }, // 別のコンピューターの t3 と結ばない
    gone: { subagents: [{ id: "y", type: "Explore", status: "working" }] }, // agents() にない端末
  };
  const terms = [
    { address: "t9", parent: "t1", state: "live", name: "lint", argv: ["npm"] },
    { address: "t10", parent: "t2", state: "live", argv: ["pytest", "-x"] },
    { address: "t11", parent: "t2", state: "finished", argv: ["old"] },
    { address: "t12", parent: "t5", state: "live", argv: ["x"] },
  ];
  assert.deepEqual(collectSubagents(live, activity, terms), {
    t1: [{ id: "a1", type: "Explore" }, { id: "t9", type: "lint" }],
    t2: [{ id: "t10", type: "pytest" }],
  });
  assert.deepEqual(collectSubagents(live, {}, []), {});
});
test("activityFor: agents() にない端末と別のコンピューターの端末は引かない", () => {
  const activity = { t1: { actions: [] }, t3: { actions: [] } };
  const live = [ag("t1", "a"), ag("laptop/t3", "b")];
  assert.deepEqual(activityFor("t1", activity, live), { actions: [] });
  assert.equal(activityFor("laptop/t3", activity, live), null);
  assert.equal(activityFor("t3", activity, live), null);
});
