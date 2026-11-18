// unified diff の読み取りと、git diff の引数の組み立て。herdr には依存しない。

const HUNK = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/;

// unified diff を行ごとの { kind, old, new, text } に直す。
// ファイルの先頭の diff --git、index、---、+++ などはハンクの前の行として飛ばす。
// ハンクの中の "--- foo" は削除された "-- foo" なので、ハンクの中では中身として数える。
export function parseUnifiedDiff(text) {
  const rows = [];
  const lines = String(text ?? "").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  let inHunk = false;
  let old = 0;
  let nw = 0;
  for (const line of lines) {
    if (line.startsWith("diff --git ")) {
      inHunk = false;
      continue;
    }
    const m = HUNK.exec(line);
    if (m) {
      inHunk = true;
      old = Number(m[1]);
      nw = Number(m[2]);
      rows.push({ kind: "hunk", old: null, new: null, text: line });
      continue;
    }
    if (!inHunk || line.startsWith("\\")) continue;
    const c = line[0];
    const body = line.slice(1);
    if (c === "+") rows.push({ kind: "add", old: null, new: nw++, text: body });
    else if (c === "-") rows.push({ kind: "del", old: old++, new: null, text: body });
    else rows.push({ kind: "context", old: old++, new: nw++, text: body });
  }
  return rows;
}

// git を呼ぶ引数。edit は 2 つのファイルの比較 (--no-index は差があると終了コード 1 なので、
// 呼ぶ側は 0 と 1 を成功として扱う)。head は作業ツリーと HEAD の比較
export function diffArgs(spec) {
  if (spec.mode === "edit") {
    return { cmd: "git", args: ["diff", "--no-index", "--no-color", "--no-ext-diff", "-U3", spec.a, spec.b] };
  }
  return {
    cmd: "git",
    args: ["--no-optional-locks", "diff", ...(spec.hasHead ? ["HEAD"] : []), "--no-color", "--no-ext-diff", "--", spec.path],
    cwd: spec.root,
  };
}
