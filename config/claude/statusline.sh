#!/bin/bash

# Catppuccin Macchiato
RED='\033[38;2;237;135;150m'
PEACH='\033[38;2;245;169;127m'
OVERLAY0='\033[38;2;110;115;141m'
RESET='\033[0m'
MAUVE='\033[38;2;198;160;246m'
SKY='\033[38;2;145;215;227m'
GREEN='\033[38;2;166;218;149m'
BLUE='\033[38;2;138;173;244m'

# Catppuccin Macchiato Bold
GREEN_BOLD='\033[1;38;2;166;218;149m'
BLUE_BOLD='\033[1;38;2;138;173;244m'

# 使用率に応じた色を返す関数（コンテキスト用）
get_color() {
  local pct=$1
  local base=${2:-$SKY}
  if [ "$pct" -ge 80 ]; then
    echo "$RED"
  elif [ "$pct" -ge 50 ]; then
    echo "$PEACH"
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

# セグメントカラー付きデュアルプログレスバー生成関数
# used_pct: 左から塗る（使用率）、time_pct: 右から塗る（回復待ち割合）
# elapsed_pct: 経過時間割合（-1 = 不明、超過色なし）、base: 通常色
make_segmented_bar() {
  local used_pct=$1 time_pct=$2 elapsed_pct=$3 base=$4 width=${5:-10}
  local used_filled=$((used_pct * width / 100))
  local time_filled=$((time_pct * width / 100))
  local elapsed_filled=0
  [ "$elapsed_pct" -ge 0 ] && elapsed_filled=$((elapsed_pct * width / 100))
  local over=0
  [ "$elapsed_pct" -ge 0 ] && over=$((used_pct - elapsed_pct))
  # 精度不足で超過セルが出ない場合、次のセル1つをYELLOWで示す
  local show_next_marker=0
  if [ "$elapsed_pct" -ge 0 ] && [ "$used_filled" -eq "$elapsed_filled" ] && [ "$over" -gt 0 ] && [ "$used_filled" -lt "$width" ]; then
    show_next_marker=1
  fi
  local bar=""
  for ((i = 0; i < width; i++)); do
    local right_idx=$((width - 1 - i))
    local is_used=0 is_time=0
    [ $i -lt $used_filled ] && is_used=1
    [ $right_idx -lt $time_filled ] && is_time=1
    local cell_color="$base"
    if [ $is_used -eq 1 ] && [ "$elapsed_pct" -ge 0 ] && [ $i -ge $elapsed_filled ]; then
      [ "$over" -ge 10 ] && cell_color="$RED" || cell_color="$PEACH"
    elif [ $show_next_marker -eq 1 ] && [ $i -eq $used_filled ]; then
      cell_color="$PEACH"
    fi
    if [ "$cell_color" != "$base" ]; then
      bar+="${cell_color}█${RESET}"
    elif [ $is_used -eq 1 ] && [ $is_time -eq 1 ]; then
      bar+="${base}▓${RESET}"
    elif [ $is_used -eq 1 ]; then
      bar+="${base}█${RESET}"
    elif [ $is_time -eq 1 ]; then
      bar+="${base}▒${RESET}"
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

# レート制限行を組み立てる関数
# 引数: label used_int reset_epoch total_secs base
build_rate_str() {
  local label=$1 used_int=$2 reset_epoch=$3 total_secs=$4 base=$5
  local time_pct=0 elapsed_pct=-1 time_str=""
  if [ -n "$reset_epoch" ]; then
    local now diff
    now=$(date +%s)
    diff=$((reset_epoch - now))
    if [ "$diff" -gt 0 ]; then
      time_pct=$((diff * 100 / total_secs))
      elapsed_pct=$((100 - time_pct))
      time_str="  ${OVERLAY0}▸$(printf " %6s" "$(format_countdown $diff)")${RESET}"
    else
      elapsed_pct=100
    fi
  fi
  local num_color
  [ "$used_int" -ge 90 ] && num_color="$RED" || num_color="$base"
  local bar
  bar=$(make_segmented_bar "$used_int" "$time_pct" "$elapsed_pct" "$base")
  echo "${label} ${bar}${num_color}$(printf "%3d%%" "$used_int")${RESET}${time_str}"
}

# 入力JSON読み取り
input=$(cat)

# モデル名取得
model=$(echo "$input" | jq -r '.model.display_name')

# CWD取得
cwd=$(echo "$input" | jq -r '.cwd // empty')

# ディレクトリと git 状態（starship のモジュールをそのまま使い、プロンプトと表示を揃える）
# directory モジュールは $PWD を基準にするので cd してから呼ぶ。
# STARSHIP_SHELL を空にして、zsh 用のエスケープ (%{ %}) が混ざらないようにする。
starship_str=""
if [ -n "$cwd" ] && cd "$cwd" 2>/dev/null; then
  for module in directory git_branch git_status; do
    starship_str+=$(STARSHIP_SHELL='' starship module "$module" 2>/dev/null)
  done
fi

# コンテキスト使用率計算 - ベースカラー: 緑
ctx_str=""
usage=$(echo "$input" | jq '.context_window.current_usage')
if [ "$usage" != "null" ]; then
  current=$(echo "$input" | jq '.context_window.current_usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
  size=$(echo "$input" | jq '.context_window.context_window_size')
  ctx_pct=$(((current * 100 + size / 2) / size))
  ctx_color=$(get_color $ctx_pct "$GREEN")
  ctx_bar=$(make_progress_bar $ctx_pct 10)
  compact_threshold=$((size * 85 / 100))
  remaining=$((compact_threshold - current))
  [ "$remaining" -lt 0 ] && remaining=0
  k_int=$((remaining / 1000))
  k_dec=$(((remaining % 1000) / 100))
  ctx_str="Cx ${ctx_color}${ctx_bar}${RESET}${ctx_color}$(printf "%3d%%" $ctx_pct)${RESET}  ${OVERLAY0}▸$(printf " %6s" "${k_int}.${k_dec}K")${RESET}"
fi

# レート制限（v2.1.80+ rate_limits フィールドから直接取得）
five_hour_str=""
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_hour_pct" ]; then
  five_hour_int=$(printf "%.0f" "$five_hour_pct")
  reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  five_hour_str=$(build_rate_str "5h" "$five_hour_int" "$reset_epoch" 18000 "$SKY")
fi

seven_day_str=""
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$seven_day_pct" ]; then
  seven_day_int=$(printf "%.0f" "$seven_day_pct")
  reset_epoch_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  seven_day_str=$(build_rate_str "7d" "$seven_day_int" "$reset_epoch_7d" 604800 "$MAUVE")
fi

# 出力（starship のディレクトリと git 状態、モデル名、時刻）
line1="${starship_str}${GREEN_BOLD}󱌼 ${model}${RESET} ${BLUE_BOLD}󰥔 $(date +%H:%M)${RESET}"

echo -e "$line1"
[ -n "$ctx_str" ] && echo -e "$ctx_str"
[ -n "$five_hour_str" ] && echo -e "$five_hour_str"
[ -n "$seven_day_str" ] && echo -e "$seven_day_str"
exit 0
