#!/bin/bash

# ANSIカラーコード
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
CYAN='\033[36m'
GRAY='\033[90m'
RESET='\033[0m'

# Catppuccin Mocha
C_MAUVE='\033[38;2;203;166;247m'
C_SKY='\033[38;2;137;220;235m'
C_GREEN='\033[38;2;166;227;161m'
C_BLUE='\033[38;2;137;180;250m'

# Catppuccin Mocha 太字
C_MAUVE_BOLD='\033[1;38;2;203;166;247m' # directory
C_SKY_BOLD='\033[1;38;2;137;220;235m'   # git branch / status
C_GREEN_BOLD='\033[1;38;2;166;227;161m' # モデル名
C_BLUE_BOLD='\033[1;38;2;137;180;250m'  # 時刻

# 使用率に応じた色を返す関数
get_color() {
  local pct=$1
  local base=${2:-$CYAN}
  if [ "$pct" -ge 80 ]; then
    echo "$RED"
  elif [ "$pct" -ge 50 ]; then
    echo "$YELLOW"
  else
    echo "$base"
  fi
}

# プログレスバー生成関数
make_progress_bar() {
  local pct=$1
  local width=${2:-10}
  local filled=$((pct * width / 100))
  local bar=""
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = filled; i < width; i++)); do bar+="░"; done
  echo "$bar"
}

# デュアルプログレスバー生成関数
# used_pct: 左から塗る（使用率）、time_pct: 右から塗る（回復待ち割合）
make_dual_progress_bar() {
  local used_pct=$1
  local time_pct=$2
  local width=${3:-10}
  local used_filled=$((used_pct * width / 100))
  local time_filled=$((time_pct * width / 100))
  local bar=""
  for ((i = 0; i < width; i++)); do
    local right_idx=$((width - 1 - i))
    local is_used=0
    local is_time=0
    [ $i -lt $used_filled ] && is_used=1
    [ $right_idx -lt $time_filled ] && is_time=1
    if [ $is_used -eq 1 ] && [ $is_time -eq 1 ]; then
      bar+="▓"
    elif [ $is_used -eq 1 ]; then
      bar+="█"
    elif [ $is_time -eq 1 ]; then
      bar+="▒"
    else
      bar+="░"
    fi
  done
  echo "$bar"
}

# カウントダウン表示フォーマット
format_countdown() {
  local secs=$1
  local d=$((secs / 86400))
  local h=$(((secs % 86400) / 3600))
  local m=$(((secs % 3600) / 60))
  if [ $d -gt 0 ]; then
    printf "%dd%02dh" $d $h
  elif [ $h -gt 0 ]; then
    printf "%dh%02dm" $h $m
  else
    printf "%dm" $m
  fi
}

# 入力JSON読み取り
input=$(cat)

# モデル名取得
model=$(echo "$input" | jq -r '.model.display_name')

# CWD取得
cwd=$(echo "$input" | jq -r '.cwd // empty')

# ディレクトリ表示（starship の truncate_to_repo + truncation_length=3 に合わせて実装）
dir_str=""
if [ -n "$cwd" ]; then
  if [[ "$cwd" == "$HOME"* ]]; then
    display_path="~${cwd#$HOME}"
  else
    display_path="$cwd"
  fi

  git_root=""
  if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  fi

  if [ -n "$git_root" ]; then
    # git リポジトリ内: リポジトリ名を基点にして上位パスを …/ で切り詰め
    repo_name=$(basename "$git_root")
    if [ "$cwd" = "$git_root" ]; then
      repo_relative="$repo_name"
    else
      repo_relative="$repo_name/${cwd#$git_root/}"
    fi
    rel_slashes=$(echo "$repo_relative" | tr -cd '/' | wc -c)
    if [ $((rel_slashes + 1)) -le 3 ]; then
      short_cwd="…/$repo_relative"
    else
      IFS='/' read -ra parts <<<"$repo_relative"
      len=${#parts[@]}
      start=$((len - 3))
      short_cwd="…/${parts[$start]}/${parts[$((start + 1))]}/${parts[$((start + 2))]}"
    fi
  else
    # git リポジトリ外: ~ を1コンポーネントとして数えて depth > 3 で切り詰め
    if [[ "$display_path" == "~/"* ]]; then
      inner="${display_path#\~/}"
      slashes=$(echo "$inner" | tr -cd '/' | wc -c)
      depth=$((slashes + 2))
    elif [[ "$display_path" == "~" ]]; then
      depth=1
      inner=""
    else
      inner="${display_path#/}"
      slashes=$(echo "$inner" | tr -cd '/' | wc -c)
      depth=$((slashes + 1))
    fi
    if [ "$depth" -le 3 ]; then
      short_cwd="$display_path"
    else
      IFS='/' read -ra parts <<<"$inner"
      len=${#parts[@]}
      start=$((len - 3))
      short_cwd="…/${parts[$start]}/${parts[$((start + 1))]}/${parts[$((start + 2))]}"
    fi
  fi

  dir_str="${C_MAUVE_BOLD}${short_cwd}${RESET}"
fi

# Git状態取得
git_str=""
if [ -n "$cwd" ]; then
  if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      git_str="${C_SKY_BOLD} ${branch}${RESET}"
      staged=0
      modified=0
      deleted=0
      untracked=0
      while IFS= read -r line; do
        x="${line:0:1}"
        y="${line:1:1}"
        if [ "$x" = "?" ] && [ "$y" = "?" ]; then
          untracked=$((untracked + 1))
          continue
        fi
        [ "$x" != " " ] && staged=$((staged + 1))
        if [ "$y" = "M" ] || [ "$y" = "T" ]; then modified=$((modified + 1)); fi
        [ "$y" = "D" ] && deleted=$((deleted + 1))
      done < <(git -C "$cwd" status --porcelain 2>/dev/null)
      [ "$modified" -gt 0 ] && git_str="$git_str ${C_SKY_BOLD}󰏫 ${modified}${RESET}"
      [ "$staged" -gt 0 ] && git_str="$git_str ${C_SKY_BOLD}󱇬 ${staged}${RESET}"
      [ "$deleted" -gt 0 ] && git_str="$git_str ${C_SKY_BOLD}󱘹 ${deleted}${RESET}"
      [ "$untracked" -gt 0 ] && git_str="$git_str ${C_SKY_BOLD}󰈉 ${untracked}${RESET}"
    fi
  fi
fi

# コンテキスト使用率計算 - ベースカラー: 緑
ctx_str=""
usage=$(echo "$input" | jq '.context_window.current_usage')
if [ "$usage" != "null" ]; then
  current=$(echo "$input" | jq '.context_window.current_usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
  size=$(echo "$input" | jq '.context_window.context_window_size')
  ctx_pct=$(((current * 100 + size / 2) / size))
  ctx_color=$(get_color $ctx_pct "$C_GREEN")
  ctx_bar=$(make_progress_bar $ctx_pct 10)
  compact_threshold=$((size * 85 / 100))
  remaining=$((compact_threshold - current))
  [ "$remaining" -lt 0 ] && remaining=0
  k_int=$((remaining / 1000))
  k_dec=$(((remaining % 1000) / 100))
  ctx_str="Cx ${ctx_color}${ctx_bar}${RESET}${ctx_color}$(printf "%3d%%" $ctx_pct)${RESET}  ${GRAY}▸$(printf " %6s" "${k_int}.${k_dec}K")${RESET}"
fi

# レート制限（v2.1.80+ rate_limits フィールドから直接取得）
five_hour_str=""
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_hour_pct" ]; then
  five_hour_int=$(printf "%.0f" "$five_hour_pct")
  hour_color=$(get_color $five_hour_int "$C_SKY")
  time_pct=0
  time_str=""
  reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  if [ -n "$reset_epoch" ]; then
    now=$(date +%s)
    diff=$((reset_epoch - now))
    if [ "$diff" -gt 0 ]; then
      time_pct=$((diff * 100 / 18000))
      time_str="  ${GRAY}▸$(printf " %6s" "$(format_countdown $diff)")${RESET}"
    fi
  fi
  hour_bar=$(make_dual_progress_bar $five_hour_int $time_pct 10)
  five_hour_str="5h ${hour_color}${hour_bar}${RESET}${hour_color}$(printf "%3d%%" $five_hour_int)${RESET}${time_str}"
fi

seven_day_str=""
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$seven_day_pct" ]; then
  seven_day_int=$(printf "%.0f" "$seven_day_pct")
  week_color=$(get_color $seven_day_int "$C_MAUVE")
  time_pct_7d=0
  time_str_7d=""
  reset_epoch_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  if [ -n "$reset_epoch_7d" ]; then
    now=$(date +%s)
    diff_7d=$((reset_epoch_7d - now))
    if [ "$diff_7d" -gt 0 ]; then
      time_pct_7d=$((diff_7d * 100 / 604800))
      time_str_7d="  ${GRAY}▸$(printf " %6s" "$(format_countdown $diff_7d)")${RESET}"
    fi
  fi
  week_bar=$(make_dual_progress_bar $seven_day_int $time_pct_7d 10)
  seven_day_str="7d ${week_color}${week_bar}${RESET}${week_color}$(printf "%3d%%" $seven_day_int)${RESET}${time_str_7d}"
fi

# 出力（ディレクトリ git モデル名 時刻 — すべてスペース区切り、すべて太字）
line1=""
[ -n "$dir_str" ] && line1="$dir_str"
if [ -n "$git_str" ]; then
  [ -n "$line1" ] && line1="$line1 "
  line1="$line1$git_str"
fi
[ -n "$line1" ] && line1="$line1 "
line1="${line1}${C_GREEN_BOLD}󱌼 ${model}${RESET} ${C_BLUE_BOLD}󰥔 $(date +%H:%M)${RESET}"

echo -e "$line1"
[ -n "$ctx_str" ] && echo -e "$ctx_str"
[ -n "$five_hour_str" ] && echo -e "$five_hour_str"
[ -n "$seven_day_str" ] && echo -e "$seven_day_str"
exit 0
