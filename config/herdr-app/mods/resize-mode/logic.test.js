import { test } from "node:test";
import assert from "node:assert/strict";
import { keyToMove, nextSize, nextSidebarMode, LIMITS } from "./logic.js";

// キーは WezTerm の resize_pane と同じ: u 上、o 左、a 下、i 右、Enter で抜ける。
// o と i はプレビューの幅、Shift を付けた O と I は帯の幅、u と a は帯の中の一覧の高さ
test("keyToMove: 境目を動かすキー", () => {
  assert.deepEqual(keyToMove("o"), { target: "preview", delta: -20 });
  assert.deepEqual(keyToMove("i"), { target: "preview", delta: 20 });
  assert.deepEqual(keyToMove("o", { shift: true }), { target: "sidebar", delta: -20 });
  assert.deepEqual(keyToMove("i", { shift: true }), { target: "sidebar", delta: 20 });
  assert.deepEqual(keyToMove("u"), { target: "workspace", delta: -20 });
  assert.deepEqual(keyToMove("a"), { target: "workspace", delta: 20 });
  assert.equal(keyToMove("x"), null);
});

test("keyToMove: Enter と Escape で抜ける", () => {
  assert.equal(keyToMove("enter"), "exit");
  assert.equal(keyToMove("escape"), "exit"); // Review Focus 3
});

// 修飾キー付きのキー (Ctrl+Shift+L の pane.go など) は global の操作に渡すが、
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
