// 枠の見出しの中身。herdr に依存しない (main.js が herdr から集めた値を渡す)
import { GLYPH, contextColor, contextPercent, formatTokens, paneLabel, tokensToCompact } from "./ui.js";

// エージェント: 作業状態がある、またはプログラムがエージェント
export const isAgentPane = (pane) => pane.status != null || Boolean(pane.program?.agent);

// エージェントは、輪で囲んだアイコン、model (無ければプログラム名)、effort、要約までの残り。それ以外は paneLabel。
// 別のコンピューターの枠では、main.js が session と repoRoot に null を渡す
export function headerFor({ pane, session, repoRoot, home }) {
  // mod の枠 (pane.split {mod}) は端末を持たない。枠の名前だけ
  if (pane.terminal == null) return { kind: "plain", icon: GLYPH.terminal, text: pane.title ?? pane.mod ?? "" };
  const program = pane.program;
  if (isAgentPane(pane)) {
    const pct = contextPercent(session?.context);
    const left = tokensToCompact(session?.context);
    return {
      kind: "agent",
      program: program ?? null,
      model: session?.model ?? null,
      label: session?.model || program?.name || "",
      effort: session?.effort ?? null,
      tokens: left == null ? null : formatTokens(left),
      tokensColor: pct == null ? null : contextColor(pct),
      ring: pct == null ? 0 : Math.min(1, pct / 100),
      ringColor: pct == null ? null : contextColor(pct),
    };
  }
  const processName = program ? (program.key === "program" ? program.name : program.key) : "";
  const label = paneLabel({
    programKey: program?.key,
    processName,
    shell: Boolean(program?.shell),
    cwd: pane.cwd,
    repoRoot,
    home,
  });
  return { kind: "plain", icon: label.icon, text: label.text };
}
