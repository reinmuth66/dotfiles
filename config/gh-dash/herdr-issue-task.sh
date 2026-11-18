# gh-dash から呼ぶ。Issue を、herdr の今の space の新しいタブの Claude Code に渡す。
# 使い方: herdr-issue-task <owner/repo> <number>
# herdr-app には通知を出すコマンドがないので、失敗は標準エラーに書き、読めるように 3 秒待つ
fail() {
  echo "herdr-issue-task: $1" >&2
  sleep 3
  exit 1
}

if [ "$#" -ne 2 ]; then
  fail "usage: herdr-issue-task <owner/repo> <number>"
fi

repo=$1
number=$2

issue=$(gh issue view "$number" -R "$repo" --json title,body,url) || fail "Issue を読めません: $repo#$number"
task=$(jq -r '"Issue \(.url) をやってください。\n\n# \(.title)\n\n\(.body)"' <<<"$issue") || fail "Issue の形が読めません: $repo#$number"

herdr-app "do" tab.new "$(jq -n --arg t "$task" '{argv: ["claude"], task: $t}')" || fail "herdr のタブを作れません"
