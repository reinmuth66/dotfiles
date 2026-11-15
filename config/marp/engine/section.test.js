const test = require("node:test");
const assert = require("node:assert/strict");
const { Marp } = require("@marp-team/marp-core");
const section = require("./section.js");

const render = (markdown) => new Marp({ html: true }).use(section).render(markdown).html;
const slides = (html) => html.split(/(?=<section)/).filter((part) => part.startsWith("<section"));
const footer = (slide) => (/<footer>([\s\S]*?)<\/footer>/.exec(slide) || [])[1];

const deck = [
  "<!-- _class: title -->\n# 表紙",
  "# 前置き",
  "<!-- _class: section -->\n## 研究背景",
  "# 本文 1",
  "# 本文 2",
  "<!-- _class: section -->\n## 手法",
  "# 本文 3",
].join("\n\n---\n\n");

test("章の扉の見出しに番号を振る", () => {
  const s = slides(render(deck));
  assert.match(s[2], /<h2[^>]*><span class="toc-num">1\.<\/span>研究背景<\/h2>/);
  assert.match(s[5], /<h2[^>]*><span class="toc-num">2\.<\/span>手法<\/h2>/);
});

test("章の扉の後から次の扉の前まで、フッターに番号と章名を入れる", () => {
  const s = slides(render(deck));
  assert.equal(footer(s[3]), "1. 研究背景");
  assert.equal(footer(s[4]), "1. 研究背景");
  assert.equal(footer(s[6]), "2. 手法");
});

test("章の扉そのものには入れない", () => {
  const s = slides(render(deck));
  assert.equal(footer(s[2]), undefined);
  assert.equal(footer(s[5]), undefined);
});

test("空のフッターを書いたスライドには入れない", () => {
  const s = slides(render(`${deck}\n\n---\n\n<!-- _footer: "" -->\n# 本文 4`));
  assert.equal(footer(s[7]), undefined);
});

test("章の扉より前のスライドと表紙には入れない", () => {
  const s = slides(render(deck));
  assert.equal(footer(s[0]), undefined);
  assert.equal(footer(s[1]), undefined);
});

test("表紙は、章の途中にあってもフッターを入れない", () => {
  const s = slides(render(`${deck}\n\n---\n\n<!-- _class: title -->\n# 終わり`));
  assert.equal(footer(s[7]), undefined);
});

test("スライドが自分で書いたフッターを優先する", () => {
  const s = slides(render(`${deck}\n\n---\n\n<!-- _footer: 別の文字 -->\n# 本文 4`));
  assert.equal(footer(s[7]), "別の文字");
});

test("章の扉が 1 枚もなければ、何も足さない", () => {
  const html = render("# 1 枚目\n\n---\n\n# 2 枚目");
  assert.doesNotMatch(html, /<footer>/);
  assert.doesNotMatch(html, /toc-num/);
});

test("番号を手で書いた見出しは、そのまま使う", () => {
  const s = slides(
    render(
      '<!-- _class: section -->\n## <span class="toc-num">3.</span>考察\n\n---\n\n# 本文',
    ),
  );
  assert.equal(s[0].match(/class="toc-num"/g).length, 1);
  assert.equal(footer(s[1]), "3. 考察");
});

test("見出しの中の装飾は、フッターでは文字だけにする", () => {
  const s = slides(render("<!-- _class: section -->\n## **強い**見出し\n\n---\n\n# 本文"));
  assert.equal(footer(s[1]), "1. 強い見出し");
});
