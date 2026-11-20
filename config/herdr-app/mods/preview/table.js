// CSV と TSV を Markdown の表に直す。プレビューで表として見せるために使う。herdr には依存しない。

// 表に出す行数の上限 (見出しを除く)。超えた分は切る
export const TABLE_MAX_ROWS = 300;

// 区切り文字 (sep) で分けた行とセルにする。RFC 4180 の引用符を扱う。
// 引用符の中の sep と改行はセルの中身で、"" は " 1 文字。行の区切りは \r\n と \n。最後の空行は捨てる
export function parseDelimited(text, sep) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c !== '"') field += c;
      else if (text[i + 1] === '"') {
        field += '"';
        i++;
      } else quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === sep) {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else field += c;
  }
  // 改行で終わらない最後の行。終わっていれば field も row も空で、何も足さない
  if (field !== "" || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

const cell = (s) => s.replace(/\|/g, "\\|").replace(/\r\n|\r|\n/g, " ");

// 1 行目を見出しにした Markdown の表にする。列の数は全部の行の最大に揃え、足りないセルは空。
// 見出しを除いて maxRows 行を超えたら切り、truncated を真にする
export function toMarkdownTable(rows, maxRows) {
  // 展開 (...) すると行が多いファイルで呼び出しの上限を超えるので、reduce で数える
  const width = rows.reduce((m, r) => Math.max(m, r.length), 0);
  if (width === 0) return { markdown: "", truncated: false };
  const line = (r) => `| ${Array.from({ length: width }, (_, i) => cell(r[i] ?? "")).join(" | ")} |\n`;
  const [head, ...body] = rows;
  const shown = body.slice(0, maxRows);
  const markdown = line(head) + `|${"---|".repeat(width)}\n` + shown.map(line).join("");
  return { markdown, truncated: body.length > maxRows };
}
