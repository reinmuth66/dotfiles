const test = require("node:test");
const assert = require("node:assert/strict");
const { Marp } = require("@marp-team/marp-core");
const container = require("./container.js");

const render = (markdown) => new Marp({ html: true }).use(container).render(markdown).html;

test("::: を class 付きの div にし、中の Markdown を変換する", () => {
  const html = render("::: card accent\n本文\n\n- 項目\n- **太字**\n:::\n");
  assert.match(html, /<div class="card accent">\s*<p>本文<\/p>/);
  assert.match(html, /<li>項目<\/li>/);
  assert.match(html, /<strong>太字<\/strong>/);
});

test("#name で id を付ける", () => {
  const html = render("::: box dark #model\nモデル\n:::\n");
  assert.match(html, /<div class="box dark" id="model">/);
});

test("入れ子にできる", () => {
  const html = render("::: row\n::: box\nA\n:::\n::: box\nB\n:::\n:::\n");
  assert.match(
    html,
    /<div class="row">\s*<div class="box">\s*<p>A<\/p>\s*<\/div>\s*<div class="box">\s*<p>B<\/p>\s*<\/div>\s*<\/div>/,
  );
});

test("段落の直後でも始められる", () => {
  const html = render("前の文\n::: card\n中\n:::\n");
  assert.match(html, /<p>前の文<\/p>\s*<div class="card">/);
});

test("閉じ忘れは div を作らず、文字として残す", () => {
  const html = render("::: card\n本文\n\n---\n\n# 次のスライド\n");
  assert.doesNotMatch(html, /<div class="card">/);
  assert.match(html, /::: card/);
  // 次のスライドが飲み込まれていない
  assert.equal(html.match(/<section/g).length, 2);
});

test("コードブロックの中の ::: は変換しない", () => {
  const html = render("```\n::: card\n本文\n:::\n```\n");
  assert.doesNotMatch(html, /<div class="card">/);
});

test("部品の中のコードブロックにある ::: で閉じない", () => {
  const html = render("::: card\n```\n:::\n```\n後ろ\n:::\n");
  assert.match(html, /<div class="card">[\s\S]*<p>後ろ<\/p>\s*<\/div>/);
});

test("名前が英字で始まらなければ変換しない", () => {
  const html = render("::: 123\n本文\n:::\n");
  assert.doesNotMatch(html, /<div class="123">/);
});
