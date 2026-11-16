// スライドの題 (最初の `#`) が 1 行に収まらない見込みのとき、変換のときに警告を出す。
// 題は 1 行の前提で場所を取ってあり、2 行になると本文に重なる。
// 幅は文字数から見積もる (全角は 1 文字、半角はおよそ半分)。実際の幅とは少しずれる。

// 題に使える幅は、全角でおよそ 19 文字 (スライドの幅 1280 から左右の余白を引き、題の大きさ 62 で割った数)
const LIMIT = 19;
// 文字の多いスライド (small-text) は、文字が 0.72 倍になる
const SMALL_TEXT_SCALE = 0.72;
// 題を左上に置かないスライド。表紙と章の扉は中央に置き、折り返してもよい
const SKIP = ["title", "section", "no-header"];

const classesOf = (token) => (token.attrGet("class") || "").split(/\s+/);

const plainText = (inline) =>
  (inline.children || [])
    .filter((child) => child.type === "text" || child.type === "code_inline")
    .map((child) => child.content)
    .join("");

// 全角の文字数に直した幅
const widthOf = (text) => {
  let width = 0;
  for (const char of text) width += /[ -~｡-ﾟ]/.test(char) ? 0.55 : 1;
  return width;
};

const title = (md) => {
  md.core.ruler.push("modern_title", (state) => {
    if (state.inlineMode) return;

    let page = 0;
    for (let i = 0; i < state.tokens.length; i++) {
      const slide = state.tokens[i];
      if (slide.type !== "marpit_slide_open") continue;
      page += 1;

      const classes = classesOf(slide);
      if (SKIP.some((name) => classes.includes(name))) continue;

      // 題は、スライドの最初の要素である h1
      let first = i + 1;
      while (state.tokens[first] && state.tokens[first].hidden) first += 1;
      const heading = state.tokens[first];
      if (!heading || heading.type !== "heading_open" || heading.tag !== "h1") continue;

      const text = plainText(state.tokens[first + 1]);
      const limit = classes.includes("small-text") ? LIMIT / SMALL_TEXT_SCALE : LIMIT;
      const width = widthOf(text);
      if (width > limit) {
        console.warn(
          `[modern] スライド ${page} の題「${text}」は 1 行に収まらない見込みです (全角で約 ${Math.ceil(width)} 文字分。目安は ${Math.floor(limit)} 文字まで)。2 行になると本文に重なるので、短くしてください。`,
        );
      }
    }
  });
};

module.exports = title;
