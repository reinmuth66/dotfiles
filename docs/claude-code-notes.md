# Claude Code のノート

CLAUDE.md、skill、agents の位置づけと、このリポジトリで skill を作って評価した経験をまとめたノート。
このファイルは自動では読み込まれない。人間が読むための資料で、Claude の指示ではない。

Claude Code のバージョンで挙動が変わるので、古くなる前提で読む。

## 信頼度の基準

- 高: 公式ドキュメント、CHANGELOG、実ファイルや実測で確認でき、記述が一致している。
- 中: 公式の記述はあるが、実挙動を検証していない。または一部が曖昧。
- 低: 第三者の記事や未解決の issue だけが根拠。

## 1. 基本原則 (要点)

1. CLAUDE.md は強制ではなく文脈である。守らせたいことはフックで実装する。(高)
2. CLAUDE.md は階層をまたいで連結され、上書きされない。矛盾する指示は書かない。(高)
3. skill と agent は同名なら 1 つに絞られ、統合されない。CLAUDE.md とは動作が違う。(高)
4. skill は説明文だけが常時文脈に入り、本文は呼ばれたときに入る。説明文が起動の唯一の手がかりである。(高)
5. agent の説明文は毎ターン文脈に入る。作るなら 1 つの目的に絞り、`tools` を絞る。(高)
6. 常に守るルールは CLAUDE.md、手順や参考資料は skill、出力が多い調査は agent に置く。(高)
7. skill の評価は、本物の skill を入れた状態で測る。一時コマンド方式の測定は信用しない。(高、実測)
8. 簡単な課題では、skill がなくても同じ結果になる。評価は、skill が必要になる難しい課題で行う。(中、実測)

## 2. CLAUDE.md

### 置き場所と読み込み順 (高)

広い範囲から狭い範囲へ、次の順に連結される。後ろに来る指示ほど最後に読まれる。

| 範囲 | 場所 |
|---|---|
| 組織 (managed policy) | macOS は `/Library/Application Support/ClaudeCode/CLAUDE.md` |
| ユーザー | `~/.claude/CLAUDE.md` (全プロジェクトに効く) |
| プロジェクト | `./CLAUDE.md` または `./.claude/CLAUDE.md` (git で共有) |
| ローカル | `./CLAUDE.local.md` (個人用。`.gitignore` に入れる) |

- 起動ディレクトリと、その上位ディレクトリの CLAUDE.md がすべて連結される。
- 下位ディレクトリの CLAUDE.md は、そこのファイルを Claude が読み書きした時点で追加される。
- ユーザー用の CLAUDE.md が Nix ストアへの symlink でも、問題なく読まれる。(実機で確認)

### 衝突したとき (高)

- どちらが勝つかは保証されない。公式は "Claude may pick one arbitrarily" と警告している。
- 「プロジェクトがグローバルに優先する」という第三者記事の主張は、公式の記述と合わない。(低)
- 結論: グローバルとプロジェクトで矛盾する指示を書かない。

### 強制ではない (高)

- 公式は "context, not enforced configuration" と明言している。
- 確実に守らせたい禁止事項は、CLAUDE.md ではなく PreToolUse フックで実装する。

### 補助機構 (高)

- `@path` で他ファイルを取り込める (再帰は最大 4 段)。起動時に全部読み込まれるので、文脈量は減らない。
- `.claude/rules/*.md` に `paths:` を付けると、該当ファイルを開いたときだけ読み込まれる。
- 作業ディレクトリかその上位に CLAUDE.md があれば、AGENTS.md は読まれない (v2.1.277 以降)。
- 目安は 1 ファイル 200 行以内。HTML のブロックコメントは、文脈に入る前に取り除かれる。

## 3. skill と slash command

### 統合済み (高)

- `.claude/commands/x.md` と `.claude/skills/x/SKILL.md` は、どちらも `/x` を作り、同じように動く。
- v2.1.3 で統合された。新規作成は skill が推奨される。skill には補助ファイル、自動起動の制御、`paths` 指定がある。

### 置き場所と優先順位 (高)

- 優先順は、組織 > 個人 (`~/.claude/skills/`) > プロジェクト (`.claude/skills/`)。
- 同名の skill と commands ファイルがあれば、skill が勝つ。
- plugin の skill は `/plugin名:skill名` で、名前空間が分かれるので衝突しない。

### 読み込み方 (高)

| 種類 | 常時文脈に入るもの | 呼ばれたときに入るもの |
|---|---|---|
| CLAUDE.md | 全文 | なし |
| skill | 説明文 | 本文 |
| `disable-model-invocation: true` の skill | なし | `/name` で呼んだときの本文 |

- `/compact` 後、起動時の読み込み内容は再注入される。skill の説明文の一覧は再注入されない。呼び出し済みの skill は本文が再添付される (1 つにつき先頭 5,000 トークン、合計 25,000 トークンまで)。

### CLAUDE.md と skill の結びつけ方 (高が 2 つ、中が 1 つ)

- 役割分担 (高): CLAUDE.md に常に守るルール、skill に手順や参考資料を置く。
- skill の中から `@path` で他ファイルを取り込む。(高)
- CLAUDE.md に skill 名を書いて呼び出しを促す。(中) 公式に明確な記述はない。確実に呼ばせたいなら `/name` を使う。

### 自動起動の限界 (中)

- 公式は「説明文が曖昧だったり重なっていたりすると、別の skill が選ばれるか見逃される」と書いている。(高)
- skill-creator の資料は「Claude が skill を参照するのは、自分では簡単に処理できないタスクのときだけ」と書いている。単純な 1 手の依頼は、説明文が合っていても skill が呼ばれないことがある。(高)
- 「`ALWAYS invoke…` と書くと発動率が 100% になる」という第三者の主張は、検証できなかった。(低)

## 4. agents (サブエージェント)

### 位置づけ (高)

- 独立した定義ファイル。`name` と `description` が必須で、本文がそのまま agent のシステムプロンプトになる。
- 新しいコンテキストで動き、メインに戻るのは最終メッセージだけ。

### 置き場所と優先順位 (高)

| 優先 | 場所 |
|:-:|:-|
| 1 | managed settings |
| 2 | `--agents` CLI フラグ |
| 3 | `.claude/agents/` (プロジェクト) |
| 4 | `~/.claude/agents/` (ユーザー) |
| 5 | plugin の `agents/` |

- skill は個人がプロジェクトに優先する。agent はプロジェクトが個人に優先する。向きが逆である。
- 同名は 1 つに絞られ、統合されない。

### skill との結びつき (高)

- agent 側の `skills:` に並べた skill は、起動時に全文が agent の文脈へ入る (上限 32 件)。
- skill 側の `context: fork` と `agent:` で、skill の本文を agent への指示として実行できる。
- skill の中に agent ファイルを同梱する公式の形はない。

### 文脈と費用 (高)

- agent の `name` と `description` は、全セッションの全ターンで文脈に入る。合計が約 15,000 トークンを超えると警告が出る。
- Explore と Plan は CLAUDE.md を読まない。そのため軽い。
- 公式のベストプラクティスは、1 つの目的に絞り、`tools` で権限を絞ること。

### plugin の制約 (高)

- plugin 内の agent は、`hooks`、`mcpServers`、`permissionMode`、`initialPrompt` が無視される。
- 配布が目的でなければ、plugin 化は不要。単体のファイルで足りる。

### 入れ子の深さ (高、ただし変遷あり)

- 現行の既定は 3 層、同時実行は 20 まで (v2.1.219 以降)。公式ブログの「5 階層」は古い情報。

### 既知の問題 (中)

- `CLAUDE_CODE_SUBAGENT_MODEL` が agent の `model` を上書きする報告が、複数ある (#91160、#85592、#80902)。いずれも open で、現行での再現は未確認。

## 5. skill を作るときの原則 (skill-creator と、このリポジトリでの経験)

- 説明文は起動の唯一の手がかり。何をするか、いつ使うかを書き、「スキル名が出なくても使う」と加える。(高)
- 本文は必要なときだけ読まれるので、詳しく書いてよい。ただし、重い雛形や実例は `assets/` や `references/` に分ける。(高)
- 実例を `grep` で探させる指示より、雛形を `assets/` に同梱する方が確実。実例は、リポジトリの変化で消える。(中、このリポジトリでの経験)
- 本文に具体的なツール名を書かない。名前が古くなると、本文も古くなる。意味が伝わる言い方にする。(このリポジトリの方針)
- 雛形を作ったら、生成して実行して検証する。雛形のコメントに書いた `version = "..."` が、更新ワークフローの `sed` と `grep` に全一致で拾われる不具合は、検証して初めて見つかった。(実測)
- このリポジトリの方針: 説明文は短い英語、本文は日本語。

## 6. skill の評価で分かったこと (実測)

### 説明文のトリガー測定

- `skill-creator` の `run_loop.py` / `run_eval.py` は、対象の skill を一時コマンドとして登録して測る。最初のツール呼び出しが `Skill` か `Read` 以外 (`Grep`、`Bash` など) だと、その場で「反応なし」と判定して打ち切る。リポジトリのファイルを調べに行く質問では、recall が実際より大きく低く出る。(高、コードで確認)
- add-npm-pkg では機能したが、add-auto-update-tool では recall が 6〜11% と出た。本物の skill を評価用のプロジェクトに入れて `claude -p` で測り直すと、100% だった。(実測)
- 質問には、紛らわしい近接の話題 (別の skill の領域、既に対処済みのもの) を入れる。他の skill との切り分けも測れる。

### 本文の評価

- 3 つの skill (add-npm-pkg、add-auto-update-tool、wrap-app-permission) のどれも、skill を使わない run と、同じ結果になった。リポジトリの実例と CLAUDE.md で解ける課題だったため。(中)
- 評価で意味があったのは、次の 2 点だった。
  - 罠の課題で、無駄な変更をせずに止まれるか (対処済み、対象外、前提が成り立たない)。
  - skill の型の分類にない解き方が現れるか (AeroSpace は、ランチャーではなく .app の複製と再署名で解かれた)。
- 課題の前提は、事前に確かめる。nixpkgs にあるツールを「ない」前提で課題にして、無効になった。
- 採点スクリプトの誤判定が多い。「未実行」と書いた行を実行と数える、元からある文字列を新規と数える、フラグの違いに合わない正規表現。失敗が出たら、まず採点側を疑って、実物を見る。

## 7. 環境上の落とし穴 (このリポジトリ)

- `sed -i` は BSD と GNU で挙動が違う。ファイル編集には使わず、Edit ツールを使う。(グローバルの禁止事項)
- flake は git で追跡されたファイルしか見えない。新規ファイルは `git add -N` する。
- `pgrep -f` は、自分自身のシェルのコマンド文字列にも一致する。待機ループに使うと、永遠に終わらない。
- サブエージェントの評価は、使い捨てのクローンで行う。実リポジトリを触らせない。
- `nh darwin switch` はユーザーが実行する。Claude は実行しない。

## 8. 根拠の限界

- 公式ドキュメントの取得は、小さいモデルが要約している。細部の取りこぼしがありうる。
- `/memory` や `/context` で、実際に読み込まれたファイルを確認することはしていない。
- 「衝突時にどちらが勝つか」は公式が曖昧なまま。実挙動の検証はしていない。
- 自作 agent を作って動かす検証はしていない。
- WebSearch は米国向けのみで、日本語の情報源は調べていない。
- 評価は、1 つのモデル (Sonnet 5.5) と少数の課題での結果。一般化できない。

## 出典

- [How Claude remembers your project](https://code.claude.com/docs/en/memory)
- [Skills](https://code.claude.com/docs/en/skills)
- [Subagents](https://code.claude.com/docs/en/sub-agents)
- [Plugin components](https://code.claude.com/docs/en/plugins/components)
- [Extend Claude Code](https://code.claude.com/docs/en/features-overview)
- [Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more)
- [anthropics/claude-code CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
