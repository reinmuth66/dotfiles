import { test } from "node:test";
import assert from "node:assert/strict";
import { keyToMove, nextSize, nextSidebarMode } from "./logic.js";

// キーは WezTerm の resize_pane と同じ: u 上、o 左、a 下、i 右、Enter で抜ける
test("keyToMove", () => {
  assert.deepEqual(keyToMove("o"), { target: "vertical", delta: -20 });
  assert.deepEqual(keyToMove("i"), { target: "vertical", delta: 20 });
  assert.deepEqual(keyToMove("u"), { target: "horizontal", delta: -20 });
  assert.deepEqual(keyToMove("a"), { target: "horizontal", delta: 20 });
  assert.equal(keyToMove("enter"), "exit");
  assert.equal(keyToMove("escape"), "exit"); // Review Focus 3
  assert.equal(keyToMove("x"), null);
});

test("nextSize", () => {
  assert.equal(nextSize(200, -20, 160, 480), 180);
  assert.equal(nextSize(170, -20, 160, 480), 160); // Review Focus 5
  assert.equal(nextSize(470, 20, 160, 480), 480);
});

test("nextSidebarMode", () => {
  assert.equal(nextSidebarMode("both"), "list");
  assert.equal(nextSidebarMode("list"), "tree");
  assert.equal(nextSidebarMode("tree"), "both");
});
