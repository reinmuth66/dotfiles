// ブランチを選ぶ窓の判断。git の出力の読み取り、絞り込み、選んだときに何をするか。描画は picker.js、つなぎは main.js

export const REFS_ARGS = [
  "for-each-ref",
  "--sort=-committerdate",
  "--format=%(refname)%00%(refname:short)%00%(worktreepath)",
  "refs/heads",
  "refs/remotes",
];

const trimSlash = (path) => (path.length > 1 ? path.replace(/\/+$/, "") : path);
const baseName = (path) => trimSlash(path).split("/").pop() || path;

// 今のブランチ、手元のもの、リモートにだけあるものの順 (それぞれ受け取った順 = 新しくコミットした順)
export function parseRefs(stdout, current, root) {
  const locals = [];
  const remotes = [];
  for (const line of stdout.split("\n")) {
    if (!line) continue;
    const [ref, , wt = ""] = line.split("\0");
    if (ref.startsWith("refs/heads/")) {
      const name = ref.slice("refs/heads/".length);
      const worktree = wt && trimSlash(wt) !== trimSlash(root) ? wt : null;
      locals.push({ name, kind: "local", remote: null, current: name === current, worktree });
    } else if (ref.startsWith("refs/remotes/")) {
      const rest = ref.slice("refs/remotes/".length);
      const slash = rest.indexOf("/");
      if (slash < 0) continue;
      const remote = rest.slice(0, slash);
      const name = rest.slice(slash + 1);
      if (name === "HEAD") continue;
      remotes.push({ name, kind: "remote", remote, current: false, worktree: null });
    }
  }
  const localNames = new Set(locals.map((b) => b.name));
  const seen = new Set();
  const onlyRemote = remotes.filter((b) => {
    if (localNames.has(b.name) || seen.has(b.name)) return false;
    seen.add(b.name);
    return true;
  });
  const cur = locals.filter((b) => b.current);
  return [...cur, ...locals.filter((b) => !b.current), ...onlyRemote];
}

// 空白で区切った語がすべて名前に含まれるもの (大文字と小文字を区別しない)
export function filterBranches(branches, query) {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return branches;
  return branches.filter((b) => {
    const name = b.name.toLowerCase();
    return words.every((w) => name.includes(w));
  });
}

const isUnder = (path, root) => {
  const p = trimSlash(path);
  const r = trimSlash(root);
  return p === r || p.startsWith(r === "/" ? "/" : `${r}/`);
};

export function switchPlan({ branch, agents, root, spaces }) {
  if (branch.current) return { action: "none" };
  const busy = agents.find((a) => a.cwd && isUnder(a.cwd, root) && (a.status === "working" || a.status === "blocked"));
  if (busy) return { action: "refuse", reason: `${busy.name} が${busy.status === "blocked" ? "入力待ち" : "作業中"}です` };
  if (branch.worktree) {
    const space = spaces.find((s) => s.folder && trimSlash(s.folder) === trimSlash(branch.worktree));
    if (space) return { action: "space", id: space.id };
    return { action: "refuse", reason: `${baseName(branch.worktree)} の worktree で使われています` };
  }
  if (branch.kind === "remote") return { action: "git", args: ["switch", "--track", `${branch.remote}/${branch.name}`] };
  // - で始まる名前は git の引数として読まれる (--orphan=x など)。リモートのものは <remote>/ が前に付くので安全
  if (branch.name.startsWith("-")) return { action: "refuse", reason: `${branch.name} は切り替えられません` };
  return { action: "git", args: ["switch", branch.name] };
}

// git のエラーの最初の error: の行 (なければ最初の空でない行) から error: を除いたもの
export function failureReason(stderr) {
  const lines = String(stderr ?? "")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  const line = lines.find((l) => l.startsWith("error:")) ?? lines[0];
  if (!line) return "切り替えられませんでした";
  return line.replace(/^error:\s*/, "") || "切り替えられませんでした";
}
