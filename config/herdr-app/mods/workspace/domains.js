// 状態の表示の詳しい作業内容。data/activity/<id>.json の actions (新しい順) から、
// 分野の札と 2 行目の文を作る

const isWrite = (a) => a.kind === "edit" || a.kind === "write";
const pathOf = (a) => (typeof a.path === "string" ? a.path : "");
const commandOf = (a) => (typeof a.command === "string" ? a.command : "");

// 差し替えられる表。前から順に当て、最初に当たった札をその作業の札にする
export const DOMAIN_RULES = [
  { tag: "design", test: (a) => isWrite(a) && /\/config\/design-system\//.test(pathOf(a)) },
  { tag: "docs", test: (a) => isWrite(a) && (/\/docs\//.test(pathOf(a)) || pathOf(a).endsWith(".md")) },
  { tag: "nix", test: (a) => isWrite(a) && pathOf(a).endsWith(".nix") },
  {
    tag: "test",
    test: (a) => a.kind === "bash" && /\b(node --test|nix flake check|pytest|cargo test|npm test|go test)\b/.test(commandOf(a)),
  },
];

const RECENT = 8;
const RESEARCH_MIN = 3;
const LOOKING = new Set(["read", "search", "web"]);

// 新しい 8 件で、当たった札の一番多いもの (同数なら新しいほう)。
// 当たる札がなく、新しい 3 件以上がすべて読むだけなら research。それもなければ null
export function domainTag(actions, rules = DOMAIN_RULES) {
  if (!Array.isArray(actions)) return null;
  const recent = actions.slice(0, RECENT);
  const counts = new Map(); // 札 → { n, newest (小さいほど新しい) }
  recent.forEach((a, i) => {
    const rule = rules.find((r) => r.test(a));
    if (!rule) return;
    const c = counts.get(rule.tag);
    if (c) c.n += 1;
    else counts.set(rule.tag, { n: 1, newest: i });
  });
  let best = null;
  for (const [tag, c] of counts) {
    if (!best || c.n > best.n || (c.n === best.n && c.newest < best.newest)) best = { tag, ...c };
  }
  if (best) return best.tag;
  const head = actions.slice(0, RESEARCH_MIN);
  if (head.length >= RESEARCH_MIN && head.every((a) => LOOKING.has(a.kind))) return "research";
  return null;
}

const baseName = (path) => path.split("/").filter(Boolean).pop() ?? "";
const COMMAND_MAX = 40;

// 2 行目の文。出すものがなければ null
export function describe(action) {
  if (!action) return null;
  const path = pathOf(action);
  switch (action.kind) {
    case "edit":
    case "write":
      return path ? `${baseName(path)} を編集` : null;
    case "read":
      return path ? `${baseName(path)} を読む` : null;
    case "bash": {
      const command = commandOf(action).trim();
      return command ? `${[...command].slice(0, COMMAND_MAX).join("")} を実行` : null;
    }
    case "web":
      return "Web を検索";
    case "search":
      return "ファイルを検索";
    default:
      return null;
  }
}
