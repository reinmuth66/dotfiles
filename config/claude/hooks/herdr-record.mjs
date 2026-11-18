// Claude Code の hook。行動、編集の前後、サブエージェントを herdr-app の data/ に書き出す。
// 読む側は herdr-app の mod (workspace、preview)。形は設計書の「データの受け渡し」。
// Claude Code を止めないよう、標準出力には何も出さず、どんな例外でも終了コード 0 で終わる
import { mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
const MAX_ACTIONS = 20;
const MAX_EDITS = 10;
const MAX_DONE_SUBAGENTS = 10;
const MAX_COMMAND = 120;
const MAX_EDIT_BYTES = 900 * 1024;
const LOCK_WAIT_MS = 50;
const LOCK_GIVE_UP_MS = 2000;
const LOCK_STALE_MS = 60_000;

const KINDS = {
  Edit: "edit",
  MultiEdit: "edit",
  NotebookEdit: "edit",
  Write: "write",
  Read: "read",
  Grep: "search",
  Glob: "search",
  WebSearch: "web",
  WebFetch: "web",
  Bash: "bash",
};

export function kindOf(toolName) {
  return Object.hasOwn(KINDS, toolName) ? KINDS[toolName] : "other";
}

const str = (v) => (typeof v === "string" ? v : null);

// 前後の中身。中身を読めなければ null を入れる (サイズの判定は record が行う)
export function editContents(event) {
  const input = event.tool_input ?? {};
  const response = event.tool_response ?? {};
  const path = str(input.file_path);
  if (path === null) return null;
  if (event.tool_name === "Edit" || event.tool_name === "MultiEdit") {
    return { path, before: str(response.originalFile), after: readSmall(path) };
  }
  if (event.tool_name === "Write") {
    return { path, before: str(response.originalFile) ?? "", after: str(input.content) };
  }
  return null;
}

// 大きすぎるファイルは読まない。上限を超えたことは TOO_LARGE で伝える
const TOO_LARGE = Symbol("too large");
function readSmall(path) {
  try {
    if (statSync(path).size > MAX_EDIT_BYTES) return TOO_LARGE;
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function writeJson(path, value) {
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}.${Math.random().toString(36).slice(2)}.tmp`);
  try {
    writeFileSync(tmp, JSON.stringify(value));
    renameSync(tmp, path);
  } catch (e) {
    rmSync(tmp, { force: true });
    throw e;
  }
}

function readJsonOr(path, fallback) {
  try {
    const v = JSON.parse(readFileSync(path, "utf8"));
    return v && typeof v === "object" && !Array.isArray(v) ? v : fallback;
  } catch {
    return fallback;
  }
}

function acquire(lock) {
  const start = Date.now();
  for (;;) {
    try {
      mkdirSync(lock);
      return true;
    } catch (e) {
      if (e.code !== "EEXIST") throw e;
    }
    try {
      if (Date.now() - statSync(lock).mtimeMs > LOCK_STALE_MS) {
        rmSync(lock, { recursive: true, force: true });
        continue;
      }
    } catch {
      continue; // 調べる間に外れた
    }
    if (Date.now() - start >= LOCK_GIVE_UP_MS) return false;
    sleep(LOCK_WAIT_MS);
  }
}

const emptyActivity = (id, event) => ({
  terminal: id,
  session_id: str(event.session_id),
  cwd: str(event.cwd),
  actions: [],
  edits: [],
  subagents: [],
});

function loadActivity(path, id, event) {
  const a = readJsonOr(path, null) ?? emptyActivity(id, event);
  return {
    terminal: id,
    session_id: str(event.session_id) ?? a.session_id ?? null,
    cwd: str(event.cwd) ?? a.cwd ?? null,
    actions: Array.isArray(a.actions) ? a.actions : [],
    edits: Array.isArray(a.edits) ? a.edits.filter(Number.isInteger) : [],
    subagents: Array.isArray(a.subagents) ? a.subagents : [],
  };
}

function seqFiles(dir) {
  try {
    return readdirSync(dir)
      .map((f) => /^(\d+)\.json$/.exec(f))
      .filter(Boolean)
      .map((m) => Number(m[1]));
  } catch {
    return [];
  }
}

function recordTool(activity, event, editsDir, now) {
  const input = event.tool_input ?? {};
  const tool = str(event.tool_name) ?? "";
  const command = tool === "Bash" && typeof input.command === "string" ? input.command.split("\n")[0].slice(0, MAX_COMMAND) : null;
  const path = str(input.file_path) ?? str(input.notebook_path) ?? null;
  activity.actions = [{ at: now, tool, kind: kindOf(tool), path, command }, ...activity.actions].slice(0, MAX_ACTIONS);

  const contents = editContents(event);
  if (contents === null) return;
  const seq = Math.max(0, ...activity.edits, ...seqFiles(editsDir)) + 1;
  const { before, after } = contents;
  const tooLarge =
    before === TOO_LARGE ||
    after === TOO_LARGE ||
    Buffer.byteLength(before ?? "", "utf8") + Buffer.byteLength(after ?? "", "utf8") > MAX_EDIT_BYTES;
  mkdirSync(editsDir, { recursive: true });
  writeJson(join(editsDir, `${seq}.json`), {
    seq,
    at: now,
    path: contents.path,
    before: tooLarge ? null : before,
    after: tooLarge ? null : after,
    too_large: tooLarge,
  });
  activity.edits = [seq, ...activity.edits].slice(0, MAX_EDITS);
  const keep = new Set(activity.edits);
  for (const s of seqFiles(editsDir)) if (!keep.has(s)) rmSync(join(editsDir, `${s}.json`), { force: true });
}

function recordSubagent(activity, event, now) {
  const id = str(event.agent_id);
  if (id === null) return;
  const type = str(event.agent_type);
  if (event.hook_event_name === "SubagentStart") {
    activity.subagents = [
      { id, type, status: "working", started_at: now, ended_at: null },
      ...activity.subagents.filter((s) => s.id !== id),
    ];
  } else {
    const s = activity.subagents.find((x) => x.id === id);
    if (!s) return;
    Object.assign(s, { status: "done", ended_at: now, type: s.type ?? type });
  }
  let done = 0;
  activity.subagents = activity.subagents.filter((s) => s.status !== "done" || ++done <= MAX_DONE_SUBAGENTS);
}

export function record(event, env, now) {
  try {
    if (!event || typeof event !== "object") return;
    const id = env.HC_TERMINAL_ID;
    if (typeof id !== "string" || !ID_PATTERN.test(id)) return;
    const name = event.hook_event_name;
    const isReset = name === "SessionStart" && (event.source === "startup" || event.source === "clear");
    if (!isReset && name !== "PostToolUse" && name !== "SubagentStart" && name !== "SubagentStop") return;

    const data = join(env.HERDR_APP_HOME || join(env.HOME, ".config/herdr-app"), "data");
    const activityDir = join(data, "activity");
    const activityPath = join(activityDir, `${id}.json`);
    const editsDir = join(data, "edits", id);
    mkdirSync(activityDir, { recursive: true });

    const lock = join(activityDir, `.${id}.lock`);
    if (!acquire(lock)) return;
    try {
      if (isReset) {
        rmSync(editsDir, { recursive: true, force: true });
        writeJson(activityPath, emptyActivity(id, event));
        return;
      }
      const activity = loadActivity(activityPath, id, event);
      if (name === "PostToolUse") recordTool(activity, event, editsDir, now);
      else recordSubagent(activity, event, now);
      writeJson(activityPath, activity);
    } finally {
      rmSync(lock, { recursive: true, force: true });
    }
  } catch {
    // Claude Code を止めない
  }
}

function isMain() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  try {
    record(JSON.parse(readFileSync(0, "utf8")), process.env, Date.now());
  } catch {
    // 壊れた入力も無視する
  }
  process.exitCode = 0;
}
