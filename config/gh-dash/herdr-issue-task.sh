# gh-dash から呼ぶ。Issue を、herdr の今の space の新しいタブの Claude Code に渡す。
# 使い方: herdr-issue-task <owner/repo> <number>
if [ "$#" -ne 2 ]; then
  echo "usage: herdr-issue-task <owner/repo> <number>" >&2
  exit 2
fi

repo=$1
number=$2

issue=$(gh issue view "$number" -R "$repo" --json title,body,url)
task=$(jq -r '"Issue \(.url) をやってください。\n\n# \(.title)\n\n\(.body)"' <<<"$issue")

herdr-app "do" tab.new "$(jq -n --arg t "$task" '{argv: ["claude"], task: $t}')"
