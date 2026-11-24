import type { EngineInterface, Register } from 'claude-code'

// agy:worker サブエージェントを定義し、その要求をモデルに送らずに答える。
// 試作 (Task 1): agy の代わりに sleep を走らせ、委任の文の先頭を echo で返す。

const AGENT_TYPE = 'agy:worker'
const HANDBACK = 'SubagentHandback'

const DESCRIPTION =
  'superpowers の実装役 (直しを含む) と、利用者が agy に任せると言った作業にだけ使う。' +
  'Antigravity CLI (Gemini) が編集とテストを行い、git の書き込みはしない。' +
  '指示には `作業ディレクトリ: <絶対パス>` の行、計画書の場所と担当のタスク、完了条件を書く。'

const PROMPT = 'このエージェントの要求は agy mod が Antigravity CLI に回す。モデルは呼ばれない。'

// agentId が agy:worker のものか。ほかのサブエージェントとメインの要求は素通しにする
async function isAgyWorker($: EngineInterface, agentId: string): Promise<boolean> {
  const agents = await $.agent.list()
  return agents.some((a) => a.id === agentId && a.type === AGENT_TYPE)
}

// サブエージェントの最初の user の文 (委任の指示)
async function delegationOf($: EngineInterface, agentId: string): Promise<string> {
  const rows = await $.session.messages({ agentId })
  if (!Array.isArray(rows)) return ''
  return rows.find((m) => m.role === 'user')?.text ?? ''
}

// agy:worker の起動時の親の権限モード。hand-back ツールは auto mode のときだけある
const modeOf = new Map<string, string | undefined>()
// 1 回目の step で作った報告。2 回目の step が来ても agy を走らせ直さない
const reports = new Map<string, string>()

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.agent.register({
      name: 'worker',
      description: DESCRIPTION,
      prompt: PROMPT,
      tools: [],
      omitClaudeMd: true,
    })
    return started
  })

  on('agent.spawn', async ($, e, next) => {
    const spawned = await next(e)
    if (e.subagentType === AGENT_TYPE && 'agentId' in spawned && spawned.agentId) {
      modeOf.set(spawned.agentId, e.permissionMode)
    }
    return spawned
  })

  on('turn.step', async function* ($, e, next) {
    if (!e.agentId || !(await isAgyWorker($, e.agentId))) return yield* next(e)

    let message = reports.get(e.agentId)
    const first = message === undefined
    if (message === undefined) {
      const delegation = await delegationOf($, e.agentId)
      const child = $.process.spawn({ argv: ['/bin/sleep', '20'] })
      for await (const _ of child) {
        // sleep は何も出さない。最後まで読む
      }
      message = `echo: ${delegation.slice(0, 200)}`
      reports.set(e.agentId, message)
    }

    // auto mode では報告は SubagentHandback の呼び出しでしか届かない。ほかのモードでは最後の text が報告になる
    if (first && modeOf.get(e.agentId) === 'auto') {
      const input = { message }
      yield { kind: 'tool', index: 0, id: `toolu_agy_${e.turnId}_${e.index}`, name: HANDBACK }
      yield { kind: 'input', index: 0, json: JSON.stringify(input) }
      yield { kind: 'stop', stopReason: 'tool_use', usage: null }
      return { turnId: e.turnId, index: e.index, answer: '', toolUses: [{ name: HANDBACK, input }], stopReason: 'tool_use', usage: null }
    }
    yield { kind: 'text', index: 0, text: message }
    yield { kind: 'stop', stopReason: 'end_turn', usage: null }
    return { turnId: e.turnId, index: e.index, answer: message, toolUses: [], stopReason: 'end_turn', usage: null }
  })
}
