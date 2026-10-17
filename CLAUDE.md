# CLAUDE.md

## 概要

nix-darwin + home-manager で macOS (aarch64) の環境を管理する dotfiles リポジトリ。Nix flake ベース。

- `flake.nix` — エントリポイント。`darwinConfigurations."ReinmuthLaptop"` を定義
- `modules/darwin.nix` — nix-darwin 設定 (Homebrew cask 管理など)
- `modules/home.nix` — home-manager エントリ (パッケージ、全モジュールの import)
- `modules/<tool>.nix` — ツールごとの設定モジュール
- `config/` — `programs.*` で表現できないツールの設定ファイル実体

`nh darwin switch`を行うまで実際の環境には反映されない。ただし、そのコマンドはユーザーが実行する。

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
- `czg.nix`: conventional commit の TUI。`importNpmLock` で `pkgs/czg/` から作る
