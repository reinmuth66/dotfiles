# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

nix-darwin + home-manager で macOS (aarch64) の環境を管理する dotfiles リポジトリ。Nix flake ベース。

- `flake.nix` — エントリポイント。`darwinConfigurations."ReinmuthLaptop"` を定義
- `modules/darwin.nix` — nix-darwin 設定 (Homebrew cask 管理など)
- `modules/home.nix` — home-manager エントリ (パッケージ、全モジュールの import)
- `modules/<tool>.nix` — ツールごとの設定モジュール
- `config/` — `programs.*` で表現できないツールの設定ファイル実体

## 重要: 設定変更の反映方法

`modules/` または `config/` 以下のファイルを編集しても、**`nh darwin switch` を実行するまで実際の環境には反映されない。**

`~/.config/` 以下のファイルは Nix ストアへのシンボリックリンクであり、`nh darwin switch` によって初めて新しいストアパスに切り替わる。

## よく使うコマンド

```bash
# 設定を適用する
git -C ~/dotfiles add .
nh darwin switch ~/dotfiles
```

`nh darwin switch` は `sudo` を付けずに実行する。

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
| `gh.nix` | programs.gh |
| `starship.nix` | programs.starship (設定含む) |
| `ghostty.nix` | xdg.configFile (config/ghostty/config) |
| `zed.nix` | xdg.configFile (config/zed/) |
| `wezterm.nix` | xdg.configFile (config/wezterm/) |
| `nvim.nix` | neovim パッケージ + xdg.configFile (config/nvim/) |
| `yazi.nix` | yazi パッケージ + xdg.configFile (config/yazi/ + プラグイン) |
| `claude.nix` | home.file (config/claude/) |
| `czg.nix` | importNpmLock (pkgs/czg/) — conventional commit TUI |
| `cavaviz.nix` | Spotify ポップアップの円形サウンドビジュアライザ (pkgs/cavaviz/ の CavaViz.app + cava の設定) |

**config/ に設定ファイルを置くツール:**
- `programs.*` で表現できない、または Lua/JSON-with-comments など Nix に変換しにくいもの
- ghostty、zed、wezterm、nvim、yazi、claude

**CavaViz (サウンドビジュアライザ) の注意:**
- cava の SDL 版に `pkgs/cavaviz/sdl-window.patch` を当て、`/usr/bin/codesign` で ad-hoc 署名した .app にする。署名はビルド中に行うので、Nix のサンドボックスが無効 (`sandbox = false`) であることが前提。
- 音声の取得 (Core Audio tap) には「システムオーディオ録音」の許可が要る。初回だけ、ポップアップを開いて再生すると macOS 標準のダイアログが出るので「許可」を押す (そのときの最初の起動は失敗するが、次から動く)。システム設定の「システムオーディオ録音のみ」に `~/Applications/Home Manager Apps/CavaViz.app` を手で追加しても付けられる (一覧に出なくても、`TCC.db` には記録される)。署名の指定要件を識別子 (`local.dotfiles.cavaviz`) だけにしてあるので、cava を更新しても許可は外れない。識別子を変えると、許可を付け直す必要がある (古い項目は `tccutil reset AudioCapture <識別子>` で消せる)。
- 起動と停止は `config/sketchybar/items/spotify.lua` が行う。再生中にホバーすると、cava を画面外に隠して起動し、準備ができてからポップアップと窓を同時に出す (ホバーから約 0.42 秒)。ホバーが外れる、または再生が止まると止める。

**新しいツールを追加する手順:**
1. `programs.*` サポートがあるなら `modules/<tool>.nix` を新規作成し `home.nix` の `imports` に追加
2. 設定不要な CLI ツールなら `modules/home.nix` の `home.packages` に追加
3. GUI アプリなら `modules/darwin.nix` の `homebrew.casks` に追加
4. 設定ファイルが必要なら `config/<tool>/` に置き、モジュール内で `xdg.configFile` を宣言
5. nixpkgs にない npm パッケージなら `/add-npm-pkg` スキルを使って追加
6. `nh darwin switch ~/dotfiles` で適用
