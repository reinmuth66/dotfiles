# dotfiles

## セットアップ

### 前提条件

SSH キーを GitHub に登録済みであること。

### 手順

```bash
git clone git@github.com:reinmuth66/dotfiles.git ~/dotfiles && ~/dotfiles/scripts/setup.sh
```

スクリプトが以下を順番に実行する:

1. Xcode Command Line Tools
2. Nix
3. Homebrew
4. dotfiles クローン (未クローンの場合)
5. nix-darwin 初回適用
6. GitHub CLI 認証 (`gh auth login`)
7. `~/.gitconfig` 削除 (Nix 管理の git config を有効化)

### セットアップ後の手動設定

| ファイル | 内容 |
|---|---|
| `~/.config/git/config.local` | git のメールアドレス設定（下記参照） |
| `~/.claude/settings.json` | Claude Code の権限・フック設定 |
| `~/.config/gh/hosts.yml` | GitHub CLI の認証情報 |
| リポジトリの secret `CREATE_PR_TOKEN` | 自動更新 PR の作成に使う fine-grained token（下記参照） |

**`~/.config/git/config.local` の作成:**

```
[user]
	email = your-email@example.com
```

**`CREATE_PR_TOKEN` の作成:**

`GITHUB_TOKEN` で作った PR では `check.yaml` が走らないため、自動更新の PR はこのトークンで作る。

1. GitHub の Settings → Developer settings → Fine-grained tokens で、次の内容のトークンを作る
   - Repository access: このリポジトリだけ
   - Permissions: Contents と Pull requests を Read and write
2. リポジトリの Settings → Secrets and variables → Actions に `CREATE_PR_TOKEN` として登録する
3. トークンの期限が切れると自動更新が失敗し、Issue が作られる。そのときは作り直して登録し直す

## 日常のワークフロー

### 設定を適用する

```bash
git -C ~/dotfiles add .
nh darwin switch ~/dotfiles
```

### flake inputs を更新して適用する

GitHub Actions (`.github/workflows/update-flake.yaml`) が毎週月曜に PR を作成する。マージ後に設定を適用する。Renovate は GitHub Actions のバージョン更新だけを担当する。

手動で更新する場合:

```bash
nix flake update ~/dotfiles
git -C ~/dotfiles add .
nh darwin switch ~/dotfiles
```

### `.DS_Store` の削除

```bash
sudo fd -H -I -t f -g ".DS_Store" / -X rm 2>/dev/null
```

### Homebrew cask を更新する

大半のアプリはアプリ自身が自動更新する。手動で全 cask を更新する場合:

```bash
brew upgrade --cask
```

### 古い Nix ビルドを削除する

nix-darwin の `nix.gc` により、毎週月曜 0:00 に 7 日より古い世代と、参照されなくなったストアパスが自動的に削除される(`modules/darwin.nix`)。ログは `/var/log/nix-gc.log`。

手動で実行する場合:

```bash
sudo nix-collect-garbage --delete-older-than 7d
```

### Google 日本語入力のアイコン復元

アプリの更新で元のアイコンに戻っても、`nh darwin switch` のたびに `modules/darwin.nix` の activation script がモノクロ版を書き戻す。反映されない場合は、ログインし直す。

switch を待たずに手動で戻す場合:

```bash
sudo cp ~/dotfiles/assets/hiragana_mono.tiff "/Library/Input Methods/GoogleJapaneseInput.app/Contents/Resources/hiragana.tiff"
```
