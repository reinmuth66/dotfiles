const test = require("node:test");
const assert = require("node:assert/strict");
const { Marp } = require("@marp-team/marp-core");
const title = require("./title.js");

const warningsOf = (t, markdown) => {
  const warn = t.mock.method(console, "warn", () => {});
  new Marp({ html: true }).use(title).render(markdown);
  return warn.mock.calls.map((call) => call.arguments[0]);
};

const LONG = "予測の誤差は、2 つのエンコーダの両方に戻して学習する仕組みにする";

test("1 行に収まらない見込みの題に、スライドの番号つきで警告を出す", (t) => {
  const warnings = warningsOf(t, `# 短い題\n\n---\n\n# ${LONG}\n\n本文\n`);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /スライド 2 /);
  assert.match(warnings[0], /予測の誤差は/);
});

test("収まる題には警告を出さない", (t) => {
  // 全角 19 文字と、半角の多い題
  const warnings = warningsOf(
    t,
    "# あいうえおかきくけこさしすせそたちつて\n\n---\n\n# Contrastive learning for images\n",
  );
  assert.deepEqual(warnings, []);
});

test("表紙と章の扉の題は、長くても警告を出さない", (t) => {
  const warnings = warningsOf(
    t,
    `<!-- _class: title -->\n# ${LONG}\n\n---\n\n<!-- _class: section -->\n# ${LONG}\n`,
  );
  assert.deepEqual(warnings, []);
});

test("最初の要素でない h1 と、h2 には警告を出さない", (t) => {
  const warnings = warningsOf(t, `本文\n\n# ${LONG}\n\n---\n\n## ${LONG}\n`);
  assert.deepEqual(warnings, []);
});

test("small-text のスライドは、文字が小さい分だけ長い題を許す", (t) => {
  const medium = "あいうえおかきくけこさしすせそたちつてとなにぬ";
  assert.equal(warningsOf(t, `# ${medium}\n`).length, 1);
  t.mock.restoreAll();
  assert.deepEqual(warningsOf(t, `<!-- _class: small-text -->\n# ${medium}\n`), []);
});
