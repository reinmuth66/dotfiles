// セッション jsonl の追記分を読むための部品。herdr には依存しない。
// main.js は、読み終えたバイト数 (offset) と書きかけの行 (rest) を持ち、
// tailArgs のコマンドを走らせ、splitComplete(rest + stdout) の lines を履歴に渡す。

// 最後の改行までを行に分け、残り (書きかけの行) を rest に返す。空の行は捨てる
export function splitComplete(buffer) {
  const end = buffer.lastIndexOf("\n");
  if (end < 0) return { lines: [], rest: buffer };
  const lines = buffer
    .slice(0, end)
    .split("\n")
    .filter((line) => line !== "");
  return { lines, rest: buffer.slice(end + 1) };
}

// offset バイト目 (0 始まり) から最後までを読むコマンド。tail の -c +N は 1 始まり
export function tailArgs(path, offset) {
  return { cmd: "tail", args: ["-c", `+${offset + 1}`, path] };
}

// UTF-8 のバイト数。TextEncoder がなければ、コードポイントから自前で数える
export function byteLength(text) {
  if (typeof TextEncoder === "function") return new TextEncoder().encode(text).length;
  let bytes = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 0x80) bytes += 1;
    else if (c < 0x800) bytes += 2;
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length && isLowSurrogate(text.charCodeAt(i + 1))) {
      // 上位と下位のサロゲートの対は 1 つのコードポイントで 4 バイト
      bytes += 4;
      i++;
    } else bytes += 3; // 対のないサロゲートは U+FFFD (3 バイト) になる
  }
  return bytes;
}

function isLowSurrogate(c) {
  return c >= 0xdc00 && c <= 0xdfff;
}
