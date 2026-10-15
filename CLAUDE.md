# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

nix-darwin + home-manager で macOS (aarch64) の環境を管理する dotfiles リポジトリ。Nix flake ベース。

- `flake.nix` — エントリポイント。`darwinConfigurations."ReinmuthLaptop"` を定義
- `modules/darwin.nix` — nix-darwin 設定 (Homebrew cask 管理など)
- `modules/home.nix` — home-manager エントリ (パッケージ、全モジュールの import)
- `modules/<tool>.nix` — ツールごとの設定モジュール
- `config/` — `programs.*` で表現できないツールの設定ファイル実体

`nh darwin switch`を行うまで実際の環境には反映されない。ただし、そのコマンドはユーザーが実行する。

## アーキテクチャのポイント

**パッケージ管理の分担:**
- nixpkgs `programs.*` (各 `modules/<tool>.nix`) — CLI ツールの設定を含む管理
- nixpkgs `home.packages` (`modules/home.nix`) — 設定不要な CLI ツール
- Homebrew casks (`modules/darwin.nix`) — nixpkgs にない GUI アプリ
- `importNpmLock` (`pkgs/<tool>/`) — nixpkgs にない npm パッケージ

**モジュール構成:**

| モジュール | 内容 |
|---|---|
| `zsh.nix` | zsh、zoxide、direnv、fzf |
| `git.nix` | programs.git、programs.delta、programs.lazygit |
| `atuin.nix` | programs.atuin |
| `bat.nix` | programs.bat |
| `bottom.nix` | programs.bottom|
| `gh.nix` | programs.gh |
| `starship.nix` | programs.starship|
| `ghostty.nix` | xdg.configFile (config/ghostty/config) |
| `zed.nix` | xdg.configFile (config/zed/) |
| `wezterm.nix` | xdg.configFile (config/wezterm/) |
| `nvim.nix` | neovim パッケージ + xdg.configFile (config/nvim/) |
| `yazi.nix` | yazi パッケージ + xdg.configFile (config/yazi/ + プラグイン) |
| `claude.nix` | home.file (config/claude/) |
| `czg.nix` | importNpmLock (pkgs/czg/) — conventional commit TUI |
| `sketchybar.nix` | programs.sketchybar |
| `mole.nix` | update-mole.yaml |
| `cavaviz.nix` | Spotify ポップアップの背景と棒グラフを描くサウンドビジュアライザ (pkgs/cavaviz/ の CavaViz.app + cava の設定とシェーダー) |

**config/ に設定ファイルを置くツール:**
- `programs.*` で表現できない、または Lua/JSON-with-comments など Nix に変換しにくいもの
- ghostty、zed、wezterm、nvim、yazi、claude、sketchybar

**新しいツールを追加する手順:**
1. `programs.*` サポートがあるなら `modules/<tool>.nix` を新規作成し `home.nix` の `imports` に追加
2. 設定不要な CLI ツールなら `modules/home.nix` の `home.packages` に追加
3. GUI アプリなら `modules/darwin.nix` の `homebrew.casks` に追加
4. 設定ファイルが必要なら `config/<tool>/` に置き、モジュール内で `xdg.configFile` を宣言
5. nixpkgs にない npm パッケージなら `/add-npm-pkg` スキルを使って追加
6. Nix ストアのパスが変わるたびに macOS の権限 (Accessibility など) が外れるなら `/wrap-app-permission` スキルで .app に包む
7. nixpkgs にない外部ツールをリリースタグに固定し、新タグが出たら自動で PR を作りたいなら `/add-auto-update-tool` スキルを使う
8. `fetchFromGitHub` + `rev` 固定で持つソースを自動更新したいなら、`flake = false` の input にする (`/add-auto-update-tool` スキルの方式 C)。`catppuccin-bat`、`zeno-zsh`、`swiftterm`、`pdf-cli` が実例
