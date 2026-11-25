# 個人設定

## 応答設定
- すべての応答は日本語で
- 絵文字の使用は禁止

## ツール
- URL の取得、Web ページの調査、HTML からの抽出には `ax` を使う。WebFetch、`curl`、使い捨てのスクリプトは使わない。使い方は skill `ax` か `ax agent-context` で確認する

## agy
- superpowers:subagent-driven-development の実装役 (直しを含む) は `subagent_type: "agy:worker"` で起動する。`model` は渡さない (モデルを呼ばないため)
- 委任の文には、実装役の雛形の中身に加えて `作業ディレクトリ: <絶対パス>` の行を書く
- agy:worker が `Status: DONE` を返したら、指揮役が `git status`、`git diff`、`git diff --cached` を見て、完了条件のテストを自分で走らせ、計画書の commit を行ってから review package を作る。`denied:` に必要なコマンドがあれば、指揮役が走らせる
- META の `refs_changed:` か `outside_writes:` が `-` でないときは、commit せずに利用者に聞く。`outside_writes:` はファイルのツールの書き込みだけで、シェルの書き込みは出ない
- `status: outside` と `status: bad-model` は委任の文の誤りなので、行を直して agy:worker に頼み直す
- 直しが 4 回目以上になったとき、BLOCKED のとき、META の `status:` が ok でないとき (outside と bad-model を除く)、DIGEST に `Status:` の行が無いときは、Claude の実装役 (`subagent_type: "general-purpose"`、`model: "sonnet"`。effort は渡さず、普段の superpowers の実装役と同じく settings の `modelSettings` の値に任せる) に戻す。`status: quota` のときは、そのセッションの残りのタスクも Claude の実装役に回す

## 禁止事項
- `pip3 install`などpythonライブラリの無許可インストール
- ファイル編集での`sed -i`の使用。代わりにEditツールを使う
