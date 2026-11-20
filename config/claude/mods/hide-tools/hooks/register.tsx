import type { Register } from 'claude-code'

// herdr の中では、会話の中のツールの行を消す。ctrl+o の全表示 (isExpanded) では元のまま出す。
// herdr の外では何もしない。
// herdr の中かどうかは HC_TERMINAL_ID で見分ける。$.process.hookEnv() にも
// process.env にも出ないので、printenv を呼ぶ (run は Claude Code の環境変数を引き継ぐ)。
export const register: Register = (on) => {
  let inHerdr: Promise<boolean> | undefined

  for (const component of ['ToolUse', 'ToolResult', 'ToolGroup'] as const) {
    on('ui.render', { component }, async ($, e, next) => {
      if ((e.props as { isExpanded?: boolean }).isExpanded) return next(e)
      inHerdr ??= $.process
        .run(['/usr/bin/printenv', 'HC_TERMINAL_ID'])
        .then((r) => r.exitCode === 0 && r.stdout.trim() !== '')
        .catch(() => false)
      if (!(await inHerdr)) return next(e)
      const { Box } = $.ui.resolve(e)
      return <Box />
    })
  }
}
