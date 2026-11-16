const test = require("node:test");
const assert = require("node:assert/strict");
const { Marp } = require("@marp-team/marp-core");
const container = require("./container.js");
const diagram = require("./diagram.js");

const SCRIPT = "/* connector */";
const render = (markdown) =>
  new Marp({ html: true })
    .use(container)
    .use(diagram, { script: SCRIPT })
    .render(markdown).html;

const edgesOf = (html) => {
  const match = /data-edges="([^"]*)"/.exec(html);
  if (!match) return null;
  return JSON.parse(match[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&"));
};

const boxes = "::: box #in\n入力\n:::\n::: box #model\nモデル\n:::\n";

test("図の中の線の記法を data-edges に移し、本文から消す", () => {
  const html = render(`::: diagram\n${boxes}\nin.right -> model.left\nmodel -- in : 戻す\n:::\n`);
  const edges = edgesOf(html);
  assert.equal(edges.length, 2);
  assert.equal(edges[0].from, "in");
  assert.equal(edges[0].toSide, "left");
  assert.equal(edges[1].kind, "line");
  assert.equal(edges[1].label, "戻す");
  assert.doesNotMatch(html, /-&gt;/);
});

test("図の外の a -> b は文字のまま残す", () => {
  const html = render(`in -> model\n\n::: diagram\n${boxes}:::\n`);
  assert.match(html, /<p>in -&gt; model<\/p>/);
  assert.equal(edgesOf(html), null);
});

test("図の中でも、コードブロックの a -> b は文字のまま残す", () => {
  const html = render(`::: diagram\n${boxes}\n\`\`\`\nin -> model\n\`\`\`\n:::\n`);
  assert.equal(edgesOf(html), null);
  assert.match(html, /in -&gt; model/);
});

test("記法でない行が混ざった段落は、文字のまま残す", () => {
  const html = render(`::: diagram\n${boxes}\nin -> model\nこれは説明の文\n:::\n`);
  assert.equal(edgesOf(html), null);
  assert.match(html, /これは説明の文/);
});

test("存在しない名前を指す線は描かず、警告を出す", (t) => {
  const warn = t.mock.method(console, "warn", () => {});
  const html = render(`::: diagram\n${boxes}\nin -> model\nin -> nowhere\n:::\n`);
  const edges = edgesOf(html);
  assert.equal(edges.length, 1);
  assert.equal(edges[0].to, "model");
  assert.equal(warn.mock.callCount(), 1);
  assert.match(warn.mock.calls[0].arguments[0], /nowhere/);
});

test("box の中身が線の形をしていても、中身として残す", () => {
  const html = render("::: diagram\n::: box #a\nx -> y\n:::\n::: box #b\nB\n:::\n\na -> b\n:::\n");
  assert.match(html, /<div class="box" id="a">\s*<p>x -&gt; y<\/p>/);
  assert.equal(edgesOf(html).length, 1);
});

test("箇条書きの中の a -> b は、文字のまま残す", () => {
  const html = render(`::: diagram\n${boxes}\n- in -> model\n:::\n`);
  assert.match(html, /<li>in -&gt; model<\/li>/);
  assert.equal(edgesOf(html), null);
});

test("1 本も描けない段落は、文字のまま残す", (t) => {
  t.mock.method(console, "warn", () => {});
  const html = render(`::: diagram\n${boxes}\nfoo -> bar\n:::\n`);
  assert.match(html, /<p>foo -&gt; bar<\/p>/);
  assert.equal(edgesOf(html), null);
});

test("HTML で書いた要素の id も、名前として使える", () => {
  const html = render(
    '::: diagram\n<div class="box" id="raw">生</div>\n\n::: box #in\n入力\n:::\n\nraw -> in\n:::\n',
  );
  assert.equal(edgesOf(html).length, 1);
});

test("名前は、同じ図の中だけで探す", (t) => {
  const warn = t.mock.method(console, "warn", () => {});
  const html = render(
    `::: diagram\n::: box #a\nA\n:::\n:::\n\n---\n\n::: diagram\n::: box #b\nB\n:::\n\na -> b\n:::\n`,
  );
  assert.equal(edgesOf(html), null);
  assert.equal(warn.mock.callCount(), 1);
});

test("スクリプトは、図があるときだけ、文書に 1 回だけ入れる", () => {
  const one = `::: diagram\n${boxes}\nin -> model\n:::\n`;
  const two = render(`${one}\n---\n\n${one}`);
  assert.equal(two.split(SCRIPT).length - 1, 1);
  assert.match(two, /<script>\/\* connector \*\/<\/script>/);

  // marp 自身も <script> を出すので、こちらが入れた中身の有無で確かめる
  const none = render("# 図のないスライド\n\n本文\n");
  assert.equal(none.includes(SCRIPT), false);
});

test("線のない図には、スクリプトを入れない", () => {
  const html = render(`::: diagram\n${boxes}:::\n`);
  assert.equal(html.includes(SCRIPT), false);
});

test("文中のコードに書いた id= は、名前として数えない", (t) => {
  t.mock.method(console, "warn", () => {});
  const html = render(
    '::: diagram\n::: box #in\n入力\n:::\n\n`<div id="ghost">` と書く\n\nin -> ghost\n:::\n',
  );
  assert.equal(edgesOf(html), null);
  assert.match(html, /in -&gt; ghost/);
});

test("タグの外に書いた id= は、名前として数えない", (t) => {
  t.mock.method(console, "warn", () => {});
  const html = render('::: diagram\n::: box #in\n入力\n:::\n\n属性は id="ghost" と書く\n\nin -> ghost\n:::\n');
  assert.equal(edgesOf(html), null);
});

test("入れ子の図の中の名前は、外の図からもつなげる", () => {
  const html = render(
    "::: diagram\n::: box #a\nA\n:::\n::: diagram\n::: box #b\nB\n:::\n:::\n\na -> b\n:::\n",
  );
  assert.equal(edgesOf(html).length, 1);
});
