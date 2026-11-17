// herdr に依存しない判断だけを置く (node --test で試す)

// エージェントの終了と入力待ちの通知を消す。どちらも、押すとそのエージェントへ移る
// action (agent.focus) を持つ。入力待ちは level が error なので、level では見分けない
export function shouldSuppress(toast) {
  return toast?.action?.name === "agent.focus";
}
