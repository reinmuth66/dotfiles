import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const layout = JSON.parse(readFileSync(new URL("./workbench.json", import.meta.url), "utf8"));

function walk(node, out = []) {
  out.push(node);
  for (const c of node.children ?? []) walk(c, out);
  return out;
}
const nodes = walk(layout);
const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));

// 窓を動かす場所は帯の一番上 (usage) だけ。帯の全体に付けると、同梱の spaces の並べ替えの
// ドラッグや、ツリーのダブルクリックが窓の移動と最大化になる
test("window_drag は usage のブロックだけ", () => {
  assert.deepEqual(
    nodes.filter((n) => n.window_drag).map((n) => n.id),
    ["usage"],
  );
});

// プレビューを伸ばしても、エージェントの枠が潰れない
test("エージェントの枠に最小の幅がある", () => {
  assert.ok((byId["agent-area"].min ?? 0) >= 320);
});

// サイドバーを狭めても、usage の 2 つの円と数字が切れない
test("サイドバーに最小の幅がある", () => {
  assert.ok((byId.sidebar.min ?? 0) >= 240);
});

test("resize-mode が動かすブロックの id がある", () => {
  for (const id of ["sidebar", "usage", "workspace", "tree", "preview-area", "agent-area"]) {
    assert.ok(byId[id], `${id} がない`);
  }
});

test("枠の見出しは pane-header", () => {
  assert.equal(byId["agent-area"].content.pane.header.content.mod, "pane-header");
});

test("帯の中は usage、workspace、tree の 3 つの自分の mod", () => {
  assert.deepEqual(byId.sidebar.children.map((c) => [c.id, c.content?.mod]), [["usage", "usage"], ["workspace", "workspace"], ["tree", "tree"]]);
});

test("preview-area の stack に preview、wtr、browser の枠がある", () => {
  assert.deepEqual(byId["preview-area"].children.map((c) => c.id), ["preview", "wtr", "browser"]);
  assert.equal(byId.browser.content.terminal, "browser");
});
