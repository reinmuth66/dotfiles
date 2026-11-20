import { test } from "node:test";
import assert from "node:assert/strict";
import { createHistory, expandedLayout, filePathOf, initialHistoryState, moveIndex, summary, toEdge, withCount } from "./history.js";

const use = (id, name, input, extra = {}) =>
  JSON.stringify({ type: "assistant", isSidechain: false, ...extra, message: { content: [{ type: "tool_use", id, name, input }] } });
const res = (id, text, toolUseResult) =>
  JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, content: text }] }, toolUseResult });

test("呼び出しと結果を結ぶ", () => {
  const h = createHistory();
  assert.equal(h.add([use("t1", "Bash", { command: "ls\nwc" }), res("t1", "a\nb")]), true);
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].result.text, "a\nb");
  assert.deepEqual(summary(h.entries[0]), { name: "Bash", detail: "ls" });
});
test("Edit の増減とパス", () => {
  const h = createHistory();
  const patch = [{ oldStart: 1, oldLines: 2, newStart: 1, newLines: 3, lines: [" a", "-b", "+c", "+d"] }];
  h.add([use("t2", "Edit", { file_path: "/x/y.nix" }), res("t2", "ok", { filePath: "/x/y.nix", structuredPatch: patch })]);
  assert.deepEqual(summary(h.entries[0]), { name: "Edit", detail: "/x/y.nix +2 -1" });
  assert.equal(filePathOf(h.entries[0]), "/x/y.nix");
});
test("子のエージェントの記録と壊れた行は飛ばす", () => {
  const h = createHistory();
  h.add([use("s1", "Bash", { command: "x" }, { isSidechain: true }), "{broken", use("t3", "Grep", { pattern: "foo" })]);
  assert.deepEqual(h.entries.map((e) => e.id), ["t3"]);
  assert.deepEqual(summary(h.entries[0]), { name: "Grep", detail: "foo" });
});
test("結果の content が配列でも文字にする", () => {
  const h = createHistory();
  const r = JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "t4", content: [{ type: "text", text: "hi" }], is_error: true }] } });
  h.add([use("t4", "Read", { file_path: "/a" }), r]);
  assert.equal(h.entries[0].result.text, "hi");
  assert.equal(h.entries[0].result.isError, true);
});
test("結果が先に来ても結ぶ。toolUseResult が文字列でも読める", () => {
  const h = createHistory();
  h.add([res("t5", "done", "plain string")]);
  assert.equal(h.entries.length, 0);
  h.add([use("t5", "Write", { file_path: "/w" })]);
  assert.equal(h.entries[0].result.text, "done");
  assert.equal(h.entries[0].result.patch, null);
  assert.equal(h.entries[0].result.filePath, null);
  assert.equal(filePathOf(h.entries[0]), "/w");
});
test("結果がない Edit はパスだけ。そのほかの道具の要点", () => {
  const e = (name, input, result = null) => ({ id: "x", name, input, result });
  assert.deepEqual(summary(e("Edit", { file_path: "/p" })), { name: "Edit", detail: "/p" });
  assert.deepEqual(summary(e("WebSearch", { query: "q" })), { name: "WebSearch", detail: "q" });
  assert.deepEqual(summary(e("Agent", { subagent_type: "Explore", description: "d" })), { name: "Agent", detail: "Explore d" });
  assert.deepEqual(summary(e("TodoWrite", {})), { name: "TodoWrite", detail: "" });
  assert.equal(filePathOf(e("Bash", { command: "x" })), null);
});
test("何も変わらなければ偽を返す", () => {
  const h = createHistory();
  assert.equal(h.add(["{broken", JSON.stringify({ type: "summary" })]), false);
});
test("一覧の移動と自動のスクロール", () => {
  let s = initialHistoryState(3);
  assert.deepEqual(s, { mode: "list", index: 2, follow: true });
  s = moveIndex(s, -1, 3);
  assert.equal(s.follow, false);
  assert.equal(withCount(s, 4).index, 1);
  s = toEdge(s, "last", 4);
  assert.equal(withCount(s, 5).index, 4);
  assert.equal(moveIndex(s, 5, 5).index, 4);
  assert.equal(toEdge(s, "first", 5).index, 0);
});
test("展開の上下の端", () => {
  assert.deepEqual(expandedLayout(0, 5, 100, 20), { before: null, after: [1] });
  assert.deepEqual(expandedLayout(4, 5, 100, 20), { before: 3, after: [] });
  assert.deepEqual(expandedLayout(1, 10, 3, 8), { before: 0, after: [2, 3, 4, 5] });
});
test("履歴が 0 件", () => {
  assert.deepEqual(initialHistoryState(0), { mode: "list", index: 0, follow: true });
  assert.deepEqual(expandedLayout(0, 0, 0, 10), { before: null, after: [] });
});
