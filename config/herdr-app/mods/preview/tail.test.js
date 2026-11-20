import { test } from "node:test";
import assert from "node:assert/strict";
import { byteLength, splitComplete, tailArgs } from "./tail.js";

test("書きかけの行は残す", () => {
  assert.deepEqual(splitComplete('{"a":1}\n{"b":'), { lines: ['{"a":1}'], rest: '{"b":' });
  assert.deepEqual(splitComplete('{"b":2}\n\n'), { lines: ['{"b":2}'], rest: "" });
  assert.deepEqual(splitComplete(""), { lines: [], rest: "" });
});
test("続きの読み込みで書きかけの行がつながる", () => {
  const first = splitComplete('{"a":1}\n{"b":');
  const second = splitComplete(first.rest + "2}\n");
  assert.deepEqual(second.lines, ['{"b":2}']);
});
test("改行がなければ全部が書きかけ", () => {
  assert.deepEqual(splitComplete('{"a":'), { lines: [], rest: '{"a":' });
});
test("tailArgs と byteLength", () => {
  assert.deepEqual(tailArgs("/p.jsonl", 0), { cmd: "tail", args: ["-c", "+1", "/p.jsonl"] });
  assert.deepEqual(tailArgs("/p.jsonl", 10), { cmd: "tail", args: ["-c", "+11", "/p.jsonl"] });
  assert.equal(byteLength("aあ"), 4);
});
test("byteLength は TextEncoder がなくても同じ数になる", () => {
  const samples = ["", "abc", "aあ", "😀", "a😀あé", "\u{10FFFF}", "߿ࠀ￿"];
  const encoder = globalThis.TextEncoder;
  try {
    for (const s of samples) {
      const expected = Buffer.byteLength(s, "utf8");
      globalThis.TextEncoder = encoder;
      assert.equal(byteLength(s), expected, `with TextEncoder: ${JSON.stringify(s)}`);
      globalThis.TextEncoder = undefined;
      assert.equal(byteLength(s), expected, `without TextEncoder: ${JSON.stringify(s)}`);
    }
  } finally {
    globalThis.TextEncoder = encoder;
  }
});
test("数 MB の行を分けても遅くならない", () => {
  const big = '{"type":"user"}\n'.repeat(200000);
  const t = Date.now();
  assert.equal(splitComplete(big).lines.length, 200000);
  assert.ok(Date.now() - t < 1000);
});
