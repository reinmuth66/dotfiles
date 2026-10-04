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
| `cavaviz.nix` | Spotify ポップアップの背景と棒グラフを描くサウンドビジュアライザ (pkgs/cavaviz/ の CavaViz.app + cava の設定とシェーダー) |

**config/ に設定ファイルを置くツール:**
- `programs.*` で表現できない、または Lua/JSON-with-comments など Nix に変換しにくいもの
- ghostty、zed、wezterm、nvim、yazi、claude

**CavaViz (サウンドビジュアライザ) の注意:**
- cava の SDL 版に `pkgs/cavaviz/sdl-window.patch` (枠なし・window level 100。SketchyBar のポップアップは 101 なので、ポップアップの文字や画像が窓の上に描かれる) と `sdl-transparent.patch` (窓の透明化。sdl2-compat 経由で SDL3 の透明フラグを渡す。背景はシェーダーがアルファ 0 で描く) を当て、`/usr/bin/codesign` で ad-hoc 署名した .app にする。署名はビルド中に行うので、Nix のサンドボックスが無効 (`sandbox = false`) であることが前提。
- 音声の取得 (Core Audio tap) には「システムオーディオ録音」の許可が要る。初回だけ、ポップアップを開いて再生すると macOS 標準のダイアログが出るので「許可」を押す (そのときの最初の起動は失敗するが、次から動く)。システム設定の「システムオーディオ録音のみ」に `~/Applications/Home Manager Apps/CavaViz.app` を手で追加しても付けられる (一覧に出なくても、`TCC.db` には記録される)。署名の指定要件を識別子 (`local.dotfiles.cavaviz`) だけにしてあるので、cava を更新しても許可は外れない。識別子を変えると、許可を付け直す必要がある (古い項目は `tccutil reset AudioCapture <識別子>` で消せる)。
- 窓は Retina 解像度で描き (`sdl-highdpi.patch`)、位置は NSWindow に小数で渡す (`sdl-fractional-position.patch`)。SketchyBar のポップアップは半ポイント位置に描かれることがあり、整数 pt にしか置けないと、再生/停止で背景を受け渡すときに枠がずれて見えるため。
- 窓はポップアップの背景全体 (中身の左端から始まり、右と上下に枠の太さの分だけ広い。SketchyBar の `popup.c`) と同じ位置と大きさで、ポップアップの下に敷く。背景、枠 (角丸)、棒グラフは `pkgs/cavaviz/popup.frag` が描き、窓が出ている間は SketchyBar 自身のポップアップの背景を透明にして、文字・カバー画像・再生位置のバーが棒グラフの上に描かれるようにする (別の窓の前後は window level でしか決まらず、1 つの窓の中の背景と文字の間には入れないため)。棒の領域の位置と大きさ・角の半径・枠の太さは、`popup.frag` の定数と `spotify.lua` の `VIZ_*` / `POPUP_BG_*` で同じ値にする。棒の不透明度は `popup.frag` の `BAR_ALPHA`。
- 起動と停止は `config/sketchybar/items/spotify.lua` が行う。再生中にホバーすると、ポップアップをすぐ開いてフェードインさせながら、cava を画面外に隠して起動し、アニメーションの終わりと準備完了の遅いほうで窓を出す (アニメーションの長さ `FADE_IN_FRAMES_VIZ` を、cava の準備にかかる時間の約 0.4 秒に合わせてある)。ホバーが外れる、または再生が止まると止める。

**Spotify ポップアップの配色:**
- `config/sketchybar/palette.lua` が、アルバム画像の色の頻度表 (ImageMagick で抽出。`sketchybar.nix` の `extraPackages` に `imagemagick`) から、アクセント・背景・文字の色を決める。無彩色の画像は従来の固定色に戻す。
- 背景の色相は有彩色の加重平均、彩度と明るさは画像全体の平均色から決める。背景の明るさは、画像の明るさ (L*) が暗い背景と明るい背景のどちらに近いかで決め、文字・再生バー・棒グラフの色は背景とのコントラスト比を確保して、背景が暗いときは明るく、明るいときは暗く作る。
- 棒・背景・枠の色は、`modules/cavaviz.nix` の設定ひな形の `@FG@` `@BG@` `@BORDER@` (グラデーションの 3 色として `popup.frag` に渡す)。起動時に `spotify.lua` が置き換え、動いている cava には設定を書き直して `SIGUSR2` を送る。cava が `SIGUSR2` で読み直すのはグラデーションの色だけで、`foreground` / `background` は読み直されないため、グラデーションで指定している (窓は作り直さない)。窓が出たあと (準備完了と `show` の指示がそろってから) にポップアップ自身の背景を透明にし、止めるときは先に不透明へ戻してから窓を隠す。cava が準備完了 (`cavaviz_ready`) になる前に送ると、シグナルの受け口がなく終了するので、準備完了のあとに送る。

**新しいツールを追加する手順:**
1. `programs.*` サポートがあるなら `modules/<tool>.nix` を新規作成し `home.nix` の `imports` に追加
2. 設定不要な CLI ツールなら `modules/home.nix` の `home.packages` に追加
3. GUI アプリなら `modules/darwin.nix` の `homebrew.casks` に追加
4. 設定ファイルが必要なら `config/<tool>/` に置き、モジュール内で `xdg.configFile` を宣言
5. nixpkgs にない npm パッケージなら `/add-npm-pkg` スキルを使って追加
6. `nh darwin switch ~/dotfiles` で適用
