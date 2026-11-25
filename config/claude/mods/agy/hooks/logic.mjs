// agy:worker の判断の部分。副作用のない関数だけを置く。register.ts が呼ぶ。
// hooks のモジュールは Node の組み込みを使えないので、POSIX の path.resolve を自前で持つ。
export function resolvePath(...segments) {
  let start = 0;
  for (let i = segments.length - 1; i >= 0; i--) {
    if (segments[i].startsWith("/")) {
      start = i;
      break;
    }
  }
  const parts = [];
  for (const seg of segments.slice(start)) {
    for (const p of seg.split("/")) {
      if (p === "" || p === ".") continue;
      if (p === "..") parts.pop();
      else parts.push(p);
    }
  }
  return `/${parts.join("/")}`;
}

export const DEFAULT_MODEL = "gemini-4-hydrogen-medium";

const DIGEST_LIMIT = 8000;

const COMMON_RULES = [
  "",
  "",
  "---",
  "次の規則を必ず守ること。",
  "- git の書き込み (add、commit、push、reset、checkout、switch、restore、rebase、merge、stash、clean、branch、tag、worktree) と gh は使わない。指示に commit するとあっても、commit は指揮役が行う。読むだけの git (status、diff、log) は使ってよい。git には -C や -c を付けない (拒否の規則に当たる)。",
  "- 作業ディレクトリの外にファイルを書かない。",
];

export const AGY_RULES = [
  ...COMMON_RULES,
  "- 完了条件のテストは走らせ、結果を digest に書く。",
  "- 返事は digest だけにする。1 行目は `Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`。続けて、変更したファイル、走らせたテストと結果、判断したこと、計画とのずれ、残った作業。大きな内容はファイルに書く。",
].join("\n");

export const REVIEW_RULES = [
  ...COMMON_RULES,
  "- あなたは確認役で、読むだけにする。作業ツリーのファイルを作らず、直さず、消さない。見つけた問題は直さずに報告する。書いてよいのは、指示に `報告ファイル:` の行があるときのその 1 つだけ。",
  "- テストは走らせ直さない。実装役と指揮役が走らせている。",
  "- 返事は digest だけにする。1 行目は、指示の雛形が決めた verdict の形で始める。続けて、指摘ごとにファイルと行、理由。指摘が無ければ、無いと書く。詳しい報告が長くなるときは `報告ファイル:` の場所に書き、digest は verdict とその場所だけにする。",
].join("\n");

const ROLES = ["implement", "review"];

const lineValue = (text, key) => {
  const m = new RegExp(`^${key}[:：][ \\t]*(.+)$`, "m").exec(text);
  if (!m) return null;
  let v = m[1].trim();
  if (v.startsWith("`") && v.endsWith("`") && v.length >= 2) v = v.slice(1, -1).trim();
  return v === "" ? null : v;
};

export function workDirFrom(delegation, sessionCwd) {
  return lineValue(delegation, "作業ディレクトリ") ?? sessionCwd;
}

export function parseWorktrees(porcelain) {
  return porcelain
    .split("\n")
    .filter((l) => l.startsWith("worktree "))
    .map((l) => l.slice("worktree ".length).trim());
}

export function isAllowedDir(dir, sessionCwd, worktrees) {
  const d = resolvePath(dir);
  return [sessionCwd, ...worktrees].some((b) => {
    const base = resolvePath(b);
    return d === base || d.startsWith(base.endsWith("/") ? base : `${base}/`);
  });
}

export function roleFrom(delegation) {
  const v = lineValue(delegation, "役");
  if (v === null) return { role: "implement" };
  if (!ROLES.includes(v)) return { error: `役の指定が不正: ${v} (${ROLES.join(" か ")})` };
  return { role: v };
}

export function reportFileFrom(delegation, workDir) {
  const v = lineValue(delegation, "報告ファイル");
  return v === null ? null : resolvePath(workDir, v);
}

export function buildPrompt(delegation, role = "implement") {
  return delegation + (role === "review" ? REVIEW_RULES : AGY_RULES);
}

export function modelFrom(delegation) {
  const v = lineValue(delegation, "モデル");
  if (v === null) return { model: DEFAULT_MODEL };
  if (!/^[a-z0-9.-]+$/.test(v)) return { error: `モデルの指定が不正: ${v}` };
  return { model: v };
}

// agy の sandbox は /nix を読めず、Nix のシェルもツールも起動できない。headless では sandbox の外で走らせる許可を聞けないので、
// --dangerously-skip-permissions で許す。permissions.deny と git-hooks はそれでも効く (2026-11-25 に確かめた)
export function buildArgv(prompt, settings, model) {
  return [
    "agy",
    "--output-format",
    "json",
    "--model",
    model,
    "--settings",
    settings,
    "--dangerously-skip-permissions",
    "--print-timeout",
    "25m",
    `--print=${prompt}`,
  ];
}

// 空の pushInsteadOf はどの URL にも当たり、どの push も agy-push-blocked: に書き換わって失敗する
export function gitHooksEnv(hooksDir) {
  return {
    GIT_CONFIG_COUNT: "2",
    GIT_CONFIG_KEY_0: "core.hooksPath",
    GIT_CONFIG_VALUE_0: hooksDir,
    GIT_CONFIG_KEY_1: "url.agy-push-blocked:.pushInsteadOf",
    GIT_CONFIG_VALUE_1: "",
  };
}

export function parseDenied(json, stderr) {
  const out = [];
  const add = (s) => {
    if (!out.includes(s)) out.push(s);
  };
  if (json && typeof json === "object") {
    if (typeof json.response === "string") {
      const re = /Permission denied for command\(([\s\S]*?)\)\. Matches user-configured deny rule\./g;
      for (const m of json.response.matchAll(re)) add(m[1]);
    }
    if (Array.isArray(json.denied_actions)) {
      for (const a of json.denied_actions) {
        if (a && typeof a === "object") add(`${a.action}: ${a.display_name}`);
      }
    }
  }
  const hasDeniedActions = json && typeof json === "object" && Array.isArray(json.denied_actions) && json.denied_actions.length > 0;
  if (!hasDeniedActions && typeof stderr === "string") {
    const line = stderr.split("\n").find((l) => l.includes("jetski: no output produced"));
    if (line) add(`stderr の知らせ: ${line.trim()}`);
  }
  return out;
}

export function refsSnapshot(head, forEachRef) {
  const lines = [`HEAD ${head.trim()}`, ...forEachRef.split("\n").map((l) => l.trim()).filter(Boolean)];
  return lines.sort().join("\n");
}

const snapshotMap = (s) => {
  const m = new Map();
  for (const l of s.split("\n")) {
    const i = l.lastIndexOf(" ");
    if (i > 0) m.set(l.slice(0, i), l.slice(i + 1));
  }
  return m;
};

// 確認役が読むだけだったかを見る。変わったファイルの path と内容の hash (消えていれば null) を、refsSnapshot と同じ形にする
export function treeSnapshot(entries) {
  return entries
    .map(({ path, hash }) => `${path} ${hash ?? "-"}`)
    .sort()
    .join("\n");
}

export function refsChanged(before, after) {
  const b = snapshotMap(before);
  const a = snapshotMap(after);
  const out = [];
  for (const name of new Set([...b.keys(), ...a.keys()])) {
    const x = b.get(name) ?? "-";
    const y = a.get(name) ?? "-";
    if (x !== y) out.push(`${name}: ${x} -> ${y}`);
  }
  return out;
}

// 報告ファイルだけは確認役が書いてよい
export function treeChanged(before, after, reportFile, workDir) {
  return refsChanged(before, after).filter((l) => reportFile === null || resolvePath(workDir, l.slice(0, l.indexOf(": "))) !== reportFile);
}

const unwrap = (v) => {
  if (typeof v !== "string") return null;
  try {
    const p = JSON.parse(v);
    if (typeof p === "string") return p;
  } catch {
    // JSON で包まれていない文字列はそのまま使う
  }
  return v;
};

export function outsideWrites(transcriptJsonl, workDir) {
  const out = [];
  for (const line of transcriptJsonl.split("\n")) {
    let row;
    try {
      row = JSON.parse(line);
    } catch {
      continue;
    }
    if (!row || !Array.isArray(row.tool_calls)) continue;
    for (const call of row.tool_calls) {
      if (!call || typeof call.name !== "string") continue;
      if (!/write|edit|replace|create|delete|move|rename/i.test(call.name)) continue;
      if (!call.args || typeof call.args !== "object") continue;
      for (const [k, raw] of Object.entries(call.args)) {
        if (!/path|file/i.test(k)) continue;
        const v = unwrap(raw);
        if (v === null || v === "") continue;
        const abs = resolvePath(workDir, v);
        if (!isAllowedDir(abs, workDir, []) && !out.includes(v)) out.push(v);
      }
    }
  }
  return out;
}

export function transcriptPath(home, conversationId) {
  return `${home}/.gemini/antigravity-cli/brain/${conversationId}/.system_generated/logs/transcript.jsonl`;
}

export function parseResult(stdout, stderr, code, signal) {
  const base = { digest: "", conversationId: null, tokens: null, denied: [], refsChanged: [], outsideWrites: [], treeChanged: [], role: "implement", detail: "" };
  if (signal) return { ...base, status: "killed", detail: `シグナル ${signal} で終了` };
  if (!stdout || stdout.trim() === "") {
    return { ...base, status: "empty", detail: (stderr ?? "").slice(-2000) };
  }
  let json;
  try {
    json = JSON.parse(stdout);
  } catch {
    return { ...base, status: "invalid-output", detail: (stderr ?? "").slice(-2000) };
  }
  if (!json || typeof json !== "object") {
    return { ...base, status: "invalid-output", detail: (stderr ?? "").slice(-2000) };
  }
  const usage = json.usage;
  const r = {
    ...base,
    digest: typeof json.response === "string" ? json.response : "",
    conversationId: typeof json.conversation_id === "string" ? json.conversation_id : null,
    tokens: usage && typeof usage === "object" ? { input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0 } : null,
    denied: parseDenied(json, stderr ?? ""),
  };
  const error = typeof json.error === "string" ? json.error : "";
  switch (json.status) {
    case "SUCCESS":
      return { ...r, status: "ok" };
    case "CANCELED":
    case "INTERRUPTED":
      return { ...r, status: "canceled", detail: error };
    case "ERROR":
    case "INVALID": {
      if (json.status === "ERROR" && /authentication/i.test(error)) return { ...r, status: "auth", detail: error };
      // 利用枠が尽きたときも exit 3 で終わるので、時間切れより先に見る
      if (/quota reached/i.test(error)) return { ...r, status: "quota", detail: error };
      const timedOut =
        json.finished_reason === "print_timeout" || /print timeout/i.test(error) || /"reason":"print_timeout"/.test(stderr ?? "") || code === 3;
      return { ...r, status: timedOut && json.status === "ERROR" ? "timeout" : "error", detail: error };
    }
    default:
      return { ...r, status: "error", detail: error || `不明な status: ${String(json.status)}` };
  }
}

export function formatReturn(r, home) {
  let digest = r.digest;
  const notes = [];
  if (digest.length > DIGEST_LIMIT) {
    digest = digest.slice(0, DIGEST_LIMIT);
    notes.push(`(digest が ${DIGEST_LIMIT} 文字を超えたので切り詰めた)`);
  }
  const warn = [];
  if (r.status !== "ok") {
    if (r.status !== "outside" && r.status !== "bad-model" && r.status !== "bad-role") {
      warn.push("ファイルが途中まで変わっている可能性がある。git status を確かめる");
    }
    if (r.detail) warn.push(r.detail);
    if (r.status === "quota") warn.push("agy の利用枠が尽きた。このあとのタスクも Claude の実装役に回す");
    if (r.status === "auth") warn.push("agy を対話で起動してログインし直す (headless の実行はブラウザを開いて 60 秒待つ)");
  }
  if (r.refsChanged.length > 0) {
    warn.push("警告: agy が git の ref か index を変えた。指示に反する。git log、git reflog、git diff --cached を確かめ、戻すかを利用者に聞く");
  }
  if (r.outsideWrites.length > 0) {
    warn.push("警告: agy がファイルのツールで作業ディレクトリの外に書いた。そのファイルを確かめる (シェルの書き込みはここに出ない)");
  }
  if (r.treeChanged.length > 0) {
    warn.push("警告: 確認役の agy が作業ツリーのファイルを変えた。読むだけの指示に反する。git status と git diff を確かめ、戻すかを利用者に聞く");
  }
  const join = (a) => (a.length > 0 ? a.join(" / ") : "-");
  const meta = [
    `status: ${r.status}`,
    `conversation: ${r.conversationId ?? "-"}`,
    `transcript: ${r.conversationId ? transcriptPath(home, r.conversationId) : "-"}`,
    `gemini_tokens: ${r.tokens ? `${r.tokens.input} / ${r.tokens.output}` : "-"}`,
    `denied: ${join(r.denied)}`,
    `refs_changed: ${join(r.refsChanged)}`,
    `outside_writes: ${join(r.outsideWrites)}`,
    ...(r.role === "review"
      ? [`tree_changed: ${join(r.treeChanged)}`, "verify: tree_changed が - であることと、digest の verdict を確かめる"]
      : ["verify: git status と git diff を確かめ、完了条件のテストを走らせ、計画書の commit を行う"]),
  ];
  return ["===DIGEST===", digest, ...notes, ...warn, "===META===", ...meta].join("\n");
}
