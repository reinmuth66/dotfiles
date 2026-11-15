// 章の扉 (class: section) の見出しに番号を振り、次の扉までのスライドのフッターに「番号. 章名」を入れる。
// 章の扉そのものと、表紙 (class: title) には入れない。スライドが自分でフッターを書いていれば、それを優先する。

const classesOf = (token) => (token.attrGet("class") || "").split(/\s+/);

// 見出しの中身から、文字だけを取り出す
const plainText = (inline) =>
  (inline.children || [])
    .filter((child) => child.type === "text" || child.type === "code_inline")
    .map((child) => child.content)
    .join("");

const section = (md) => {
  // marpit_header_and_footer も同じ規則の直後に入るので、後から登録したこちらが先に走る
  md.core.ruler.after("marpit_directives_apply", "modern_section", (state) => {
    if (state.inlineMode) return;

    let count = 0;
    let footer = null;

    for (let i = 0; i < state.tokens.length; i++) {
      const slide = state.tokens[i];
      if (slide.type !== "marpit_slide_open") continue;

      const classes = classesOf(slide);

      if (classes.includes("section")) {
        // このスライドの最初の見出しを章名にする
        let heading = null;
        for (let j = i + 1; j < state.tokens.length; j++) {
          if (state.tokens[j].type === "marpit_slide_close") break;
          if (state.tokens[j].type === "heading_open") {
            heading = state.tokens[j + 1];
            break;
          }
        }

        if (heading) {
          const children = heading.children || [];
          const numbered = children.some(
            (child) => child.type === "html_inline" && child.content.includes("toc-num"),
          );

          if (numbered) {
            // 番号を手で書いてある。番号の後ろに空白を入れて、フッターの文字にする
            const text = plainText(heading);
            const manual = /^(\d+)\.\s*(.*)$/.exec(text);
            footer = manual ? `${manual[1]}. ${manual[2]}` : text;
            if (manual) count = Number(manual[1]);
          } else {
            count += 1;
            const title = plainText(heading);
            const number = new state.Token("html_inline", "", 0);
            number.content = `<span class="toc-num">${count}.</span>`;
            heading.children = [number, ...children];
            footer = `${count}. ${title}`;
          }
        }
      }

      // 章の扉そのものと表紙には入れない
      if (footer === null || classes.includes("title") || classes.includes("section")) continue;

      // 空のフッター (<!-- _footer: "" -->) も、スライドが自分で決めたものとして残す
      // marpit は空のフッターを meta.marpitFooter に入れないので、指定の有無は directive で見る
      slide.meta = slide.meta || {};
      const directives = slide.meta.marpitDirectives || {};
      if (directives.footer === undefined) slide.meta.marpitFooter = footer;
    }
  });
};

module.exports = section;
