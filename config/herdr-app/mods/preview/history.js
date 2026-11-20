// Claude Code のセッション jsonl の行から、道具の呼び出しの履歴 (作業履歴) を作る。herdr には依存しない。

// tool_result の content (文字列か {type:"text", text} の配列) を 1 つの文字にする
function textOf(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((c) => (typeof c === "string" ? c : c && typeof c.text === "string" ? c.text : ""))
    .join("\n");
}

// toolUseResult が物なら patch と filePath を取る。文字列などのときは何もない
function patchOf(tur) {
  const isObj = tur !== null && typeof tur === "object" && !Array.isArray(tur);
  return {
    patch: isObj && Array.isArray(tur.structuredPatch) ? tur.structuredPatch : null,
    filePath: isObj && typeof tur.filePath === "string" ? tur.filePath : null,
  };
}

// 行 (JSON の文字列) を足していく履歴。entries は呼び出しの順。
// 結果が呼び出しより先に来ても結べるように、結びつかない結果は id ごとに預かる
export function createHistory() {
  const entries = [];
  const byId = new Map();
  const pending = new Map();

  function attach(entry, result) {
    entry.result = result;
  }

  function add(lines) {
    let changed = false;
    for (const line of lines) {
      let rec;
      try {
        rec = JSON.parse(line);
      } catch {
        continue;
      }
      if (!rec || typeof rec !== "object" || rec.isSidechain === true) continue;
      const content = rec.message?.content;
      if (!Array.isArray(content)) continue;
      for (const item of content) {
        if (!item || typeof item !== "object") continue;
        if (rec.type === "assistant" && item.type === "tool_use" && typeof item.id === "string") {
          if (byId.has(item.id)) continue;
          const entry = { id: item.id, name: String(item.name ?? ""), input: item.input ?? {}, result: null };
          entries.push(entry);
          byId.set(item.id, entry);
          if (pending.has(item.id)) {
            attach(entry, pending.get(item.id));
            pending.delete(item.id);
          }
          changed = true;
        } else if (rec.type === "user" && item.type === "tool_result" && typeof item.tool_use_id === "string") {
          const result = { text: textOf(item.content), isError: item.is_error === true, ...patchOf(rec.toolUseResult) };
          const entry = byId.get(item.tool_use_id);
          if (entry) attach(entry, result);
          else pending.set(item.tool_use_id, result);
          changed = true;
        }
      }
    }
    return changed;
  }

  return { add, entries };
}

// patch の行の先頭の + と - の数を数えて "+3 -1" にする
function countChanges(patch) {
  let plus = 0;
  let minus = 0;
  for (const hunk of patch) {
    for (const l of hunk.lines ?? []) {
      if (l.startsWith("+")) plus++;
      else if (l.startsWith("-")) minus++;
    }
  }
  return `+${plus} -${minus}`;
}

// 一覧の 1 行に出す道具名と要点
export function summary(entry) {
  const { name, input = {} } = entry;
  const str = (v) => (typeof v === "string" ? v : "");
  switch (name) {
    case "Bash":
      return { name, detail: str(input.command).split("\n")[0] };
    case "Read":
    case "Write":
      return { name, detail: str(input.file_path) };
    case "Edit": {
      const path = str(input.file_path);
      const patch = entry.result?.patch;
      return { name, detail: patch ? `${path} ${countChanges(patch)}` : path };
    }
    case "Grep":
    case "Glob":
      return { name, detail: str(input.pattern) };
    case "WebSearch":
      return { name, detail: str(input.query) };
    case "Agent":
      return { name, detail: [str(input.subagent_type), str(input.description)].filter(Boolean).join(" ") };
    default:
      return { name, detail: "" };
  }
}

// ファイルを開く道具 (Read、Edit、Write) のパス。ほかは null
export function filePathOf(entry) {
  if (!["Read", "Edit", "Write"].includes(entry.name)) return null;
  const p = entry.input?.file_path;
  return typeof p === "string" && p ? p : null;
}
