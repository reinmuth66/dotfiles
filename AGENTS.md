# AGENTS.md

## 概要

nix-darwin + home-manager で macOS (aarch64) の環境を管理する dotfiles リポジトリ。Nix flake ベース。

- `flake.nix` — エントリポイント。inputs だけを書く
- `flake/` — 出力を定義する flake-parts モジュール。`hosts.nix` が `darwinConfigurations."ReinmuthLaptop"`、`packages.nix` が自前パッケージ、`formatter.nix` が整形・lint・pre-commit フック、`apps.nix` が `nix run` のアプリを定義する
- `modules/darwin.nix` — nix-darwin 設定 (Homebrew cask 管理など)
- `modules/home.nix` — home-manager エントリ (パッケージ、全モジュールの import)
- `modules/<tool>.nix` — ツールごとの設定モジュール
- `config/` — `programs.*` で表現できないツールの設定ファイル実体
- `config/design-system/` — デザインシステム「modern」の正本。`project/` がトークン・説明・部品の CSS、`src/` が React の部品、`tools/` が色を法則から計算するスクリプト。claude.ai の Artifact に publish する
- `pkgs/<name>/default.nix` — 自前でビルドするパッケージ。パッチなど関連ファイルも同じディレクトリに置く。単体で使えるものは `flake/packages.nix` に登録し (`nix build .#<name>` でビルドできる)、モジュールからは `inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.<name>` で参照する
- flake の input は `inputs` としてモジュールに渡る。モジュールでは `inputs.<name>` で参照する

`nh darwin switch`を行うまで実際の環境には反映されない。ただし、そのコマンドはユーザーが実行する。

ファイルを編集したら `nix fmt` で整形する (treefmt が `.nix`、`.lua`、シェルスクリプトを整形する)。`nix flake check` が、整形・statix・deadnix・gitleaks を確認する。CI (`check.yaml`) は、それに加えてシステム全体のビルドを確認する。

同じ検査は commit 前にも走る。フックは dev shell に入ると `.git/hooks` に入る (direnv を許可してあれば自動、そうでなければ `nix develop`)。

GitHub Actions のアクションは commit SHA で固定し、タグをコメントに書く。Nix は `.github/actions/setup-nix` で入れる。

## 新しいツールを追加する

追加先は、次の順に探して、最初に当てはまるものを使う。

1. nixpkgs に `programs.*` がある — `modules/<tool>.nix` を新規作成し、`modules/home.nix` の `imports` に追加する
2. nixpkgs にあるが `programs.*` が無い、設定不要な CLI ツール — `modules/home.nix` の `home.packages` に追加する
3. nixpkgs にない GUI アプリ — `modules/darwin.nix` の `homebrew.casks` に追加する
4. 上のどれにも当てはまらない場合は、固定して持つ。
   - nixpkgs にない npm パッケージ: `/add-npm-pkg` スキルを使う (`pkgs/<tool>/` に `importNpmLock` で置く。実例は `czg`)
   - nixpkgs にない外部ツールをリリースタグに固定し、新タグが出たら自動で PR を作りたい: `/add-auto-update-tool` スキルを使う。自動更新のワークフローは、失敗を Issue にする `.github/actions/notify-failure` を呼ぶ
   - `fetchFromGitHub` + `rev` 固定で持つソースを自動更新したい: `flake = false` の input にする (`/add-auto-update-tool` スキルの方式 C)。実例は `catppuccin-bat`、`zeno-zsh`、`pdf-cli`

## 設定ファイルと補足

- 設定ファイルは、`programs.*` で表現できない、または Lua や JSON-with-comments など Nix に変換しにくい場合に、`config/<tool>/` に置く。モジュール内で `xdg.configFile` を宣言する。
- Nix ストアのパスが変わるたびに macOS の権限 (Accessibility など) が外れるなら、`/wrap-app-permission` スキルで `.app` に包む。
- `~/.claude/CLAUDE.md` と `statusline.sh` は、`modules/claude.nix` が `config/claude/` から配る。

## モジュールの補足

モジュールの一覧は持たない (`ls modules/` で分かる)。コードから分からないことだけを、ここに書く。

- `zsh.nix`: zsh のほかに、zoxide、direnv、fzf の設定も含む
- `git.nix`: git のほかに、delta と lazygit の設定も含む
- `spicetify.nix`: Spotify と spicetify-cli は nixpkgs-spotify の rev で固定し、`update-spotify.yaml` が、猶予期間・互換性・ビルドを確認してから PR で更新する
- `cavaviz.nix`: Spotify ポップアップの背景と棒グラフを描くサウンドビジュアライザ。`pkgs/cavaviz/` の CavaViz.app と、cava の設定とシェーダーからなる
- `mole.nix`: タグ固定の flake input。`update-mole.yaml` が新しいリリースで PR を作る
- `marp.nix`: テーマ `modern` は手で書かず、`pkgs/marp-theme/` がデザインシステムから組み立てる (`nix build .#marp-theme` で確認できる)
  - 連結の順は、`tokens.json` から作る変数、`components/bundle.css` (部品)、`config/marp/layout.css` (marp 固有のレイアウト)
  - 色、文字サイズ、余白、角丸、線の値は `config/design-system/project/tokens.json` にだけ書く。CSS では変数で指す。色の直書きは `nix flake check` (`checks.marp-theme`) が止める
  - 色は OKLCH の法則から計算した 16 進の値。法則は `tokens.json` の `meta` と `README.md` にある。計算は `config/design-system/tools/color.py` が行う (`python3 color.py ladder <色相の角度>` で 7 段の値が出る)。色相を足すときは、`meta.colorRule.hue` に名前と角度を足し、`python3 color.py check <tokens.json>` が出す値を書く。`nix flake check` (`checks.design-system-colors`) が、全ての色が法則どおりかを確かめる
  - 部品 (目次、card、box、配置、図) の見た目は `components/bundle.css` に 1 か所だけ書く。React の部品 (`config/design-system/src/index.jsx`) は、その class を付けた HTML を出すだけにする
  - marp では、エンジンの拡張 (`config/marp/engine/`、`pkgs/marp-engine/` がまとめて `~/.config/marp/engine/` に配る) が、`:::` の記法、章の番号とフッターの自動反映、図の線を足す。外部のパッケージは使わない。図の線を描く `config/design-system/src/connector.js` は、拡張と React の部品が共有する
  - `marp` コマンドは marp-cli を包んだもの (`pkgs/marp/`)。`~/.marprc.yml` を必ず読み、端末以外から呼ばれたときは標準入力を待たない。シェルの関数にしない (`timeout` やエージェント越しでは関数を通らず、拡張が効かないまま変換が成功してしまう)
  - 書き方の説明は `config/marp/README.md`。記法や部品を変えたら、この README、`config/marp/skill/SKILL.md` (AI エージェント用の skill `marp-modern`。`~/.claude/skills/marp-modern/` に配る)、デザインシステムの `components/<部品>/README.md` を合わせて直す
  - skill `marp-modern` は、テーマと拡張の記法の一覧だけを書く。それ 1 つで足りるようにし、書き方は例ではなく形 (`<名前>` や `[省ける部分]`) で示し、「する」ことだけを書く。スライドの作り方 (構成、文章、枚数) は書かない (別の skill にする。Issue #74)。試験は `config/marp/skill/evals/` にある
  - 拡張と線の試験は `node --test` で書き、`nix flake check` (`checks.marp-engine`) が走らせる。`checks.design-system` は、React の部品をまとめた `bundle.js` を確かめる
  - デザインシステムは <https://claude.ai/artifact/LvnvWfqkhouGZxRA2cieud> にある。`config/design-system/` を変えたら publish する。`bundle.js` はリポジトリに置かないので、`nix build .#design-system` の結果 (`result/project/`) をスクラッチパッドにコピーし、それを `root` にして Artifact ツールで同じ URL に送る。`index.d.ts` は `contentType: text/plain` を付ける。索引 `design-system.json` は、直前に読み直してから最後に送る
- `czg.nix`: conventional commit の TUI。`importNpmLock` で `pkgs/czg/` から作る
- `claude.nix`: Claude Code 本体は `nix-claude-code` input の overlay (`darwin.nix`) で入れる。`update-claude-code.yaml` が、この input だけを毎日更新して PR を作る。MCP サーバーは `programs.claude-code.mcpServers` で宣言する
  - `settings.json` は丸ごと置き換えず、activation で jq マージする。Nix に書いたキーが勝ち、`enabledPlugins` や `permissions.allow` など Claude Code が書き込むものは残る。`hooks` だけは Nix の内容で置き換える
  - 自前の mod は `config/claude/mods/<名前>/` に置く。`~/.claude/mods/<名前>` へ `mkOutOfStoreSymlink` で配り、`settings.env.CLAUDE_CODE_PLUGIN_DIRS` に書いて常に読み込ませる (新しい mod は switch が要る)。Claude Code が mod のフォルダに書く `.claude-plugin/types/` は `.gitignore` 済み。`hide-tools` は herdr の中 (`HC_TERMINAL_ID` がある) だけ、会話の中のツールの行を消す (ctrl+o で出る)
  - `agy` は `agy:worker` サブエージェントを定義し、その要求をモデルに送らず agy (`pkgs/antigravity-cli/`) の headless 実行 (auto mode は `agy-settings.json` の `agentMode` で示す。headless の `--mode auto` は公開のフラグで止められていて警告が出るので付けない。git の書き込みは `agy-settings.json` の deny と `git-hooks/` で止め、前後の refs の比較で気づく) に回す。判断の部分は `hooks/logic.mjs` にあり、`checks.claude-scripts` が試す
  - `CLAUDE.md` と `statusline.sh` は `mkOutOfStoreSymlink` で dotfiles を直接指すので、編集は switch なしで反映される
- `herdr-app.nix`: herdr アプリの設定と自前の mod (`config/herdr-app/`)
  - mod は自分のフォルダの外を `import` できない。共通の部品は `config/herdr-app/shared/` の正本を、使う mod のフォルダへ `cp` で同じ中身に写す。`shared/shared.test.js` が一致を確かめる
  - Claude Code から mod へは `~/.config/herdr-app/data/` で渡す。`config/claude/statusline.sh` が `limits/` と `sessions/`、`config/claude/hooks/herdr-record.mjs` が `activity/` と `edits/` を書き、mod が `watchJsonDir` で読む。どちらも herdr の外 (`HC_TERMINAL_ID` がない) では何も書かない
  - mod のフォルダは dotfiles への out-of-store のリンク。中のファイルの編集はレイアウトを読み直せば効く (`layout.switch` で別のレイアウトへ移ってから戻す)。新しい mod や新しくリンクするファイルは switch が要る
- `gh-dash.nix`: Issue の一覧で `C` が `herdr-issue-task` (Issue を herdr の新しいタブの Claude Code に渡す)、`N` が herdr の新しいタブで `gh issue create` を開く。組み込みの `C` (checkout) は上書きしている
- `agent-skills.nix`: ユーザー全体の skill を agent-skills-nix で `~/.claude/skills` に配る。取得元は flake input ではなく `config/agent-skills/registry/sources/*.nix` で固定し、`nix run .#skills-sources-lock -- --manifest-dir config/agent-skills/registry/sources --lock-file config/agent-skills/registry/sources.lock.json` で更新する (`update-agent-skills.yaml` が週次で実行)。hooks や agents を含むプラグイン (superpowers など) は `/plugin` で管理する
