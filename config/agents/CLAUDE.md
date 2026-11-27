# Claude Code の個人設定

共通の設定 (agy にも配る) は次のファイルにある。

@~/dotfiles/config/agents/AGENTS.md

## agy
- superpowers:subagent-driven-development の実装役 (直しを含む) は `subagent_type: "agy:worker"` で起動する。`model` は渡さない (モデルを呼ばないため)
- 委任の文には、実装役の雛形の中身に加えて `作業ディレクトリ: <絶対パス>` の行を書く
- superpowers のタスクごとの確認役 (spec、code quality) も `subagent_type: "agy:worker"` で起動し、委任の文に `役: review` の行を足す。モデルの行は、通常のタスクが `モデル: gemini-4-hydrogen-medium`、設計の判断が要るタスクが `モデル: gemini-4-neon-medium`。詳しい報告が長くなりそうなときは `報告ファイル: <絶対パス>` の行も足し、digest は verdict と場所だけにさせる。最終 review は `/code-review medium` のままで、agy に任せない
- 確認役の META の `tree_changed:` が `-` でないときは、確認役が作業ツリーを変えている。結果を使わずに利用者に聞く。`status: bad-role` は `役:` の行の誤りなので、行を直して頼み直す
- agy:worker が `Status: DONE` を返したら、指揮役が `git status`、`git diff`、`git diff --cached` を見て、完了条件のテストを自分で走らせ、計画書の commit を行ってから review package を作る。`denied:` に必要なコマンドがあれば、指揮役が走らせる
- META の `refs_changed:` か `outside_writes:` が `-` でないときは、commit せずに利用者に聞く。`outside_writes:` はファイルのツールの書き込みだけで、シェルの書き込みは出ない
- `status: outside`、`status: bad-model`、`status: bad-role` は委任の文の誤りなので、行を直して agy:worker に頼み直す
- モデルは、基本は Gemini を使う。設計の判断が要るタスクの実装役は `モデル: gemini-4-neon-medium`、それ以外は `モデル` の行を省く (`gemini-4-hydrogen-medium` になる)。確認役は上の行のとおり
- `status: quota` のときは、そのセッションの残りの実装役と確認役を、agy の Claude に切り替えて頼み直す。通常のタスクは `モデル: claude-sonnet-5-5-medium`、設計の判断が要るタスクは `モデル: claude-opus-5-5-medium`
- 直しが 4 回目以上になったとき、BLOCKED のとき、META の `status:` が ok でないとき (outside、bad-model、bad-role を除く)、DIGEST に `Status:` の行が無いとき、agy の Claude でも `status: quota` のときは、Claude の実装役 (`subagent_type: "general-purpose"`、`model: "sonnet"`。effort は渡さず、普段の superpowers の実装役と同じく settings の `modelSettings` の値に任せる) に戻す。確認役は、agy が使えなければ superpowers の reviewer に戻す

## 実装の進め方
- この節、共通の設定の「実装の進め方」、「レビュー」の節は、superpowers の skill の指示 (「1% でも当てはまれば使う」を含む) より優先する
- 変更が小さく (数ファイル以内で、仕様がはっきりしている) 設計の判断が要らないときは、superpowers の brainstorming と writing-plans を使わずに直接実装する

## レビュー
- バグを探すレビューは `/code-review` を使う。superpowers の最終レビュー (subagent-driven-development の whole-branch review) と requesting-code-review の代わりに、ブランチの差分に `/code-review medium` を走らせ、その指摘を最終レビューの指摘として扱う (直しは 1 つの subagent にまとめて渡す)
- superpowers のタスクごとのレビュー (計画どおりかの確認) は、そのまま superpowers の reviewer に任せる
