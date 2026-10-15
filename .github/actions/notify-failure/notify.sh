#!/usr/bin/env bash
# ワークフローの失敗を Issue にする。action.yaml から呼ばれる。ローカルでは DRY_RUN=1 で動作を確認できる。
#
# 必須の環境変数: KEY, WORKFLOW, JOB, EVENT, GITHUB_REPOSITORY, GITHUB_RUN_ID
# 任意: DETAIL, TOPIC, DRY_RUN, GITHUB_SERVER_URL
#
# - 同じキーの open な Issue があれば、コメントを追記する (同じ失敗が続く間、Issue は増えない)
# - 無ければ新規作成する。クローズ済みは数えないので、直したあとの再発は新しい Issue になる
set -euo pipefail

LABEL="workflow-failure"
DRY_RUN="${DRY_RUN:-0}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
RUN_URL="${SERVER}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

# 失敗した step の名前 (ワークフローに書いた固定の文字列)。取得できなくても通知は止めない。
failed_steps=$(gh run view "$GITHUB_RUN_ID" --repo "$GITHUB_REPOSITORY" --json jobs \
  --jq '[.jobs[].steps[] | select(.conclusion == "failure") | .name] | join(", ")' 2>/dev/null || true)
[ -n "$failed_steps" ] || failed_steps="(取得できませんでした)"

existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --label "$LABEL" --state open --limit 100 --json number,body \
  -q "[.[] | select(.body | contains(\"<!-- key:${KEY} -->\"))] | .[0].number // empty")

if [ -n "$existing" ]; then
  comment="同じ失敗が再発しました。

- 実行: ${RUN_URL}
- 失敗した step: ${failed_steps}"
  if [ "$DRY_RUN" = 1 ]; then
    echo "[DRY_RUN] Issue #${existing} にコメントを追記する:"; echo "$comment"; exit 0
  fi
  gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$comment"
  exit 0
fi

title="ワークフローの失敗: ${WORKFLOW}"
[ -z "${TOPIC:-}" ] || title="${title} (${TOPIC})"
body="<!-- key:${KEY} -->
ワークフロー **${WORKFLOW}** (ジョブ: ${JOB}、トリガー: ${EVENT}) が失敗しました。

| 項目 | 値 |
|---|---|
| 実行 | ${RUN_URL} |
| 失敗した step | ${failed_steps} |
"
if [ -n "${DETAIL:-}" ]; then
  body="${body}
${DETAIL}
"
fi
body="${body}
この Issue は、同じ失敗が続く間、コメントで追記されます。原因を直したら、クローズしてください。
クローズ後に再発した場合は、新しい Issue が作られます。"

if [ "$DRY_RUN" = 1 ]; then
  echo "[DRY_RUN] Issue を作成する: ${title}"; echo "$body"; exit 0
fi
gh label create "$LABEL" --repo "$GITHUB_REPOSITORY" --force --color d93f0b \
  --description "ワークフローの失敗の通知" >/dev/null
gh issue create --repo "$GITHUB_REPOSITORY" --label "$LABEL" --title "$title" --body "$body"
