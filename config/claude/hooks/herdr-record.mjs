// Claude Code の hook。行動とサブエージェントを herdr-app の data/ に書き出す。
// 読む側は herdr-app の mod (workspace)。形は設計書の「データの受け渡し」。
// Claude Code を止めないよう、標準出力には何も出さず、どんな例外でも終了コード 0 で終わる
import { lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
const MAX_ACTIONS = 20;
const MAX_DONE_SUBAGENTS = 10;
const MAX_COMMAND = 120;
const LOCK_WAIT_MS = 50;
const LOCK_GIVE_UP_MS = 2000;
const LOCK_STALE_MS = 60_000;
const STALE_DATA_MS = 7 * 24 * 60 * 60 * 1000;

const KINDS = {
  // Claude Code
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
  // Antigravity CLI (agy)
  edit_file: "edit",
  replace_file_content: "edit",
  multi_replace_file_content: "edit",
  write_file: "write",
  write_to_file: "write",
  read_file: "read",
  view_file: "read",
  view_file_outline: "read",
  view_code_item: "read",
  grep_search: "search",
  find_by_name: "search",
  list_dir: "search",
  search_web: "web",
  read_url_content: "web",
  run_command: "bash",
};

export function kindOf(toolName) {
  return Object.hasOwn(KINDS, toolName) ? KINDS[toolName] : "other";
}

const str = (v) => (typeof v === "string" ? v : null);

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function writeJson(path, value) {
  writeText(path, JSON.stringify(value));
}

function writeText(path, text) {
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}.${Math.random().toString(36).slice(2)}.tmp`);
  try {
    writeFileSync(tmp, text);
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
        // 名前を変えてから消す。消す前に他の誰かが取り直した新しいロックを消さないため。
        // rename に失敗したら、他の誰かが先に片付けたので取り直す
        const stale = `${lock}.stale.${process.pid}.${Math.random().toString(36).slice(2)}`;
        renameSync(lock, stale);
        rmSync(stale, { recursive: true, force: true });
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
  subagents: [],
});

function loadActivity(path, id, event) {
  const a = readJsonOr(path, null) ?? emptyActivity(id, event);
  return {
    terminal: id,
    session_id: str(event.session_id) ?? a.session_id ?? null,
    cwd: str(event.cwd) ?? a.cwd ?? null,
    actions: Array.isArray(a.actions) ? a.actions : [],
    subagents: Array.isArray(a.subagents) ? a.subagents : [],
  };
}

function recordTool(activity, event, now) {
  const input = event.tool_input ?? {};
  const tool = str(event.tool_name) ?? "";
  const command = kindOf(tool) === "bash" && typeof input.command === "string" ? input.command.split("\n")[0].slice(0, MAX_COMMAND) : null;
  const path = str(input.file_path) ?? str(input.notebook_path) ?? null;
  activity.actions = [{ at: now, tool, kind: kindOf(tool), path, command }, ...activity.actions].slice(0, MAX_ACTIONS);
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

// 名前の一覧。フォルダがない、またはリンクなら空 (data/ の外をたどらない)
function namesIn(dir) {
  try {
    return lstatSync(dir).isDirectory() ? readdirSync(dir) : [];
  } catch {
    return [];
  }
}

// path が isDir の種類で、STALE_DATA_MS より古ければ消す。リンクは消さずにたどらない。
// 調べる間に他の誰かが消しても、書き直しても気にしない
function removeIfStale(path, isDir, now) {
  try {
    const st = lstatSync(path);
    if (st.isSymbolicLink() || st.isDirectory() !== isDir) return;
    if (now - st.mtimeMs <= STALE_DATA_MS) return;
    rmSync(path, { recursive: isDir, force: true });
  } catch {
    // 他の誰かが先に消した
  }
}

const terminalOfJson = (name) => (name.endsWith(".json") ? name.slice(0, -".json".length) : null);

// 端末の ID は使い回されないので、終わった端末の activity、sessions (statusline.sh が書く) は
// 残り続ける。新しいセッションの始まりに、7 日より古いものを、他の端末の分も含めて消す (今の端末は除く)。
// activity は、その端末のロックを 1 回だけ試し、取れたときだけ消す (取れなければ次の機会に)
function pruneStale(data, id, now) {
  const activityDir = join(data, "activity");
  const terminals = new Set(namesIn(activityDir).map(terminalOfJson));
  for (const term of terminals) {
    if (term === null || term === id || !ID_PATTERN.test(term)) continue;
    const lock = join(activityDir, `.${term}.lock`);
    try {
      mkdirSync(lock);
    } catch {
      continue;
    }
    try {
      removeIfStale(join(activityDir, `${term}.json`), false, now);
    } finally {
      rmSync(lock, { recursive: true, force: true });
    }
  }
  const sessionsDir = join(data, "sessions");
  for (const name of namesIn(sessionsDir)) {
    const term = terminalOfJson(name);
    if (term === null || term === id || !ID_PATTERN.test(term)) continue;
    removeIfStale(join(sessionsDir, name), false, now);
  }
}

function normalizeEvent(raw) {
  if (typeof raw.hookEventName !== "string") return raw;
  const call = raw.toolCall && typeof raw.toolCall === "object" ? raw.toolCall : {};
  const args = call.args && typeof call.args === "object" ? call.args : {};
  return {
    hook_event_name: raw.hookEventName,
    session_id: raw.conversationId ?? raw.session_id,
    cwd: raw.cwd,
    source: raw.hookEventName === "SessionStart" ? "startup" : undefined,
    tool_name: call.name,
    tool_input: {
      file_path: str(args.Path) ?? str(args.TargetFile) ?? str(args.AbsolutePath),
      command: str(args.CommandLine),
    },
  };
}

export function record(rawEvent, env, now) {
  try {
    if (!rawEvent || typeof rawEvent !== "object") return;
    const event = normalizeEvent(rawEvent);
    const id = env.HC_TERMINAL_ID;
    if (typeof id !== "string" || !ID_PATTERN.test(id)) return;
    const name = event.hook_event_name;
    const isReset = name === "SessionStart" && (event.source === "startup" || event.source === "clear");
    if (!isReset && name !== "PostToolUse" && name !== "SubagentStart" && name !== "SubagentStop") return;

    const data = join(env.HERDR_APP_HOME || join(env.HOME, ".config/herdr-app"), "data");
    const activityDir = join(data, "activity");
    const activityPath = join(activityDir, `${id}.json`);
    mkdirSync(activityDir, { recursive: true });

    const lock = join(activityDir, `.${id}.lock`);
    if (!acquire(lock)) return;
    try {
      if (isReset) {
        writeJson(activityPath, emptyActivity(id, event));
      } else {
        const activity = loadActivity(activityPath, id, event);
        if (name === "PostToolUse") recordTool(activity, event, now);
        else recordSubagent(activity, event, now);
        writeJson(activityPath, activity);
      }
    } finally {
      rmSync(lock, { recursive: true, force: true });
    }
    if (isReset) pruneStale(data, id, now);
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
  let isAgy = false;
  try {
    const event = JSON.parse(readFileSync(0, "utf8"));
    isAgy = typeof event?.hookEventName === "string";
    record(event, process.env, Date.now());
  } catch {
    // 壊れた入力も無視する
  }
  if (isAgy) process.stdout.write("{}\n");
  process.exitCode = 0;
}
