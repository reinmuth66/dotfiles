# 個人設定

## 応答設定
- すべての応答は日本語で
- 絵文字の使用は禁止

## ツール
- URL の取得、Web ページの調査、HTML からの抽出には `ax` を使う。WebFetch、`curl`、使い捨てのスクリプトは使わない。使い方は skill `ax` か `ax agent-context` で確認する

## agy
- superpowers:subagent-driven-development の実装役 (直しを含む) は `subagent_type: "agy:worker"` で起動する。`model` は渡さない (モデルを呼ばないため)
- 委任の文には、実装役の雛形の中身に加えて `作業ディレクトリ: <絶対パス>` の行を書く
- superpowers のタスクごとの確認役 (spec、code quality) も `subagent_type: "agy:worker"` で起動し、委任の文に `役: review` の行を足す。モデルの行は、通常のタスクが `モデル: claude-sonnet-5-5-medium`、設計の判断が要るタスクが `モデル: claude-opus-5-5-medium`。詳しい報告が長くなりそうなときは `報告ファイル: <絶対パス>` の行も足し、digest は verdict と場所だけにさせる。最終 review は `/code-review medium` のままで、agy に任せない
- 確認役の META の `tree_changed:` が `-` でないときは、確認役が作業ツリーを変えている。結果を使わずに利用者に聞く。`status: bad-role` は `役:` の行の誤りなので、行を直して頼み直す
- agy:worker が `Status: DONE` を返したら、指揮役が `git status`、`git diff`、`git diff --cached` を見て、完了条件のテストを自分で走らせ、計画書の commit を行ってから review package を作る。`denied:` に必要なコマンドがあれば、指揮役が走らせる
- META の `refs_changed:` か `outside_writes:` が `-` でないときは、commit せずに利用者に聞く。`outside_writes:` はファイルのツールの書き込みだけで、シェルの書き込みは出ない
- `status: outside`、`status: bad-model`、`status: bad-role` は委任の文の誤りなので、行を直して agy:worker に頼み直す
- 直しが 4 回目以上になったとき、BLOCKED のとき、META の `status:` が ok でないとき (outside、bad-model、bad-role を除く)、DIGEST に `Status:` の行が無いときは、Claude の実装役 (`subagent_type: "general-purpose"`、`model: "sonnet"`。effort は渡さず、普段の superpowers の実装役と同じく settings の `modelSettings` の値に任せる) に戻す。`status: quota` のときは、そのセッションの残りのタスクも Claude の実装役に回す

## 実装の進め方
- この節と「レビュー」の節は、superpowers の skill の指示 (「1% でも当てはまれば使う」を含む) より優先する
- 変更が小さく (数ファイル以内で、仕様がはっきりしている) 設計の判断が要らないときは、superpowers の brainstorming と writing-plans を使わずに直接実装する
- 変更は小さく、かつ完全にする。変更が届くべき場所 (呼び出し元、同じ規則を持つ別の入口、テスト、設定、ドキュメント) は同じ変更で全部直し、後回しの課題にしない。頼まれていない選択肢、設定、互換の層、データの修復は足さない。保存済みのデータの修復が要るときは先に聞く
- コードベースに既にあるもの、標準ライブラリ、入っている依存を、新しく書くより先に使う
- レビューの指摘は、実際に起こりうる入力 (利用者、実際のファイル、連携先、並行して動く処理が作るもの) を名指しできるものだけを直す。前のレビューの直しで足したコードへの指摘や、直しが元のコードより大きくなる指摘は、利用者に判断を仰ぐ

## レビュー
- バグを探すレビューは `/code-review` を使う。superpowers の最終レビュー (subagent-driven-development の whole-branch review) と requesting-code-review の代わりに、ブランチの差分に `/code-review medium` を走らせ、その指摘を最終レビューの指摘として扱う (直しは 1 つの subagent にまとめて渡す)
- superpowers のタスクごとのレビュー (計画どおりかの確認) は、そのまま superpowers の reviewer に任せる

## 禁止事項
- `pip3 install`などpythonライブラリの無許可インストール
- ファイル編集での`sed -i`の使用。代わりにEditツールを使う
