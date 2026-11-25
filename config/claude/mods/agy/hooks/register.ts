import type { EngineInterface, Register } from 'claude-code'
import {
  buildArgv,
  buildPrompt,
  formatReturn,
  gitHooksEnv,
  isAllowedDir,
  modelFrom,
  outsideWrites,
  parseResult,
  parseWorktrees,
  refsChanged,
  refsSnapshot,
  transcriptPath,
  workDirFrom,
} from './logic.mjs'

// agy:worker サブエージェントを定義し、その要求をモデルに送らずに答える。
// 委任の文を agy (Antigravity CLI) の headless 実行に回し、その digest を報告として返す。

const AGENT_TYPE = 'agy:worker'
const HANDBACK = 'SubagentHandback'
const READ_LIMIT = 4 * 1024 * 1024

const DESCRIPTION =
  'superpowers の実装役 (直しを含む) と、利用者が agy に任せると言った作業にだけ使う。' +
  'Antigravity CLI (Gemini) が編集とテストを行い、git の書き込みはしない。' +
  '指示には `作業ディレクトリ: <絶対パス>` の行、計画書の場所と担当のタスク、完了条件を書く。' +
  '省ける行: `モデル: <agy models の id>` (省くと gemini-4-hydrogen-medium)。'

const PROMPT = 'このエージェントの要求は agy mod が Antigravity CLI に回す。モデルは呼ばれない。'

// agentId が agy:worker のものか。ほかのサブエージェントとメインの要求は素通しにする
async function isAgyWorker($: EngineInterface, agentId: string): Promise<boolean> {
  const agents = await $.agent.list()
  return agents.some((a) => a.id === agentId && a.type === AGENT_TYPE)
}

// サブエージェントの最後の user の文 (委任の指示。SendMessage で再開されたときはその文)
async function delegationOf($: EngineInterface, agentId: string): Promise<string> {
  const rows = await $.session.messages({ agentId })
  if (!Array.isArray(rows)) return ''
  const asks = rows.filter((m) => m.role === 'user' && !(m.toolResults?.length) && m.text !== '')
  return asks.at(-1)?.text ?? ''
}

const errorText = (err: unknown): string => (err instanceof Error ? err.message : String(err))

// agy の結果と同じ形で、agy を走らせなかったときの報告を作る
const failure = (status: string, detail: string) => ({
  status,
  digest: '',
  conversationId: null,
  tokens: null,
  denied: [],
  refsChanged: [],
  outsideWrites: [],
  detail,
})

// 作業ディレクトリの git の refs、HEAD、index。git のリポジトリでなければ空
async function snapshot($: EngineInterface, cwd: string): Promise<string> {
  const refs = await $.process.run(['git', 'for-each-ref', '--format=%(refname) %(objectname)'], { cwd })
  if (refs.exitCode !== 0) return ''
  const head = await $.process.run(['git', 'rev-parse', 'HEAD'], { cwd })
  const tree = await $.process.run(['git', 'write-tree'], { cwd })
  const extra = tree.exitCode === 0 ? `\nINDEX ${tree.stdout.trim()}` : ''
  return refsSnapshot(head.exitCode === 0 ? head.stdout : '-', `${refs.stdout}${extra}`)
}

// agy の transcript。4 MiB を超えるなら末尾の 4 MiB を読む (切れた先頭の行は outsideWrites が読み飛ばす)
async function readTranscript($: EngineInterface, file: string): Promise<string> {
  const { size } = await $.fs.stat(file)
  const offset = Math.max(0, size - READ_LIMIT)
  return $.fs.read(file, { offset, length: Math.min(size, READ_LIMIT) })
}

// 止められたか。$.process.spawn は abort で aborted を投げる
const isAborted = (signal: AbortSignal, err: unknown): boolean =>
  signal.aborted || (err instanceof Error && (err.name === 'AbortError' || /\baborted\b/.test(err.message)))

// 委任を agy に回し、報告を返す。止められたら null を返す
async function runAgy($: EngineInterface, delegation: string, signal: AbortSignal): Promise<string | null> {
  let home = ''
  try {
    const cwd = await $.session.cwd()
    const cwdReal = await $.process.run(['/bin/realpath', cwd])
    const sessionCwd = cwdReal.exitCode === 0 ? cwdReal.stdout.trim() : cwd
    home = (await $.process.run(['/usr/bin/printenv', 'HOME'])).stdout.trim()

    const real = await $.process.run(['/bin/realpath', workDirFrom(delegation, sessionCwd)])
    if (real.exitCode !== 0) {
      return formatReturn(failure('spawn-failed', `作業ディレクトリを解決できない: ${real.stderr.trim()}`), home)
    }
    const workDir = real.stdout.trim()

    const wt = await $.process.run(['git', 'worktree', 'list', '--porcelain'], { cwd: sessionCwd })
    const worktrees = wt.exitCode === 0 ? parseWorktrees(wt.stdout) : []
    if (!isAllowedDir(workDir, sessionCwd, worktrees)) {
      return formatReturn(failure('outside', `作業ディレクトリがセッションと worktree の外: ${workDir}`), home)
    }

    const chosen = modelFrom(delegation)
    if ('error' in chosen) return formatReturn(failure('bad-model', chosen.error ?? ''), home)

    const settings = `${$.plugin.root}/agy-settings.json`
    const hooksDir = `${$.plugin.root}/git-hooks`
    const before = await snapshot($, workDir)

    const child = $.process.spawn({
      argv: buildArgv(buildPrompt(delegation), settings, chosen.model ?? ''),
      cwd: workDir,
      env: gitHooksEnv(hooksDir),
    })
    let step
    try {
      step = await child.next()
    } catch (err) {
      if (isAborted(signal, err)) return null
      return formatReturn(failure('spawn-failed', errorText(err)), home)
    }
    let stdout = ''
    let stderr = ''
    while (!step.done) {
      if (step.value.stream === 'stdout') stdout += step.value.text
      else stderr += step.value.text
      step = await child.next()
    }
    if (signal.aborted) return null
    const { code, signal: killedBy } = step.value

    // logic.mjs の推論では空の配列が never[] になるので、ここで型を付け直す
    const r = { ...parseResult(stdout, stderr, code, killedBy), refsChanged: [] as string[], outsideWrites: [] as string[] }
    // 比べられなくても agy の結果は捨てない
    try {
      r.refsChanged = refsChanged(before, await snapshot($, workDir))
    } catch (err) {
      r.refsChanged = [`比べられなかった: ${errorText(err)}`]
    }
    if (r.conversationId) {
      try {
        r.outsideWrites = outsideWrites(await readTranscript($, transcriptPath(home, r.conversationId)), workDir)
      } catch (err) {
        r.outsideWrites = [`transcript を読めなかった: ${errorText(err)}`]
      }
    }
    return formatReturn(r, home)
  } catch (err) {
    if (isAborted(signal, err)) return null
    return formatReturn(failure('spawn-failed', errorText(err)), home)
  }
}

// mod が持つ状態は agentId ごとのこの 2 つだけ。agent が終わったら消す
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

  on('agent.report', async ($, e, next) => {
    const reported = await next(e)
    modeOf.delete(e.agentId)
    reports.delete(e.agentId)
    return reported
  })

  on('turn.step', async function* ($, e, next) {
    if (!e.agentId || !(await isAgyWorker($, e.agentId))) return yield* next(e)

    let message = reports.get(e.agentId)
    const first = message === undefined
    if (message === undefined) {
      const report = await runAgy($, await delegationOf($, e.agentId), next.signal)
      if (report === null) {
        return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: null, usage: null }
      }
      message = report
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
