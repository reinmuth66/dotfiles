import { test } from "node:test";
import assert from "node:assert/strict";
import { TABLE_MAX_ROWS, parseDelimited, toMarkdownTable } from "./table.js";

test("引用符の中のカンマと改行", () => {
  assert.deepEqual(parseDelimited('a,b\n"x, y","1\n2"\n', ","), [
    ["a", "b"],
    ["x, y", "1\n2"],
  ]);
  assert.deepEqual(parseDelimited('a,"say ""hi"""\r\n', ","), [["a", 'say "hi"']]);
  assert.deepEqual(parseDelimited("a\tb\n1\t2", "\t"), [
    ["a", "b"],
    ["1", "2"],
  ]);
});

test("列の数が違う行と、表に使えない文字", () => {
  const { markdown, truncated } = toMarkdownTable([["a", "b", "c"], ["1"], ["x|y", "p\nq"]], 300);
  assert.equal(markdown, "| a | b | c |\n|---|---|---|\n| 1 |  |  |\n| x\\|y | p q |  |\n");
  assert.equal(truncated, false);
});

test("maxRows を超えたら切る", () => {
  const rows = [["h"], ...Array.from({ length: 5 }, (_, i) => [String(i)])];
  const { markdown, truncated } = toMarkdownTable(rows, 2);
  assert.equal(markdown.trim().split("\n").length, 4);
  assert.equal(truncated, true);
});

test("空の CSV", () => {
  assert.deepEqual(toMarkdownTable([], 300), { markdown: "", truncated: false });
  assert.equal(TABLE_MAX_ROWS, 300);
});
