import { test } from "node:test";
import assert from "node:assert/strict";
import { keyToMove, nextSize, nextSidebarMode, wtrStep, LIMITS } from "./logic.js";

// u/a/o/i は pane の境目 (上/下/左/右)、Shift を付けた J/L はプレビューの幅、I/K は帯の中の一覧の高さ、y/h は帯の幅、Enter/Escape で抜ける
test("keyToMove: 境目を動かすキー", () => {
  assert.deepEqual(keyToMove("u"), { target: "pane", direction: "up" });
  assert.deepEqual(keyToMove("a"), { target: "pane", direction: "down" });
  assert.deepEqual(keyToMove("o"), { target: "pane", direction: "left" });
  assert.deepEqual(keyToMove("i"), { target: "pane", direction: "right" });
  assert.deepEqual(keyToMove("j", { shift: true }), { target: "preview", delta: 20 });
  assert.deepEqual(keyToMove("l", { shift: true }), { target: "preview", delta: -20 });
  assert.deepEqual(keyToMove("k", { shift: true }), { target: "workspace", delta: 20 });
  assert.deepEqual(keyToMove("i", { shift: true }), { target: "workspace", delta: -20 });
  assert.deepEqual(keyToMove("y"), { target: "sidebar", delta: -20 });
  assert.deepEqual(keyToMove("h"), { target: "sidebar", delta: 20 });
  for (const k of ["j", "k", "l", "x", "constructor"]) assert.equal(keyToMove(k), null);
  for (const k of ["u", "a", "o", "x", "constructor"]) assert.equal(keyToMove(k, { shift: true }), null);
});

test("keyToMove: Enter と Escape で抜ける", () => {
  assert.equal(keyToMove("enter"), "exit");
  assert.equal(keyToMove("escape"), "exit"); // Review Focus 3
});

// 修飾キー付きのキー (cmd-l の pane.go など) は global の操作に渡すが、
// モードは畳む。畳まないと、フォーカスが外へ出たあとも RESIZE の表示が残る
test("keyToMove: 修飾キー付きのキーでモードを畳む", () => {
  assert.equal(keyToMove("l", { control: true, shift: true }), "collapse");
  assert.equal(keyToMove("t", { platform: true }), "collapse");
  assert.equal(keyToMove("o", { alt: true }), "collapse");
});

test("nextSize", () => {
  assert.equal(nextSize(200, -20, 160, 480), 180);
  assert.equal(nextSize(170, -20, 160, 480), 160); // Review Focus 5
  assert.equal(nextSize(470, 20, 160, 480), 480);
});

// プレビューを伸ばしすぎて、エージェントの枠が潰れないよう、上限を窓の半分ほどに抑える
test("LIMITS: プレビューの上限は 900 以下", () => {
  assert.ok(LIMITS.preview.max <= 900);
  assert.deepEqual(
    Object.fromEntries(Object.entries(LIMITS).map(([k, v]) => [k, v.id])),
    { sidebar: "sidebar", preview: "preview-area", workspace: "workspace" },
  );
});

test("nextSidebarMode", () => {
  assert.equal(nextSidebarMode("both"), "list");
  assert.equal(nextSidebarMode("list"), "tree");
  assert.equal(nextSidebarMode("tree"), "both");
});

test("wtrStep: preview-area と focus の状態から次の動きを決める", () => {
  assert.equal(wtrStep({ hidden: true, active: "wtr", onWtr: false }), "show");
  assert.equal(wtrStep({ hidden: true, active: "browser", onWtr: false }), "show");
  assert.equal(wtrStep({ hidden: false, active: "browser", onWtr: false }), "show");
  assert.equal(wtrStep({ active: "browser", onWtr: false }), "show");
  assert.equal(wtrStep({ hidden: false, active: "wtr", onWtr: false }), "focus");
  assert.equal(wtrStep({ active: "wtr", onWtr: false }), "focus");
  assert.equal(wtrStep({ hidden: false, active: "wtr", onWtr: true }), "hide");
  assert.equal(wtrStep({ active: "wtr", onWtr: true }), "hide");
});
