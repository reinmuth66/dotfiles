# dotfiles

nix-darwin + home-manager で macOS (aarch64) の環境を管理する dotfiles。

## セットアップ

### 前提条件

SSH キーを GitHub に登録済みであること。

### 手順

```bash
git clone git@github.com:reinmuth66/dotfiles.git ~/dotfiles && ~/dotfiles/scripts/setup.sh
```

スクリプトが以下を順番に実行する:

1. Xcode Command Line Tools
2. Nix (Determinate Nix)
3. Homebrew
4. nix-darwin 初回適用
5. GitHub CLI 認証 (`gh auth login`)
6. `~/.gitconfig` 削除 (Nix 管理の git config を有効化)

### セットアップ後の手動設定

| ファイル | 内容 |
|---|---|
| `~/.config/git/config.local` | git のメールアドレス設定（下記参照） |
| `~/.claude/settings.json` | Claude Code の権限・フック設定 |
| `~/.config/gh/hosts.yml` | GitHub CLI の認証情報 |

**`~/.config/git/config.local` の作成:**

```
[user]
	email = your-email@example.com
```

## 日常のワークフロー

### 設定を適用する

```bash
git -C ~/dotfiles add .
sudo darwin-rebuild switch --flake ~/dotfiles
stty sane
git -C ~/dotfiles commit -m "メッセージ"
git -C ~/dotfiles push
```

### flake inputs を更新して適用する

Renovate が自動で PR を作成する。マージ後に設定を適用する。

手動で更新する場合:

```bash
nix flake update ~/dotfiles
git -C ~/dotfiles add .
sudo darwin-rebuild switch --flake ~/dotfiles
stty sane
git -C ~/dotfiles commit -m "update: nix flake update"
git -C ~/dotfiles push
```

### Homebrew cask を更新する

大半のアプリはアプリ自身が自動更新する。手動で全 cask を更新する場合:

```bash
brew upgrade --cask
```

### Google 日本語入力のアイコン復元

`topgrade` 実行後にアイコンが上書きされた場合:

```bash
sudo cp ~/dotfiles/assets/hiragana_mono.tiff "/Library/Input Methods/GoogleJapaneseInput.app/Contents/Resources/hiragana.tiff"
```
