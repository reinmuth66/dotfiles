// `::: 名前 修飾... #id` 〜 `:::` を `<div class="名前 修飾..." id="id">` にする。
// 中は Markdown のまま書け、入れ子にできる。閉じる `:::` がなければ、何もせず文字として残す。

const OPEN = /^:::[ \t]*([A-Za-z][\w-]*(?:[ \t]+[A-Za-z][\w-]*)*)(?:[ \t]+#([A-Za-z][\w-]*))?[ \t]*$/;
const OPEN_ANY = /^:::[ \t]*\S/;
const CLOSE = /^:::[ \t]*$/;
const FENCE = /^(`{3,}|~{3,})(.*)$/;
// スライドの区切り (水平線)。部品はスライドをまたげない
const RULE = /^([-*_])(?:[ \t]*\1){2,}[ \t]*$/;

const container = (md) => {
  md.block.ruler.before(
    "fence",
    "modern_container",
    (state, startLine, endLine, silent) => {
      // 4 つ以上の字下げはコードブロック
      if (state.sCount[startLine] - state.blkIndent >= 4) return false;

      const lineAt = (line) =>
        state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line]);

      const match = OPEN.exec(lineAt(startLine));
      if (!match) return false;

      // 対応する閉じの行を探す。コードブロックの中の ::: は数えない
      let depth = 1;
      let fence = null;
      let closeLine = -1;
      for (let line = startLine + 1; line < endLine; line++) {
        const text = lineAt(line);

        // 字下げが浅くなったら、囲んでいるブロック (リストなど) の外。そこから先では閉じない
        if (text !== "" && state.sCount[line] < state.blkIndent) break;

        // 4 つ以上の字下げは、コードか前の行の続き。記法としては読まない
        const indented = state.sCount[line] - state.blkIndent >= 4;
        const fenceMatch = indented ? null : FENCE.exec(text);

        if (fence) {
          // 閉じは、同じ記号が開きと同じ数以上あり、後ろに何もない行
          if (
            fenceMatch &&
            fenceMatch[1][0] === fence[0] &&
            fenceMatch[1].length >= fence.length &&
            fenceMatch[2].trim() === ""
          ) {
            fence = null;
          }
          continue;
        }
        if (indented) continue;

        // ``` の後ろに ` がある行 (```code``` など) は、コードブロックの始まりではない
        if (fenceMatch && !(fenceMatch[1][0] === "`" && fenceMatch[2].includes("`"))) {
          fence = fenceMatch[1];
        } else if (RULE.test(text)) {
          break;
        } else if (CLOSE.test(text)) {
          depth -= 1;
          if (depth === 0) {
            closeLine = line;
            break;
          }
        } else if (OPEN_ANY.test(text)) {
          depth += 1;
        }
      }
      if (closeLine < 0) return false;
      if (silent) return true;

      const open = state.push("modern_container_open", "div", 1);
      open.block = true;
      open.map = [startLine, closeLine + 1];
      open.attrSet("class", match[1].trim().split(/[ \t]+/).join(" "));
      if (match[2]) open.attrSet("id", match[2]);

      const oldParent = state.parentType;
      const oldLineMax = state.lineMax;
      state.parentType = "modern_container";
      state.lineMax = closeLine;
      state.md.block.tokenize(state, startLine + 1, closeLine);
      state.parentType = oldParent;
      state.lineMax = oldLineMax;

      state.push("modern_container_close", "div", -1).block = true;
      state.line = closeLine + 1;
      return true;
    },
    { alt: ["paragraph", "reference", "blockquote", "list"] },
  );
};

module.exports = container;
