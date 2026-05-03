#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- ユーティリティ ---
bold="\033[1m"
green="\033[32m"
yellow="\033[33m"
reset="\033[0m"

step() { echo -e "\n${bold}==> $1${reset}"; }
ok()   { echo -e "${green}  ✓ $1${reset}"; }
note() { echo -e "${yellow}  ! $1${reset}"; }

# --- 1. Xcode Command Line Tools ---
step "Xcode Command Line Tools"
if xcode-select -p &>/dev/null; then
  ok "インストール済み"
else
  xcode-select --install
  echo "  インストーラーが開きます。完了後、Enter を押して続行してください。"
  read -r
fi

# --- 2. Nix (Determinate Nix) ---
step "Nix"
if command -v nix &>/dev/null; then
  ok "インストール済み"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  # シェルを再読み込みしてパスを通す
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# --- 3. Homebrew ---
step "Homebrew"
if command -v brew &>/dev/null; then
  ok "インストール済み"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon のパスを通す
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# --- 4. dotfiles クローン ---
step "dotfiles"
if [[ -d "$HOME/dotfiles/.git" ]]; then
  ok "クローン済み ($HOME/dotfiles)"
else
  git clone git@github.com:reinmuth66/dotfiles.git "$HOME/dotfiles"
fi

# --- 5. nix-darwin 初回適用 ---
step "nix-darwin switch"
if command -v darwin-rebuild &>/dev/null; then
  ok "nix-darwin インストール済み — switch を実行"
  sudo darwin-rebuild switch --flake "$DOTFILES_DIR"
else
  nix run nix-darwin -- switch --flake "$DOTFILES_DIR"
fi

# --- 6. 認証情報 ---
step "GitHub CLI 認証"
if gh auth status &>/dev/null; then
  ok "認証済み"
else
  gh auth login
fi

step "~/.gitconfig の削除 (Nix 管理の git config を有効化)"
if [[ -f "$HOME/.gitconfig" ]]; then
  rm "$HOME/.gitconfig"
  ok "削除しました"
else
  ok "すでに存在しない"
fi

# --- 完了 ---
echo -e "\n${bold}セットアップ完了${reset}"
note "手動設定が必要なファイル:"
note "  ~/.config/git/config.local — git のメールアドレス設定"
note "  ~/.claude/settings.json    — Claude Code の権限・フック設定"
note "  ~/.config/gh/hosts.yml     — GitHub CLI の認証情報"
