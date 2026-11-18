import { test } from "node:test";
import assert from "node:assert/strict";
import { parseStatus, ORDER, STRENGTH, folderState, counts, GIT_STYLE, fileIcon, flatten, treeRoot, parentIndex } from "./logic.js";
import { GLYPH, PALETTE } from "./ui.js";

test("parseStatus: 空白と日本語のパス", () => {
  const z = [" M docs/設計 書.md", "M  a.nix", "A  new.txt", "?? 画像/x.png", " D gone.lua", "UU c.txt", ""].join("\0");
  assert.deepEqual(parseStatus(z), { "docs/設計 書.md": "modified", "a.nix": "staged", "new.txt": "added", "画像/x.png": "untracked", "gone.lua": "deleted", "c.txt": "conflict" });
});
test("parseStatus: 衝突、索引と作業ツリーの両方、空", () => {
  const z = ["AA a", "DD b", "AU c", "UD d", "MM e", "AM f", "D  g", "R  h", ""].join("\0");
  assert.deepEqual(parseStatus(z), { a: "conflict", b: "conflict", c: "conflict", d: "conflict", e: "modified", f: "modified", g: "staged", h: "staged" });
  assert.deepEqual(parseStatus(""), {});
});
test("ORDER と STRENGTH", () => {
  assert.deepEqual(ORDER, ["staged", "added", "modified", "deleted", "untracked", "conflict"]);
  assert.deepEqual(STRENGTH, ["untracked", "modified", "staged", "added", "deleted", "conflict"]);
});
test("GIT_STYLE", () => {
  assert.deepEqual(GIT_STYLE.staged, { glyph: GLYPH.diffModified, color: PALETTE.blue });
  assert.deepEqual(GIT_STYLE.added, { glyph: GLYPH.diffAdded, color: PALETTE.green });
  assert.deepEqual(GIT_STYLE.modified, { glyph: GLYPH.diffModified, color: PALETTE.yellow });
  assert.deepEqual(GIT_STYLE.deleted, { glyph: GLYPH.diffRemoved, color: PALETTE.red });
  assert.deepEqual(GIT_STYLE.untracked, { glyph: "?", color: PALETTE.overlay2 });
  assert.deepEqual(GIT_STYLE.conflict, { glyph: GLYPH.diffModified, color: PALETTE.peach });
});
test("folderState と counts", () => {
  const s = { "config/a.md": "modified", "config/marp/b.css": "staged", "config/c": "untracked", "x.nix": "deleted" };
  assert.equal(folderState(s, "config"), "untracked");
  assert.equal(folderState(s, "config/marp"), "staged");
  assert.equal(folderState(s, "modules"), null);
  assert.deepEqual(counts(s), [{ state: "staged", n: 1 }, { state: "modified", n: 1 }, { state: "deleted", n: 1 }, { state: "untracked", n: 1 }]);
  assert.deepEqual(counts({}), []);
});
test("folderState: 名前の前方一致でフォルダを取り違えない", () => {
  assert.equal(folderState({ "config2/a": "modified" }, "config"), null);
});
test("fileIcon", () => {
  const table = { files: [{ name: "flake.nix", text: "F", fg: "#1" }], exts: [{ name: "nix", text: "N", fg: "#2" }], conds: [{ if: "dir", text: "R", fg: "#4" }, { if: "!dir", text: "D", fg: "#3" }] };
  assert.equal(fileIcon("flake.nix", table).text, "F");
  assert.equal(fileIcon("home.NIX", table).text, "N");
  assert.equal(fileIcon("README", table).text, "D");
  assert.equal(fileIcon(".gitignore", table).text, "D");
  assert.equal(fileIcon("a.nix", null).text, "\u{f0214}");
  assert.equal(fileIcon("a.nix", null).fg, PALETTE.text);
});
test("flatten: フォルダが先、隠しと無視は既定で出さない", () => {
  const children = { "": [{ name: "b.txt", dir: false }, { name: "config", dir: true }, { name: ".git", dir: true }, { name: "result", dir: true }], config: [{ name: "x.md", dir: false }] };
  const rows = flatten({ root: "/r", children, open: new Set(["config"]), showHidden: false, ignored: new Set(["result"]) });
  assert.deepEqual(rows.map((r) => [r.rel, r.depth]), [["config", 0], ["config/x.md", 1], ["b.txt", 0]]);
  assert.equal(flatten({ root: "/r", children, open: new Set(), showHidden: true, ignored: new Set(["result"]) }).length, 4);
});
test("flatten: open の印と、読み込み前のフォルダ", () => {
  const children = { "": [{ name: "a", dir: true }, { name: "b", dir: true }] };
  const rows = flatten({ root: "/r", children, open: new Set(["a", "b"]), showHidden: false, ignored: new Set() });
  assert.deepEqual(rows.map((r) => [r.rel, r.open]), [["a", true], ["b", true]]);
});
test("treeRoot", () => {
  assert.equal(treeRoot({ space: { machine: null, folder: "/r/x/sub" }, repoRoot: "/r/x", home: "/h" }), "/r/x");
  assert.equal(treeRoot({ space: { machine: null, folder: "" }, repoRoot: null, home: "/h" }), "/h");
  assert.equal(treeRoot({ space: { machine: null, folder: "/r/y" }, repoRoot: null, home: "/h" }), "/r/y");
  assert.equal(treeRoot({ space: { machine: "laptop", folder: "/r/x" }, repoRoot: null, home: "/h" }), null);
  assert.equal(treeRoot({ space: null, repoRoot: null, home: "/h" }), null);
  // 枠の cwd の git のルートが先
  assert.equal(treeRoot({ space: { machine: null, folder: "/r/x" }, repoRoot: "/r/x", cwdRepoRoot: "/r/z", home: "/h" }), "/r/z");
  assert.equal(treeRoot({ space: { machine: null, folder: "" }, repoRoot: null, cwdRepoRoot: "/r/z", home: "/h" }), "/r/z");
  assert.equal(treeRoot({ space: { machine: "laptop", folder: "/r/x" }, repoRoot: null, cwdRepoRoot: "/r/z", home: "/h" }), null);
});
test("parentIndex", () => {
  const rows = [
    { kind: "root" },
    { kind: "entry", rel: "a", depth: 0, dir: true },
    { kind: "entry", rel: "a/b", depth: 1, dir: true },
    { kind: "entry", rel: "a/b/c", depth: 2 },
    { kind: "entry", rel: "a/d", depth: 1 },
    { kind: "entry", rel: "e", depth: 0 },
  ];
  assert.equal(parentIndex(rows, 0), null);
  assert.equal(parentIndex(rows, 1), 0);
  assert.equal(parentIndex(rows, 3), 2);
  assert.equal(parentIndex(rows, 4), 1);
  assert.equal(parentIndex(rows, 5), 0);
  assert.equal(parentIndex(rows, 9), null);
});
