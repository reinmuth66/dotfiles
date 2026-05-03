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

`modules/` または `config/` 以下のファイルを編集しても、**`darwin-rebuild switch` を実行するまで実際の環境には反映されない。**

`~/.config/` 以下のファイルは Nix ストアへのシンボリックリンクであり、`darwin-rebuild switch` によって初めて新しいストアパスに切り替わる。

## よく使うコマンド

```bash
# 設定を適用する
git -C ~/dotfiles add .
sudo darwin-rebuild switch --flake ~/dotfiles
stty sane
git -C ~/dotfiles commit -m "メッセージ"
git -C ~/dotfiles push
```

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

**config/ に設定ファイルを置くツール:**
- `programs.*` で表現できない、または Lua/JSON-with-comments など Nix に変換しにくいもの
- ghostty、zed、wezterm、nvim、yazi、claude

**新しいツールを追加する手順:**
1. `programs.*` サポートがあるなら `modules/<tool>.nix` を新規作成し `home.nix` の `imports` に追加
2. 設定不要な CLI ツールなら `modules/home.nix` の `home.packages` に追加
3. GUI アプリなら `modules/darwin.nix` の `homebrew.casks` に追加
4. 設定ファイルが必要なら `config/<tool>/` に置き、モジュール内で `xdg.configFile` を宣言
5. nixpkgs にない npm パッケージなら下記の手順で `importNpmLock` を使って追加
6. `sudo darwin-rebuild switch --flake ~/dotfiles` で適用

**nixpkgs にない npm パッケージを追加する手順 (`importNpmLock`):**

```bash
# 1. package.json を作成
mkdir -p pkgs/<tool>
cat > pkgs/<tool>/package.json <<EOF
{
  "name": "<tool>-nix",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "<tool>": "<version>"
  }
}
EOF

# 2. package-lock.json を生成 (node_modules は作らない)
cd pkgs/<tool> && npm install --package-lock-only
```

```nix
# 3. modules/<tool>.nix を作成
{ pkgs, ... }:
let
  nodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ../pkgs/<tool>;
    nodejs = pkgs.nodejs;
  };
  <tool> = pkgs.writeShellScriptBin "<tool>" ''
    exec ${pkgs.nodejs}/bin/node ${nodeModules}/node_modules/.bin/<tool> "$@"
  '';
in {
  home.packages = [ <tool> ];
}
```

```nix
# 4. modules/home.nix の imports に追加
imports = [ ... ./<tool>.nix ];
```

実例: `pkgs/czg/`、`modules/czg.nix`
