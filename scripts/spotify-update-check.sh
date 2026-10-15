#!/usr/bin/env bash
# nixpkgs-spotify の固定を、nixpkgs-unstable の先頭へ進めてよいかを判定する。
# update-spotify.yaml の判定ジョブから呼ばれる。ローカルでは DRY_RUN=1 で動作を確認できる (Issue を作らない)。
#
# 出力 ($GITHUB_OUTPUT。未設定なら標準出力):
#   go=true|false, candidate_rev, spotify, cli, current_spotify, current_cli, compat_low, compat_high
#
# 進めてよい条件 (上から順に判定し、満たさなければ終了する):
#   1. Spotify か spicetify-cli の版が、現在の固定と異なる
#   2. darwin.nix の最終変更から SOAK_DAYS 日以上経っている
#   3. spicetify-cli のメジャーバージョンが変わっていない (変わるなら Issue)
#   4. Spotify の版が、spicetify-cli の macOS の対応範囲に入っている (範囲外・解析失敗は Issue)
set -euo pipefail

SOAK_DAYS="${SOAK_DAYS:-7}"
DRY_RUN="${DRY_RUN:-0}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"
LABEL="spotify-update"

say() { echo "$*" >&2; }
output() { echo "$1=$2" >> "$OUT"; }
stop() { output go false; exit 0; }

# 外部から得た文字列は、検証してから使う。
valid_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }
valid_rev() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

# 先頭 3 要素を数値で比較する。a < b なら -1、a = b なら 0、a > b なら 1。
# Spotify の版は 4 要素 (1.2.98.301)、対応範囲は 3 要素 (1.3.3) なので、先頭 3 要素で揃える。
cmp3() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) {
      if (x[i] + 0 < y[i] + 0) { print -1; exit }
      if (x[i] + 0 > y[i] + 0) { print 1; exit }
    }
    print 0
  }'
}

# $1 = nixpkgs の rev。"<spotify の版> <spicetify-cli の版>" を返す。
eval_versions() {
  nix eval --impure --raw --expr "
    let
      p = import (builtins.getFlake \"github:NixOS/nixpkgs/$1\") {
        system = \"aarch64-darwin\";
        config.allowUnfree = true;
      };
    in \"\${p.spotify.version} \${p.spicetify-cli.version}\"
  "
}

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# $1 = 重複判定のキー、$2 = タイトル、$3 = 本文。同じキーの Issue が (クローズ済みも含め) あれば作らない。
# キーは本文の隠しコメントに埋め込む。検索 (--search) は反映が遅れるので使わず、ラベルで絞った一覧を見る。
open_issue() {
  local key="$1" title="$2" body="$3" existing
  existing=$(gh issue list --repo "$REPO" --label "$LABEL" --state all --limit 200 --json number,body \
    -q "[.[] | select(.body | contains(\"<!-- key:${key} -->\"))] | .[0].number // empty")
  if [ -n "$existing" ]; then
    say "Issue #${existing} が既にあるため、作成しない (key=${key})"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "[DRY_RUN] Issue を作成する: ${title}"
    say "$body"
    return 0
  fi
  gh label create "$LABEL" --repo "$REPO" --force --color 1d76db \
    --description "Spotify / spicetify-cli の自動更新に関する通知" >/dev/null
  gh issue create --repo "$REPO" --label "$LABEL" --title "$title" \
    --body "<!-- key:${key} -->
${body}"
}

# --- 1. 候補と現在の版 ---
current_rev=$(sed -nE 's|.*github:nixos/nixpkgs/([0-9a-f]{40}).*|\1|p' flake.nix | head -1)
valid_rev "$current_rev" || { say "flake.nix から nixpkgs-spotify の rev を取得できない"; exit 1; }
candidate_rev=$(gh api repos/NixOS/nixpkgs/commits/nixpkgs-unstable --jq .sha)
valid_rev "$candidate_rev" || { say "候補の rev が不正: ${candidate_rev}"; exit 1; }

read -r current_spotify current_cli <<<"$(eval_versions "$current_rev")"
read -r spotify cli <<<"$(eval_versions "$candidate_rev")"
valid_version "$spotify" && valid_version "$cli" || { say "版の取得結果が不正: ${spotify} / ${cli}"; exit 1; }
say "現在: Spotify ${current_spotify} / spicetify-cli ${current_cli} (${current_rev:0:10})"
say "候補: Spotify ${spotify} / spicetify-cli ${cli} (${candidate_rev:0:10})"

if [ "$spotify" = "$current_spotify" ] && [ "$cli" = "$current_cli" ]; then
  say "版が変わっていないので、何もしない"
  stop
fi

# --- 2. 猶予期間 ---
last_change=$(gh api "repos/NixOS/nixpkgs/commits?path=pkgs/by-name/sp/spotify/darwin.nix&sha=${candidate_rev}&per_page=1" \
  --jq '.[0].commit.committer.date | fromdateiso8601')
age_days=$(( ($(date +%s) - last_change) / 86400 ))
if [ "$spotify" != "$current_spotify" ] && [ "$age_days" -lt "$SOAK_DAYS" ]; then
  say "darwin.nix の最終変更から ${age_days} 日 (猶予 ${SOAK_DAYS} 日)。今回は見送る"
  stop
fi

# --- 3. spicetify-cli のメジャーバージョン ---
if [ "${cli%%.*}" != "${current_cli%%.*}" ]; then
  say "spicetify-cli のメジャー更新 (${current_cli} から ${cli})。Issue にして終了する"
  open_issue "major:${cli}" "spicetify-cli ${cli} へのメジャー更新が nixpkgs に入りました" \
"nixpkgs-unstable で spicetify-cli が ${current_cli} から ${cli} に上がったため、自動更新の PR を見送りました。

| 項目 | 値 |
|---|---|
| 現在の固定 | Spotify ${current_spotify} / spicetify-cli ${current_cli} |
| 候補 | Spotify ${spotify} / spicetify-cli ${cli} |
| 評価した nixpkgs のコミット | https://github.com/NixOS/nixpkgs/commit/${candidate_rev} |
| spicetify-cli のリリースノート | https://github.com/spicetify/cli/releases/tag/v${cli} |

メジャー更新は、設定の書式や spicetify-nix との適合が変わりうるため、手動での確認が必要です。
対応する場合は flake.nix の nixpkgs-spotify の rev を手動で更新してください。"
  stop
fi

# --- 4. 互換性 (spicetify-cli のリリースノートの macOS の範囲) ---
notes=$(gh release view "v${cli}" --repo spicetify/cli --json body -q .body)
line=$(printf '%s\n' "$notes" | grep -E 'Spotify for \*\*macOS\*\*' | head -1 || true)
low=$(printf '%s' "$line" | sed -nE 's/.*`([0-9.]+)`[^`]*`([0-9.]+)`.*/\1/p')
high=$(printf '%s' "$line" | sed -nE 's/.*`([0-9.]+)`[^`]*`([0-9.]+)`.*/\2/p')

if ! { valid_version "$low" && valid_version "$high"; }; then
  say "対応範囲を解析できない (spicetify-cli v${cli})。Issue にして終了する"
  open_issue "parse:${cli}" "spicetify-cli ${cli} の対応範囲を解析できませんでした" \
"spicetify-cli v${cli} のリリースノートから、macOS の対応範囲を取得できませんでした。
書式が変わった可能性があります。自動更新は、この状態では PR を作りません。

- リリースノート: https://github.com/spicetify/cli/releases/tag/v${cli}
- 解析している行: 「Spotify for **macOS**」を含む行の、バッククォートで囲まれた 2 つの版数 (下限と上限)
- 修正箇所: scripts/spotify-update-check.sh の「4. 互換性」"
  stop
fi

if [ "$(cmp3 "$low" "$spotify")" = 1 ] || [ "$(cmp3 "$spotify" "$high")" = 1 ]; then
  say "Spotify ${spotify} は、spicetify-cli ${cli} の対応範囲 (${low} から ${high}) の外。Issue にして終了する"
  open_issue "compat:${cli}" "Spotify ${spotify} は spicetify-cli ${cli} の対応範囲外です" \
"nixpkgs-unstable の候補を評価した結果、自動更新の PR を見送りました。

| 項目 | 値 |
|---|---|
| 候補の Spotify | ${spotify} |
| 候補の spicetify-cli | ${cli} |
| spicetify-cli の macOS 対応範囲 | ${low} から ${high} |
| 現在の固定 | Spotify ${current_spotify} / spicetify-cli ${current_cli} |
| 評価した nixpkgs のコミット | https://github.com/NixOS/nixpkgs/commit/${candidate_rev} |
| spicetify-cli のリリースノート | https://github.com/spicetify/cli/releases/tag/v${cli} |

対応: spicetify-cli が、この Spotify の版に対応する版へ更新されるまで待機します。
nixpkgs に新しい版が入ると、次回の定期実行で再評価されます。
今すぐ再評価するには、Actions の update-spotify を手動実行してください。"
  stop
fi

say "すべてのゲートを通過 (Spotify ${spotify} は ${low} から ${high} の範囲内)"
output go true
output candidate_rev "$candidate_rev"
output spotify "$spotify"
output cli "$cli"
output current_spotify "$current_spotify"
output current_cli "$current_cli"
output compat_low "$low"
output compat_high "$high"
