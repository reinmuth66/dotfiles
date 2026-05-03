# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

nix-darwin + home-manager で macOS (aarch64) の環境を管理する dotfiles リポジトリ。Nix flake ベース。

- `flake.nix` — エントリポイント。`darwinConfigurations."ReinmuthLaptop"` を定義
- `modules/darwin.nix` — nix-darwin 設定 (Homebrew cask 管理など)
- `modules/home.nix` — home-manager 設定 (パッケージ、xdg.configFile シンボリックリンク)
- `modules/zsh.nix` — zsh 設定 (home.nix から import される)
- `config/` — 各ツールの設定ファイル実体 (home.nix から `xdg.configFile` でシンボリックリンクされる)

## 重要: 設定変更の反映方法

`config/` 以下のファイルを編集しても、**`switch.sh` を実行するまで実際の環境には反映されない。**

`~/.config/` 以下のファイルは Nix ストアへのシンボリックリンクであり、`darwin-rebuild switch` によって初めて新しいストアパスに切り替わる。ファイルを編集したら必ず `switch.sh` を実行すること。

## よく使うコマンド

`switch` / `update` は `programs.zsh.shellAliases` で定義されており、**どのディレクトリからでも実行できる。**

```bash
# 設定を適用する (変更をステージング → darwin-rebuild switch → コミット&プッシュ)
switch "コミットメッセージ"

# flake inputs を更新して適用 (topgrade も実行)
update

# darwin-rebuild を直接実行 (switch を使わない場合)
sudo darwin-rebuild switch --flake ~/dotfiles
```

## アーキテクチャのポイント

**パッケージ管理の分担:**
- nixpkgs (home.packages) — CLI ツール全般
- Homebrew casks (darwin.nix) — nixpkgs にない GUI アプリ
- mise — 言語ランタイムのバージョン管理 (`config/mise/config.toml`)

**設定ファイルの管理フロー:**
1. 設定ファイルの実体は `config/` 以下に置く
2. `modules/home.nix` の `xdg.configFile` でシンボリックリンクを宣言する
3. `darwin-rebuild switch` 実行時に `~/.config/` 以下にリンクが張られる
4. 例外: `starship.toml` は `STARSHIP_CONFIG` 環境変数で直接参照 (シンボリックリンクなし)

**zsh 設定の流れ:**
- `modules/zsh.nix` ですべての zsh 設定を管理
- home-manager の `programs.zsh` が `~/.zshrc` を自動生成 (直接編集不可)
- zsh の設定を変更する場合は `modules/zsh.nix` を編集して `switch` を実行

**新しいツールを追加する手順:**
1. nixpkgs にあるなら `modules/home.nix` の `home.packages` に追加
2. GUI アプリなら `modules/darwin.nix` の `homebrew.casks` に追加
3. 設定ファイルがあるなら `config/` に置き、`home.nix` の `xdg.configFile` にエントリを追加
4. `./switch.sh` で適用
