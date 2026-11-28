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

// pane の並びでエージェントと端末を並べる。panes に無いエージェントは後ろに足す
function tabUnits(tabId, agents, panes) {
  const list = agents.filter((a) => a.tab === tabId);
  const byPane = new Map(list.filter((a) => a.pane != null).map((a) => [a.pane, a]));
  const units = panes.filter((p) => p.tab === tabId).map((p) => byPane.get(p.pane) ?? { pane: p.pane });
  for (const a of list) if (!units.includes(a)) units.push(a);
  return { list, units };
}

// space → タブ → サブエージェント。space は畳まない。
// タブは 1 行で、そのタブで最後に focus された pane (activePanes: タブ → pane、無ければ並びの最初) を代表にする。
// 代表がエージェントならエージェントの行 (サブエージェントを下に並べる)、そうでなければタブの行。
// panes は端末の pane ({ pane, tab }) を並び順で
export function buildStructure({ nested, agents, subagents, sessions = {}, collapsed, panes = [], activePanes = new Map() }) {
  const rows = [];
  for (const { space, depth } of nested) {
    rows.push({ key: `space:${space.id}`, kind: "space", depth, label: space.name, status: null, spaceId: space.id });
    const td = depth + 1;
    for (const tab of space.tabs) {
      const { list, units } = tabUnits(tab.id, agents, panes);
      const active = activePanes.get(tab.id);
      const rep = units.find((u) => active != null && u.pane === active) ?? units[0];
      if (rep?.address) {
        const subs = subagents[rep.address] ?? [];
        const open = !collapsed.has(`agent:${rep.address}`);
        rows.push(agentRow(rep, td, sessions, { spaceId: space.id, hasChildren: subs.length > 0, open }));
        if (open) for (const sub of subs) rows.push(subRow(rep, sub, td + 1, rep.status));
        continue;
      }
      rows.push({
        key: `tab:${tab.id}`,
        kind: "tab",
        depth: td,
        label: tab.named ? tab.name : null,
        // 代表の端末の pane (名前と記号に使う)
        paneId: rep?.pane ?? null,
        status: mostUrgent([tab.status, ...list.map((a) => a.status)].filter(Boolean)),
        tabId: tab.id,
        spaceId: space.id,
      });
    }
  }
  return rows;
}

// 作業状態で並べる。STATUS_ORDER の順にまとまり、エージェントのいないまとまりは出さない。
// まとまりの中は since の古い順 (無いものは後ろ、同じなら今の順)
export function buildGroups({ agents, subagents, sessions = {}, collapsed, times = {} }) {
  const rows = [];
  for (const status of STATUS_ORDER) {
    const list = agents
      .filter((a) => a.status === status)
      .sort((a, b) => {
        const sa = times[a.address]?.since;
        const sb = times[b.address]?.since;
        if (sa == null && sb == null) return 0;
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sa - sb;
      });
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

// focus している pane のエージェントかタブの行と、それを含む space の行 (濃く出す)。サブエージェントは親のエージェントに従う。
// focus は herdr の focused() ({ space, tab, pane, terminal } か null)
export function isFocusRow(row, focus) {
  if (!focus) return false;
  if (row.kind === "space") return row.spaceId === focus.space;
  if (row.kind === "tab") return row.tabId === focus.tab;
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
  const ordered = nested
    .map((n, i) => ({ space: n.space, index: n.space.index ?? i + 1 }))
    .sort((a, b) => a.index - b.index);
  const curIdx = ordered.findIndex((o) => o.space.id === focus.space);
  if (curIdx === -1) return null;
  const { space, index: cur } = ordered[curIdx];
  if (isRemoteSpace(space)) return null;
  const target = ordered[(curIdx + dir + ordered.length) % ordered.length]?.space;
  if (!target || isRemoteSpace(target)) return null;
  const sameMachine = ordered.filter((o) => (o.space.machine ?? null) === (space.machine ?? null));
  const last = Math.max(...sameMachine.map((o) => o.index));
  let index = cur + dir;
  if (index < 1) index = last;
  else if (index > last) index = 1;
  return { command: "space.move", args: { id: space.id, index } };
}

// 開閉できるのは状態の表示のまとまり (group) と、その中の focus のエージェントのサブエージェント (small)
function resolveToggleTargets(rows, focus, containers) {
  const groupKey = containers?.[0] ?? null;
  if (!groupKey) return null;
  const groupRow = rows.find((r) => r.key === groupKey) ?? null;
  if (groupRow?.kind !== "group") return null;
  const agentRow = focus?.terminal != null ? rows.find((r) => r.kind === "agent" && r.address === focus.terminal) : null;
  const smallRow = agentRow?.hasChildren ? agentRow : null;
  return { groupKey, groupRow, smallKey: smallRow?.key ?? null, smallRow };
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

// focus 中のエージェントを含む、閉じうるまとまりの鍵。構造の表示は畳む行が無いので []
export function focusContainers({ view, agents = [], focus }) {
  if (!focus || view !== "status" || focus.terminal == null) return [];
  const agent = agents.find((a) => a.address === focus.terminal);
  return agent?.status ? [`group:${agent.status}`] : [];
}

// collapsed を写し、held に無い containers の鍵を開いた状態にする
export function effectiveCollapsed(collapsed, containers, held = new Set()) {
  const next = new Set(collapsed);
  for (const key of containers) if (!held.has(key)) next.delete(key);
  return next;
}

// containers に無い鍵を held から捨てる
export function pruneHeld(held, containers) {
  const active = new Set(containers);
  const next = new Set();
  for (const key of held) {
    if (active.has(key)) next.add(key);
  }
  return next;
}

// ハイライトする行の鍵。表に出ている focus のエージェントかタブの行、無ければ containers を内から外へ
export function highlightKey(rows, focus, containers = []) {
  if (!focus) return null;
  const leaf = rows.find((r) => r.kind === "agent" && isFocusRow(r, focus));
  if (leaf) return leaf.key;
  const tab = rows.find((r) => r.kind === "tab" && isFocusRow(r, focus));
  if (tab) return tab.key;
  for (let i = containers.length - 1; i >= 0; i--) {
    if (rows.some((r) => r.key === containers[i])) return containers[i];
  }
  return null;
}
