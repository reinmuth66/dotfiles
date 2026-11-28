import { test } from "node:test";
import assert from "node:assert/strict";
import { nestSpaces, contextFor, trackAgentTimes, agentTime, nextTick, buildStructure, buildGroups, isFocusRow, agentOrder, collectSubagents, activityFor, SUBAGENT_STALE_MS, stepTab, stepSpace, stepAgent, stepGroup, moveTarget, closeKey, openKey, focusContainers, effectiveCollapsed, pruneHeld, highlightKey } from "./logic.js";

const sp = (id, tabs, extra = {}) => ({ id, name: id, folder: `/r/${id}`, status: null, tabs, ...extra });
const tab = (id, extra = {}) => ({ id, name: id, named: false, status: null, working_since: null, changed_at: null, ...extra });
const ag = (address, tabId, status = "idle", extra = {}) => ({ address, tab: tabId, space: "s1", space_name: "dotfiles", tab_name: tabId, status, program: { key: "claude", name: "Claude Code" }, ...extra });

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
test("trackAgentTimes と agentTime", () => {
  let recs = trackAgentTimes({}, [{ address: "t1", status: "working" }], 1000, { t1: { since: 0 } });
  assert.equal(agentTime(recs.t1, 61_000), "1m");
  recs = trackAgentTimes(recs, [{ address: "t1", status: "done" }], 192_000, {});
  assert.equal(agentTime(recs.t1, 999_999), "3m"); // かかった時間 = 192_000 - since (fallback の 0)
  recs = trackAgentTimes(recs, [{ address: "t1", status: "idle" }], 200_000, {});
  assert.equal(agentTime(recs.t1, 300_000), null);
  assert.deepEqual(trackAgentTimes(recs, [], 0, {}), {});
});
test("trackAgentTimes: 同じ状態なら since を変えず、blocked は経過を出し、working に戻ると workedMs を消す", () => {
  let recs = trackAgentTimes({}, [{ address: "t1", status: "blocked" }], 5000, { t1: { since: 2000 } });
  recs = trackAgentTimes(recs, [{ address: "t1", status: "blocked" }], 9000, {});
  assert.equal(recs.t1.since, 2000);
  assert.equal(agentTime(recs.t1, 12_000), "0m");
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
  assert.equal(nextTick({ t1: { status: "working", since: 0 } }, 5_400), 54_600); // 1 分未満でも次の分まで
  assert.equal(nextTick({ t1: { status: "working", since: 0 } }, 12 * 60_000 + 30_000), 30_000); // 分の表示になったら次の分まで
  assert.equal(nextTick({ t1: { status: "working", since: 0 }, t2: { status: "blocked", since: 0 } }, 12 * 60_000 + 30_000 - 0), 30_000);
  assert.equal(nextTick({ t1: { status: "working", since: 0 }, t2: { status: "blocked", since: 45_000 } }, 12 * 60_000 + 30_000), 15_000);
});
test("buildStructure: エージェントが 1 つのタブはエージェントの行、space は畳まず状態を出さない", () => {
  const nested = [{ space: sp("s1", [tab("a"), tab("b"), tab("c", { named: true, name: "logs" })]), depth: 0 }];
  const rows = buildStructure({ nested, agents: [ag("t1", "a", "working")], subagents: {}, sessions: { t1: { model: "Opus 5.5" } }, collapsed: new Set(["space:s1"]) });
  assert.deepEqual(rows.map((r) => [r.kind, r.depth, r.label]), [["space", 0, "s1"], ["agent", 1, "Opus 5.5"], ["tab", 1, null], ["tab", 1, "logs"]]);
  assert.equal(rows[0].status, null);
  assert.equal(rows[1].status, "working");
  assert.equal(rows[1].program.key, "claude");
  assert.deepEqual(rows.map((r) => r.key), ["space:s1", "agent:t1", "tab:b", "tab:c"]);
});
test("buildStructure: エージェントの行はサブエージェントを下に並べ、畳める", () => {
  const nested = [{ space: sp("s1", [tab("a")]), depth: 0 }];
  const base = { nested, agents: [ag("t1", "a", "working")], subagents: { t1: [{ id: "x", type: "Explore" }] }, sessions: { t1: { model: "Opus 5.5" } } };
  assert.deepEqual(
    buildStructure({ ...base, collapsed: new Set() }).map((r) => [r.kind, r.depth]),
    [["space", 0], ["agent", 1], ["sub", 2]],
  );
  assert.deepEqual(buildStructure({ ...base, collapsed: new Set(["agent:t1"]) }).map((r) => r.kind), ["space", "agent"]);
  const rows = buildStructure({ ...base, collapsed: new Set() });
  assert.equal(rows[1].hasChildren, true);
  assert.equal(rows[1].open, true);
  assert.equal(rows[2].key, "sub:t1:x");
  assert.equal(rows[2].label, "Explore");
});
test("buildStructure: 複数 pane のタブは最後に focus された pane を代表にした 1 行", () => {
  const nested = [{ space: sp("s1", [tab("a")]), depth: 0 }];
  const agents = [ag("t1", "a", "working", { pane: "p2" })];
  const panes = [{ pane: "p1", tab: "a" }, { pane: "p2", tab: "a" }, { pane: "q", tab: "other" }];
  const base = { nested, agents, subagents: { t1: [{ id: "x", type: "Explore" }] }, sessions: {}, panes, collapsed: new Set() };
  // 覚えが無ければ並びの最初 (端末)
  const first = buildStructure(base);
  assert.deepEqual(first.map((r) => [r.kind, r.depth, r.key]), [["space", 0, "space:s1"], ["tab", 1, "tab:a"]]);
  assert.equal(first[1].paneId, "p1");
  assert.equal(first[1].status, "working");
  assert.equal("paneCount" in first[1], false);
  // エージェントの pane が代表ならエージェントの行とサブエージェント
  const agentRep = buildStructure({ ...base, activePanes: new Map([["a", "p2"]]) });
  assert.deepEqual(agentRep.map((r) => [r.kind, r.depth, r.key]), [["space", 0, "space:s1"], ["agent", 1, "agent:t1"], ["sub", 2, "sub:t1:x"]]);
  // 覚えた pane が無くなったら並びの最初
  assert.equal(buildStructure({ ...base, activePanes: new Map([["a", "gone"]]) })[1].key, "tab:a");
});
test("buildStructure: pane の無いエージェントが 2 つのタブは最初のエージェント、worktree は字下げ、モデルが無ければプログラム名・tab_name", () => {
  const nested = [
    { space: sp("s1", [tab("a")]), depth: 0 },
    { space: sp("s2", [tab("z")]), depth: 1 },
  ];
  const agents = [ag("t1", "a", "idle"), ag("t2", "a", "blocked"), ag("t3", "z", "done", { space: "s2", program: null })];
  const rows = buildStructure({ nested, agents, subagents: {}, sessions: { t1: { model: "Opus 5.5" } }, collapsed: new Set() });
  assert.deepEqual(rows.map((r) => [r.kind, r.depth, r.label]), [
    ["space", 0, "s1"], ["agent", 1, "Opus 5.5"],
    ["space", 1, "s2"], ["agent", 2, "z"],
  ]);
});
test("isFocusRow: focus の pane とそれを含むタブと space、サブエージェントは親に従う", () => {
  const focus = { space: "s1", tab: "a", pane: "p1", terminal: "t1" };
  assert.equal(isFocusRow({ kind: "space", spaceId: "s1" }, focus), true);
  assert.equal(isFocusRow({ kind: "space", spaceId: "s2" }, focus), false);
  assert.equal(isFocusRow({ kind: "tab", tabId: "a" }, focus), true);
  assert.equal(isFocusRow({ kind: "tab", tabId: "b" }, focus), false);
  assert.equal(isFocusRow({ kind: "agent", address: "t1" }, focus), true);
  assert.equal(isFocusRow({ kind: "sub", address: "t1" }, focus), true);
  assert.equal(isFocusRow({ kind: "agent", address: "t2" }, { ...focus, terminal: null }), false);
  assert.equal(isFocusRow({ kind: "space", spaceId: "s1" }, null), false);
});
test("buildGroups と agentOrder: 入力待ちが先、Idle は畳める", () => {
  const agents = [ag("t1", "a", "working"), ag("t2", "b", "blocked"), ag("t3", "c", "idle")];
  const rows = buildGroups({ agents, subagents: {}, sessions: { t1: { model: "Opus 5.5" }, t2: { model: "Sonnet 5" } }, collapsed: new Set(["group:idle"]) });
  assert.deepEqual(rows.map((r) => r.key), ["group:blocked", "agent:t2", "group:working", "agent:t1", "group:idle"]);
  assert.equal(rows.at(-1).count, 1);
  assert.equal(rows.at(-1).open, false);
  assert.deepEqual(agentOrder(rows), ["t2", "t1"]);
});
test("buildGroups: サブエージェントは depth 2、エージェントのいないまとまりは出さない", () => {
  const agents = [ag("t1", "a", "working")];
  const rows = buildGroups({ agents, subagents: { t1: [{ id: "x", type: "Explore" }] }, sessions: {}, collapsed: new Set() });
  assert.deepEqual(rows.map((r) => [r.key, r.depth]), [["group:working", 0], ["agent:t1", 1], ["sub:t1:x", 2]]);
  assert.equal(rows[1].spaceName, "dotfiles");
  assert.equal(rows[0].open, true);
  assert.deepEqual(buildGroups({ agents: [], subagents: {}, sessions: {}, collapsed: new Set() }), []);
});

test("collectSubagents: 作業中の Claude Code のサブエージェントと hc run の端末", () => {
  const now = 10_000_000;
  const live = [ag("t1", "tab1", "working"), ag("t2", "tab2"), ag("laptop/t3", "tab3")];
  const activity = {
    t1: { subagents: [
      { id: "a1", type: "Explore", status: "working", started_at: now },
      { id: "a2", type: "Plan", status: "done", started_at: now },
    ] },
    t3: { subagents: [{ id: "x", type: "Explore", status: "working", started_at: now }] }, // 別のコンピューターの t3 と結ばない
    gone: { subagents: [{ id: "y", type: "Explore", status: "working", started_at: now }] }, // agents() にない端末
  };
  const terms = [
    { address: "t9", parent: "t1", state: "live", name: "lint", argv: ["npm"] },
    { address: "t10", parent: "t2", state: "live", argv: ["pytest", "-x"] },
    { address: "t11", parent: "t2", state: "finished", argv: ["old"] },
    { address: "t12", parent: "t5", state: "live", argv: ["x"] },
  ];
  assert.deepEqual(collectSubagents(live, activity, terms, {}, now), {
    t1: [{ id: "a1", type: "Explore" }, { id: "t9", type: "lint" }],
    t2: [{ id: "t10", type: "pytest" }],
  });
  assert.deepEqual(collectSubagents(live, {}, [], {}, now), {});
});
test("activityFor: agents() にない端末と別のコンピューターの端末は引かない", () => {
  const activity = { t1: { actions: [] }, t3: { actions: [] } };
  const live = [ag("t1", "a"), ag("laptop/t3", "b")];
  assert.deepEqual(activityFor("t1", activity, live), { actions: [] });
  assert.equal(activityFor("laptop/t3", activity, live), null);
  assert.equal(activityFor("t3", activity, live), null);
});
test("activityFor: セッションが変わった記録は使わない (Review Focus 4)", () => {
  const live = [ag("t1", "a")];
  const activity = { t1: { session_id: "old", actions: [] } };
  assert.equal(activityFor("t1", activity, live, { t1: { session_id: "new" } }), null);
  assert.deepEqual(activityFor("t1", activity, live, { t1: { session_id: "old" } }), activity.t1);
  assert.deepEqual(activityFor("t1", activity, live, {}), activity.t1); // セッションが分からなければ使う
  assert.deepEqual(activityFor("t1", { t1: { actions: [] } }, live, { t1: { session_id: "new" } }), { actions: [] });
});
test("collectSubagents: 親の状態によらず、始まって 30 分までの作業中のサブエージェントを出す", () => {
  const now = 10_000_000;
  const fresh = { id: "a1", type: "agy:worker", status: "working", started_at: now - SUBAGENT_STALE_MS + 1 };
  const stale = { id: "a2", type: "Explore", status: "working", started_at: now - SUBAGENT_STALE_MS };
  const old = { id: "a3", type: "Explore", status: "working" }; // started_at のない古い記録
  const live = [ag("t1", "a", "idle"), ag("t2", "b", "done")];
  const activity = { t1: { subagents: [fresh, stale, old] }, t2: { subagents: [fresh] } };
  assert.deepEqual(collectSubagents(live, activity, [], {}, now), {
    t1: [{ id: "a1", type: "agy:worker" }],
    t2: [{ id: "a1", type: "agy:worker" }],
  });
});
test("collectSubagents: セッションが変わった記録のサブエージェントは出さない", () => {
  const now = 10_000_000;
  const live = [ag("t1", "a", "working")];
  const activity = { t1: { session_id: "old", subagents: [{ id: "a1", type: "Explore", status: "working", started_at: now }] } };
  assert.deepEqual(collectSubagents(live, activity, [], { t1: { session_id: "new" } }, now), {});
});

test("stepTab: 同じ space の中で回る", () => {
  const nested = [{ space: sp("s1", [tab("t1"), tab("t2")]), depth: 0 }];
  const focus = { space: "s1", tab: "t2", pane: "p2", terminal: null };
  assert.equal(stepTab(nested, focus, 1), "t1");
  assert.equal(stepTab(nested, focus, -1), "t1");
});

test("stepTab: focus が並びに無いと先頭 / 末尾", () => {
  const nested = [
    { space: sp("s1", [tab("t1"), tab("t2")]), depth: 0 },
    { space: sp("s2", [tab("t3"), tab("t4")]), depth: 0 },
  ];
  assert.equal(stepTab(nested, null, 1), "t1");
  assert.equal(stepTab(nested, null, -1), "t4");
  assert.equal(stepTab(nested, { space: "gone", tab: "x" }, 1), "t1");
  assert.equal(stepTab(nested, { space: "gone", tab: "x" }, -1), "t4");
});

test("stepTab / stepSpace / stepAgent: 空なら null", () => {
  assert.equal(stepTab([], null, 1), null);
  assert.equal(stepTab([{ space: sp("s1", []), depth: 0 }], null, 1), null);
  assert.equal(stepSpace([], null, 1), null);
  assert.equal(stepAgent([], null, 1), null);
  assert.equal(stepGroup([], null, 1), null);
});

test("stepSpace: 端で回る", () => {
  const nested = [
    { space: sp("s1", []), depth: 0 },
    { space: sp("s2", []), depth: 0 },
    { space: sp("s3", []), depth: 0 },
  ];
  assert.equal(stepSpace(nested, { space: "s3" }, 1), "s1");
  assert.equal(stepSpace(nested, { space: "s1" }, -1), "s3");
  assert.equal(stepSpace(nested, null, 1), "s1");
  assert.equal(stepSpace(nested, null, -1), "s3");
});

test("stepAgent: 閉じたまとまりの中も数え、サブエージェントは数えない", () => {
  const agents = [ag("a1", "t1", "blocked"), ag("a2", "t2", "working")];
  const groups = buildGroups({ agents, subagents: { a1: [{ id: "sub1", type: "Explore" }] }, collapsed: new Set() });
  assert.equal(stepAgent(groups, { terminal: "a1" }, 1), "a2");
  assert.equal(stepAgent(groups, { terminal: "a2" }, 1), "a1");
  assert.equal(stepAgent(groups, { terminal: "a1" }, -1), "a2");
  assert.equal(stepAgent(groups, null, 1), "a1");
  assert.equal(stepAgent(groups, null, -1), "a2");
});

test("stepGroup: 次のまとまりの先頭", () => {
  const agents = [ag("a1", "t1", "blocked"), ag("a2", "t2", "blocked"), ag("a3", "t3", "working")];
  const groups = buildGroups({ agents, subagents: {}, collapsed: new Set() });
  assert.equal(stepGroup(groups, { terminal: "a2" }, 1), "a3");
  assert.equal(stepGroup(groups, { terminal: "a3" }, 1), "a1");
  assert.equal(stepGroup(groups, { terminal: "a1" }, -1), "a3");
  assert.equal(stepGroup(groups, null, 1), "a1");
  assert.equal(stepGroup(groups, null, -1), "a3");
});

test("moveTarget: tab は by、space は index で回る", () => {
  const nested = [
    { space: sp("s1", [tab("t1")], { index: 1 }), depth: 0 },
    { space: sp("s2", [tab("t2")], { index: 2 }), depth: 0 },
    { space: sp("s3", [tab("t3")], { index: 3 }), depth: 0 },
  ];
  assert.deepEqual(moveTarget(nested, { space: "s1", tab: "t1" }, 1, "tab"), { command: "tab.move", args: { id: "t1", by: 1 } });
  assert.deepEqual(moveTarget(nested, { space: "s3", tab: "t3" }, 1, "space"), { command: "space.move", args: { id: "s3", index: 1 } });
  assert.deepEqual(moveTarget(nested, { space: "s1", tab: "t1" }, -1, "space"), { command: "space.move", args: { id: "s1", index: 3 } });
});

test("moveTarget: 別のコンピューターの space をまたぐと null", () => {
  const nested = [
    { space: sp("s1", [], { index: 1 }), depth: 0 },
    { space: sp("s2", [], { index: 2 }), depth: 0 },
    { space: sp("laptop/s3", [], { index: 3, machine: "laptop" }), depth: 0 },
  ];
  assert.equal(moveTarget(nested, { space: "s2" }, 1, "space"), null);
  assert.equal(moveTarget(nested, { space: "s1" }, -1, "space"), null);
  assert.deepEqual(moveTarget(nested, { space: "s1" }, 1, "space"), { command: "space.move", args: { id: "s1", index: 2 } });
  assert.equal(moveTarget(nested, { space: "laptop/s3" }, -1, "space"), null);
});

test("moveTarget: worktree で表示順と herdr の並びが違っても space.index の順で動く", () => {
  const nested = [
    { space: sp("A", [], { index: 1 }), depth: 0 },
    { space: sp("C", [], { index: 3 }), depth: 1 },
    { space: sp("B", [], { index: 2 }), depth: 0 },
  ];
  assert.deepEqual(moveTarget(nested, { space: "C" }, -1, "space"), { command: "space.move", args: { id: "C", index: 2 } });
  assert.deepEqual(moveTarget(nested, { space: "C" }, 1, "space"), { command: "space.move", args: { id: "C", index: 1 } });
});

test("moveTarget: herdr の並びで隣が remote なら null、remote が間にあっても端は同じコンピューターの最大で回る", () => {
  const nested = [
    { space: sp("A", [], { index: 1 }), depth: 0 },
    { space: sp("C", [], { index: 3 }), depth: 1 },
    { space: sp("laptop/R", [], { index: 2, machine: "laptop" }), depth: 0 },
  ];
  // 表示は [A, C, R] だが herdr の並びは [A(1), R(2), C(3)]
  assert.equal(moveTarget(nested, { space: "A" }, 1, "space"), null);
  assert.equal(moveTarget(nested, { space: "C" }, -1, "space"), null);
  assert.deepEqual(moveTarget(nested, { space: "A" }, -1, "space"), { command: "space.move", args: { id: "A", index: 3 } });
  assert.deepEqual(moveTarget(nested, { space: "C" }, 1, "space"), { command: "space.move", args: { id: "C", index: 1 } });
});

test("closeKey / openKey: 構造の表示では開閉しない", () => {
  const nested = [{ space: sp("s1", [tab("a")]), depth: 0 }];
  const panes = [{ pane: "p1", tab: "a" }, { pane: "p2", tab: "a" }];
  const focus = { space: "s1", tab: "a", pane: "p1", terminal: null };
  const rows = buildStructure({ nested, agents: [], subagents: {}, panes, collapsed: new Set() });
  assert.deepEqual(focusContainers({ view: "structure", agents: [], focus }), []);
  assert.equal(openKey(rows, focus, ["space:s1"], "group"), null);
  assert.equal(closeKey(rows, focus, ["space:s1"], "small"), null);
});

test("closeKey / openKey: status ビューでもサブエージェントとまとまりを開閉できる", () => {
  const agents = [ag("a1", "t1", "working"), ag("a2", "t2", "working")];
  const subagents = { a1: [{ id: "s1", type: "Explore" }] };
  const focus = { space: "s1", tab: "t1", pane: "p1", terminal: "a1" };
  const containers = ["group:working"];

  const rowsOpen = buildGroups({ agents, subagents, collapsed: new Set() });
  assert.equal(openKey(rowsOpen, focus, containers, "small"), null);
  assert.equal(closeKey(rowsOpen, focus, containers, "small"), "agent:a1");
  assert.equal(closeKey(rowsOpen, focus, containers, "group"), "group:working");

  const rowsSubClosed = buildGroups({ agents, subagents, collapsed: new Set(["agent:a1"]) });
  assert.equal(openKey(rowsSubClosed, focus, containers, "small"), "agent:a1");
  assert.equal(closeKey(rowsSubClosed, focus, containers, "small"), "group:working");
  assert.equal(closeKey(rowsSubClosed, { ...focus, terminal: "a2" }, containers, "small"), "group:working");
});

test("closeKey / openKey: focus が一覧に無ければ null", () => {
  const nested = [{ space: sp("s1", [tab("a")]), depth: 0 }];
  const rows = buildStructure({ nested, agents: [], subagents: {}, panes: [{ pane: "p1", tab: "a" }], collapsed: new Set() });
  assert.equal(openKey(rows, null, [], "small"), null);
  assert.equal(closeKey(rows, null, [], "small"), null);
  assert.equal(closeKey(rows, { space: "wtr", tab: "w", pane: null, terminal: "wtr" }, [], "group"), null);
});

test("focusContainers: status では group の鍵", () => {
  const agents = [ag("t1", "a", "working"), ag("t2", "b", "blocked")];
  const focus = { space: "s1", tab: "a", pane: "p1", terminal: "t1" };
  assert.deepEqual(focusContainers({ view: "status", agents, focus }), ["group:working"]);
  assert.deepEqual(focusContainers({ view: "status", agents, focus: { ...focus, terminal: "other" } }), []);
});

test("focusContainers: focus が null なら []", () => {
  assert.deepEqual(focusContainers({ view: "status", agents: [ag("t1", "a", "working")], focus: null }), []);
});

test("effectiveCollapsed: focus のまとまりは開き、held は閉じたまま、他はそのまま", () => {
  const collapsed = new Set(["group:working", "group:idle"]);
  const opened = effectiveCollapsed(collapsed, ["group:working"], new Set());
  assert.equal(opened.has("group:working"), false);
  assert.equal(opened.has("group:idle"), true);
  // 元の collapsed は変えない
  assert.equal(collapsed.has("group:working"), true);
  const kept = effectiveCollapsed(collapsed, ["group:working"], new Set(["group:working"]));
  assert.equal(kept.has("group:working"), true);
});

test("pruneHeld: 離れた鍵を捨てる", () => {
  const held = new Set(["group:working", "group:idle"]);
  const next = pruneHeld(held, ["group:working"]);
  assert.deepEqual([...next], ["group:working"]);
  assert.equal(held.size, 2);
});

test("highlightKey: 代表のエージェントかタブの行、閉じたまとまりならまとまりの行", () => {
  const nested = [{ space: sp("s1", [tab("a"), tab("b")]), depth: 0 }];
  const agents = [ag("t1", "a", "working", { pane: "p2" })];
  const panes = [{ pane: "p1", tab: "a" }, { pane: "p2", tab: "a" }, { pane: "p3", tab: "b" }];
  const focusPane = { space: "s1", tab: "a", pane: "p1", terminal: null };
  const focusAgent = { space: "s1", tab: "a", pane: "p2", terminal: "t1" };

  const paneRep = buildStructure({ nested, agents, subagents: {}, panes, collapsed: new Set(), activePanes: new Map([["a", "p1"]]) });
  assert.equal(highlightKey(paneRep, focusPane, []), "tab:a");
  const agentRep = buildStructure({ nested, agents, subagents: {}, panes, collapsed: new Set(), activePanes: new Map([["a", "p2"]]) });
  assert.equal(highlightKey(agentRep, focusAgent, []), "agent:t1");
  assert.equal(highlightKey(agentRep, { space: "s1", tab: "b", pane: "p3", terminal: null }, []), "tab:b");

  const groupClosed = buildGroups({ agents, subagents: {}, collapsed: new Set(["group:working"]) });
  assert.equal(highlightKey(groupClosed, focusAgent, ["group:working"]), "group:working");

  assert.equal(highlightKey(agentRep, null, []), null);
});

test("buildGroups: まとまりの中を since の古い順", () => {
  const agents = [
    ag("t1", "a", "working"),
    ag("t2", "b", "working"),
    ag("t3", "c", "working"),
    ag("t4", "d", "working"),
    ag("t5", "e", "working"),
  ];
  const times = {
    t1: { since: 3000 },
    t2: { since: 1000 },
    t4: { since: 1000 },
    // t3, t5 は since なし → 後ろに元の順で並ぶ
  };
  const rows = buildGroups({ agents, subagents: {}, collapsed: new Set(), times });
  assert.deepEqual(agentOrder(rows), ["t2", "t4", "t1", "t3", "t5"]);
});
