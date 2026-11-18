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

// エージェントごとのサブエージェント。hook が書いた作業中の Claude Code のサブエージェントと、
// そのエージェントが hc run で起動して動いている端末 (parent がそのエージェント)。
// hook のサブエージェントは、Esc で止めると終わりが記録されないので、親が待機か完了なら出さない
export function collectSubagents(liveAgents, activity, terminals, sessions = {}) {
  const out = {};
  for (const agent of liveAgents) {
    const list = [];
    const ended = agent.status === "idle" || agent.status === "done";
    const subs = ended ? null : activityFor(agent.address, activity, liveAgents, sessions)?.subagents;
    if (Array.isArray(subs)) {
      for (const s of subs) if (s?.status === "working" && s.id != null) list.push({ id: String(s.id), type: String(s.type ?? "agent") });
    }
    for (const t of terminals) {
      if (t.parent !== agent.address || t.state !== "live") continue;
      list.push({ id: t.address, type: t.name ?? t.argv?.[0] ?? t.address });
    }
    if (list.length > 0) out[agent.address] = list;
  }
  return out;
}

// 生きている端末の名前は変えず、消えた端末の名前は外す。新しい端末には使われていない名前を前から付ける。
// 全部使われていたら "Mocha 2"、"Mocha 3" (名簿の順で、使われていない最初のもの)
export function assignNames(prev, live, roster) {
  const next = {};
  for (const address of live) if (prev[address] !== undefined) next[address] = prev[address];
  const used = new Set(Object.values(next));
  for (const address of live) {
    if (next[address] !== undefined) continue;
    let name = roster.find((n) => !used.has(n));
    for (let i = 2; name === undefined; i++) name = roster.map((n) => `${n} ${i}`).find((n) => !used.has(n));
    next[address] = name;
    used.add(name);
  }
  return next;
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

const agentRow = (agent, depth, names, extra = {}) => ({
  key: `agent:${agent.address}`,
  kind: "agent",
  depth,
  label: names[agent.address] ?? agent.tab_name,
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

// space → タブ → エージェント → サブエージェント
export function buildStructure({ nested, agents, subagents, names, collapsed }) {
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
      status: mostUrgent(statuses),
      spaceId: space.id,
      open,
      hasChildren: space.tabs.length > 0,
    });
    if (!open) continue;
    const td = depth + 1;
    for (const tab of space.tabs) {
      const list = tabAgents(tab);
      const subsOf = (a) => subagents[a.address] ?? [];
      if (list.length === 1 && subsOf(list[0]).length === 0) {
        rows.push(agentRow(list[0], td, names, { spaceId: space.id }));
        continue;
      }
      rows.push({
        key: `tab:${tab.id}`,
        kind: "tab",
        depth: td,
        label: tab.named ? tab.name : null,
        status: mostUrgent([tab.status, ...list.map((a) => a.status)].filter(Boolean)),
        tabId: tab.id,
        spaceId: space.id,
      });
      for (const agent of list) {
        const subs = subsOf(agent);
        const open = !collapsed.has(`agent:${agent.address}`);
        rows.push(agentRow(agent, td + 1, names, { spaceId: space.id, hasChildren: subs.length > 0, open }));
        if (open) for (const sub of subs) rows.push(subRow(agent, sub, td + 2, agent.status));
      }
    }
  }
  return rows;
}

// 作業状態で並べる。STATUS_ORDER の順にまとまり、エージェントのいないまとまりは出さない
export function buildGroups({ agents, subagents, names, collapsed }) {
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
      rows.push(agentRow(agent, 1, names, { spaceId: agent.space, spaceName: agent.space_name, hasChildren: subs.length > 0, open: subOpen }));
      if (subOpen) for (const sub of subs) rows.push(subRow(agent, sub, 2, status));
    }
  }
  return rows;
}

export const agentOrder = (rows) => rows.filter((r) => r.kind === "agent").map((r) => r.address);
