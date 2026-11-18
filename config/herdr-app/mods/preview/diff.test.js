import { test } from "node:test";
import assert from "node:assert/strict";
import { parseUnifiedDiff, diffArgs } from "./diff.js";

test("parseUnifiedDiff", () => {
  const text = ["diff --git a/x b/x", "index 1..2", "--- a/x", "+++ b/x", "@@ -1,3 +1,3 @@", " a", "-b", "+B", " c", "\\ No newline at end of file", ""].join("\n");
  assert.deepEqual(
    parseUnifiedDiff(text).map((r) => [r.kind, r.old, r.new, r.text]),
    [
      ["hunk", null, null, "@@ -1,3 +1,3 @@"],
      ["context", 1, 1, "a"],
      ["del", 2, null, "b"],
      ["add", null, 2, "B"],
      ["context", 3, 3, "c"],
    ],
  );
  assert.deepEqual(parseUnifiedDiff(""), []);
});

test("parseUnifiedDiff: 複数のハンクと 1 行だけのハンク", () => {
  const text = ["@@ -1 +1 @@", "-a", "+b", "@@ -10,2 +20,2 @@ fn()", " x", "+y"].join("\n");
  assert.deepEqual(
    parseUnifiedDiff(text).map((r) => [r.kind, r.old, r.new]),
    [["hunk", null, null], ["del", 1, null], ["add", null, 1], ["hunk", null, null], ["context", 10, 20], ["add", null, 21]],
  );
});

test("parseUnifiedDiff: ハンクの中の --- と +++ で始まる行は中身として数える", () => {
  const text = ["--- a/x", "+++ b/x", "@@ -1,2 +1,2 @@", "--- foo", "+++ bar"].join("\n");
  assert.deepEqual(
    parseUnifiedDiff(text).map((r) => [r.kind, r.text]),
    [["hunk", "@@ -1,2 +1,2 @@"], ["del", "-- foo"], ["add", "++ bar"]],
  );
});

test("diffArgs", () => {
  assert.deepEqual(diffArgs({ mode: "edit", a: "/t/a", b: "/t/b" }).args, ["diff", "--no-index", "--no-color", "--no-ext-diff", "-U3", "/t/a", "/t/b"]);
  assert.equal(diffArgs({ mode: "head", root: "/r", path: "x y.md", hasHead: false }).args.includes("HEAD"), false);
  const head = diffArgs({ mode: "head", root: "/r", path: "x y.md", hasHead: true });
  assert.equal(head.cmd, "git");
  assert.equal(head.cwd, "/r");
  assert.deepEqual(head.args, ["--no-optional-locks", "diff", "HEAD", "--no-color", "--no-ext-diff", "--", "x y.md"]);
});
