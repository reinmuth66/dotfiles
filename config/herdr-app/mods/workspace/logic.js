// workspace mod の一覧の組み立て。herdr に依存しない (node --test で確かめる)。
import { STATUS, STATUS_ORDER, mostUrgent, formatDuration, isRemoteAddress, isRemoteSpace } from "./ui.js";

// worktree の space (common が <top>/.git でない) を、元の space の直後に depth 1 で置く。
// 別のコンピューターの space は入れ子にしない (main.js は git を呼ばない)
export function nestSpaces(spaces, repos) {
  const repoOf = (space) => (isRemoteSpace(space) ? null : (repos[space.id] ?? null));
  const isMain = (repo) => repo.common === `${repo.top}/.git`;
  const mainByGit = new Map();
  for (const space of spaces) {
    const repo = repoOf(space);
    if (repo && isMain(repo) && !mainByGit.has(`${repo.top}/.git`)) mainByGit.set(`${repo.top}/.git`, space.id);
  }
  const children = new Map();
  const nested = new Set();
  for (const space of spaces) {
    const repo = repoOf(space);
    if (!repo || isMain(repo)) continue;
    const parent = mainByGit.get(repo.common);
    if (parent === undefined) continue;
    if (!children.has(parent)) children.set(parent, []);
    children.get(parent).push(space);
    nested.add(space.id);
  }
  const out = [];
  for (const space of spaces) {
    if (nested.has(space.id)) continue;
    out.push({ space, depth: 0 });
    for (const child of children.get(space.id) ?? []) out.push({ space: child, depth: 1 });
  }
  return out;
}

// 輪と札の両方で使う。別のコンピューターの端末のセッションは引かない
export function contextFor(address, sessions) {
  if (isRemoteAddress(address)) return null;
  return sessions[address] ?? null;
}

// data/activity の記録。agents() にない端末 (終わったセッションの残り) と別のコンピューターの端末では引かない。
// data/sessions の session_id と食い違う記録 (--resume や同じ端末の別のセッションの残り) も使わない
export function activityFor(address, activity, liveAgents, sessions = {}) {
  if (isRemoteAddress(address)) return null;
  if (!liveAgents.some((a) => a.address === address)) return null;
  const rec = activity[address] ?? null;
  const current = sessions[address]?.session_id;
  if (rec?.session_id && current && rec.session_id !== current) return null;
  return rec;
}

// Esc で止めると終わりが記録されないので、始まって 30 分を過ぎた記録は出さない
export const SUBAGENT_STALE_MS = 30 * 60 * 1000;

// エージェントごとのサブエージェント。hook が書いた作業中の Claude Code のサブエージェントと、
// そのエージェントが hc run で起動して動いている端末 (parent がそのエージェント)。
export function collectSubagents(liveAgents, activity, terminals, sessions = {}, now = Date.now()) {
  const out = {};
  for (const agent of liveAgents) {
    const list = [];
    const subs = activityFor(agent.address, activity, liveAgents, sessions)?.subagents;
    if (Array.isArray(subs)) {
      for (const s of subs) {
        if (s?.status === "working" && s.id != null && typeof s.started_at === "number" && now - s.started_at < SUBAGENT_STALE_MS) {
          list.push({ id: String(s.id), type: String(s.type ?? "agent") });
        }
      }
    }
    for (const t of terminals) {
      if (t.parent !== agent.address || t.state !== "live") continue;
      list.push({ id: t.address, type: t.name ?? t.argv?.[0] ?? t.address });
    }
    if (list.length > 0) out[agent.address] = list;
  }
  return out;
}

// 状態が変わった時刻と、working から done までにかかった時間を覚える
export function trackAgentTimes(prev, agents, now, fallback) {
  const next = {};
  for (const { address, status } of agents) {
    const old = prev[address];
    if (!old) {
      next[address] = { status, since: fallback[address]?.since ?? now, workedMs: null };
    } else if (old.status === status) {
      next[address] = old;
    } else {
      const workedMs = old.status === "working" && status === "done" ? now - old.since : null;
      next[address] = { status, since: now, workedMs };
    }
  }
  return next;
}

export function agentTime(rec, now) {
  if (!rec) return null;
  if (rec.status === "working" || rec.status === "blocked") return formatDuration(Math.max(0, now - rec.since));
  if (rec.status === "done" && rec.workedMs != null) return formatDuration(rec.workedMs);
  return null;
}

// 出している時間の文字 (分の単位) が次に変わるまでの ms。最小 1000
export function nextTick(recs, now) {
  let best = null;
  for (const rec of Object.values(recs)) {
    if (rec.status !== "working" && rec.status !== "blocked") continue;
    const elapsed = Math.max(0, now - rec.since);
    const wait = Math.max(1000, 60_000 - (elapsed % 60_000));
    if (best === null || wait < best) best = wait;
  }
  return best;
}

const agentLabel = (agent, sessions) => contextFor(agent.address, sessions)?.model || agent.program?.name || agent.tab_name;

const agentRow = (agent, depth, sessions, extra = {}) => ({
  key: `agent:${agent.address}`,
  kind: "agent",
  depth,
  label: agentLabel(agent, sessions),
  program: agent.program ?? null,
  status: agent.status,
  address: agent.address,
  tabId: agent.tab,
  ...extra,
});

const subRow = (agent, sub, depth, status) => ({
  key: `sub:${agent.address}:${sub.id}`,
  kind: "sub",
  depth,
  label: sub.type,
  status,
  address: agent.address,
});

// 複数 pane のタブは最初は畳む。開いたタブを collapsed に覚える (他の行とは逆の意味)
export const tabOpenKey = (tabId) => `tab-open:${tabId}`;

// space → タブ → pane (エージェントか、エージェントのいない端末) → サブエージェント。
// pane が 1 つのタブはその pane の行がタブの代わり、2 つ以上なら畳めるタブの行の下に全部の pane を並べる。
// panes は端末の pane ({ pane, tab }) を並び順で
export function buildStructure({ nested, agents, subagents, sessions = {}, collapsed, panes = [] }) {
  const rows = [];
  for (const { space, depth } of nested) {
    const tabAgents = (tab) => agents.filter((a) => a.tab === tab.id);
    const statuses = space.tabs.flatMap((t) => [t.status, ...tabAgents(t).map((a) => a.status)]).filter(Boolean);
    const open = !collapsed.has(`space:${space.id}`);
    rows.push({
      key: `space:${space.id}`,
      kind: "space",
      depth,
      label: space.name,
      // 開いているときは中の行が状態を出すので、畳んだときだけまとめて出す
      status: open ? null : mostUrgent(statuses),
      spaceId: space.id,
      open,
      hasChildren: space.tabs.length > 0,
    });
    if (!open) continue;
    const td = depth + 1;
    for (const tab of space.tabs) {
      const list = tabAgents(tab);
      const pushAgent = (agent, depth) => {
        const subs = subagents[agent.address] ?? [];
        const open = !collapsed.has(`agent:${agent.address}`);
        rows.push(agentRow(agent, depth, sessions, { spaceId: space.id, hasChildren: subs.length > 0, open }));
        if (open) for (const sub of subs) rows.push(subRow(agent, sub, depth + 1, agent.status));
      };
      // pane の並びでエージェントと端末を並べる。panes に無いエージェントは後ろに足す
      const byPane = new Map(list.filter((a) => a.pane != null).map((a) => [a.pane, a]));
      const units = panes.filter((p) => p.tab === tab.id).map((p) => byPane.get(p.pane) ?? { pane: p.pane });
      for (const a of list) if (!units.includes(a)) units.push(a);
      if (units.length === 1 && units[0].address) {
        pushAgent(units[0], td);
        continue;
      }
      const several = units.length > 1;
      const open = several && collapsed.has(tabOpenKey(tab.id));
      rows.push({
        key: `tab:${tab.id}`,
        kind: "tab",
        depth: td,
        label: tab.named ? tab.name : null,
        // 名前の 2 番目の候補: 最初のエージェントのプログラム
        program: list[0]?.program ?? null,
        // 開いたタブは中の行が状態を出す
        status: open ? null : mostUrgent([tab.status, ...list.map((a) => a.status)].filter(Boolean)),
        tabId: tab.id,
        spaceId: space.id,
        hasChildren: several,
        open,
      });
      if (!open) continue;
      for (const unit of units) {
        if (unit.address) pushAgent(unit, td + 1);
        else rows.push({ key: `pane:${unit.pane}`, kind: "pane", depth: td + 1, paneId: unit.pane, tabId: tab.id, spaceId: space.id, status: null });
      }
    }
  }
  return rows;
}

// 作業状態で並べる。STATUS_ORDER の順にまとまり、エージェントのいないまとまりは出さない
export function buildGroups({ agents, subagents, sessions = {}, collapsed }) {
  const rows = [];
  for (const status of STATUS_ORDER) {
    const list = agents.filter((a) => a.status === status);
    if (list.length === 0) continue;
    const open = !collapsed.has(`group:${status}`);
    rows.push({ key: `group:${status}`, kind: "group", depth: 0, label: STATUS[status].label, status, count: list.length, open });
    if (!open) continue;
    for (const agent of list) {
      const subs = subagents[agent.address] ?? [];
      const subOpen = !collapsed.has(`agent:${agent.address}`);
      rows.push(agentRow(agent, 1, sessions, { spaceId: agent.space, spaceName: agent.space_name, hasChildren: subs.length > 0, open: subOpen }));
      if (subOpen) for (const sub of subs) rows.push(subRow(agent, sub, 2, status));
    }
  }
  return rows;
}

// focus している pane の行と、それを含むタブと space の行 (濃く出す)。サブエージェントは親のエージェントに従う。
// focus は herdr の focused() ({ space, tab, pane, terminal } か null)
export function isFocusRow(row, focus) {
  if (!focus) return false;
  if (row.kind === "space") return row.spaceId === focus.space;
  if (row.kind === "tab") return row.tabId === focus.tab;
  if (row.kind === "pane") return row.paneId === focus.pane;
  if (row.kind === "agent" || row.kind === "sub") return focus.terminal != null && row.address === focus.terminal;
  return false;
}

export const agentOrder =(rows) => rows.filter((r) => r.kind === "agent").map((r) => r.address);

function stepInList(list, idx, dir) {
  if (list.length === 0) return null;
  if (idx === -1) return dir === 1 ? list[0] : list.at(-1);
  return list[(idx + dir + list.length) % list.length];
}

// focus の space の中で次 / 前の tab の id (端で回る)。無ければ先頭 / 末尾
export function stepTab(nested, focus, dir) {
  const space = focus ? nested.find((n) => n.space.id === focus.space)?.space : null;
  if (space && space.tabs.length > 0) {
    const ids = space.tabs.map((t) => t.id);
    return stepInList(ids, ids.indexOf(focus.tab), dir);
  }
  const allTabs = nested.flatMap((n) => n.space.tabs.map((t) => t.id));
  return stepInList(allTabs, -1, dir);
}

// 次 / 前の space の id (端で回る)。focus が無ければ先頭 / 末尾
export function stepSpace(nested, focus, dir) {
  const ids = nested.map((n) => n.space.id);
  return stepInList(ids, focus ? ids.indexOf(focus.space) : -1, dir);
}

// まとまりの行から agent だけを数えて次 / 前の address を返す
export function stepAgent(groups, focus, dir) {
  const addrs = agentOrder(groups);
  return stepInList(addrs, focus?.terminal != null ? addrs.indexOf(focus.terminal) : -1, dir);
}

// 次 / 前のまとまりの先頭エージェントの address
export function stepGroup(groups, focus, dir) {
  const buckets = [];
  for (const row of groups) {
    if (row.kind === "group") buckets.push([]);
    else if (row.kind === "agent" && buckets.length > 0) buckets.at(-1).push(row.address);
  }
  const nonEmpty = buckets.filter((b) => b.length > 0);
  const idx = focus?.terminal != null ? nonEmpty.findIndex((b) => b.includes(focus.terminal)) : -1;
  return stepInList(nonEmpty, idx, dir)?.[0] ?? null;
}

// tab.move / space.move の命令を組み立てる。別のコンピューターの space は越えない
export function moveTarget(nested, focus, dir, level) {
  if (!focus) return null;
  if (level === "tab") {
    if (!focus.tab) return null;
    return { command: "tab.move", args: { id: focus.tab, by: dir } };
  }
  if (level !== "space") return null;
  const curIdx = nested.findIndex((n) => n.space.id === focus.space);
  if (curIdx === -1) return null;
  const space = nested[curIdx].space;
  if (isRemoteSpace(space)) return null;
  const target = nested[(curIdx + dir + nested.length) % nested.length]?.space;
  if (!target || isRemoteSpace(target)) return null;
  const last = Math.max(...nested.map((n, i) => n.space.index ?? i + 1));
  const cur = space.index ?? curIdx + 1;
  let index = cur + dir;
  if (index < 1) index = last;
  else if (index > last) index = 1;
  return { command: "space.move", args: { id: space.id, index } };
}

function resolveToggleTargets(rows, focus, containers) {
  const groupKey = containers?.[0] ?? null;
  if (!groupKey) return null;
  const groupRow = rows.find((r) => r.key === groupKey) ?? null;
  if (!groupRow) return null;
  let smallKey = null;
  let smallRow = null;
  if (groupRow.kind === "space") {
    const tabOpen = containers[1] ?? null;
    if (tabOpen) {
      const tabId = tabOpen.slice("tab-open:".length);
      smallRow = rows.find((r) => r.kind === "tab" && r.tabId === tabId) ?? null;
      if (smallRow) smallKey = tabOpen;
    }
  } else if (groupRow.kind === "group" && focus?.terminal != null) {
    const agentRow = rows.find((r) => r.kind === "agent" && r.address === focus.terminal) ?? null;
    if (agentRow?.hasChildren) {
      smallRow = agentRow;
      smallKey = agentRow.key;
    }
  }
  return { groupKey, groupRow, smallKey, smallRow };
}

// 開く対象の鍵 (閉じていればその鍵、開いていれば null)
export function openKey(rows, focus, containers, level) {
  const t = resolveToggleTargets(rows, focus, containers);
  if (!t) return null;
  if (level === "group") return !t.groupRow.open ? t.groupKey : null;
  if (level === "small") return t.smallRow && !t.smallRow.open ? t.smallKey : null;
  return null;
}

// 閉じる対象の鍵 (開いていればその鍵、閉じていれば 1 つ上の段の鍵)
export function closeKey(rows, focus, containers, level) {
  const t = resolveToggleTargets(rows, focus, containers);
  if (!t) return null;
  if (level === "group") return t.groupRow.open ? t.groupKey : null;
  if (level === "small") {
    if (t.smallRow?.open) return t.smallKey;
    return t.groupRow.open ? t.groupKey : null;
  }
  return null;
}
