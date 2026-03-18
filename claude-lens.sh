#!/usr/bin/env bash
# claude-lens - lightweight statusline for Claude Code
# https://github.com/<user>/claude-lens
#
# Called by Claude Code every ~300ms via stdin JSON.
# Must complete within ~35ms. All modules are inline functions.

# === Constants ===
readonly VERSION="0.2.1"
readonly CACHE_PREFIX="/tmp/claude-lens"

# ANSI colors
readonly C_CYAN='\033[36m'
readonly C_GREEN='\033[32m'
readonly C_YELLOW='\033[33m'
readonly C_RED='\033[31m'
readonly C_DIM='\033[2m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

# === Cache Helpers ===

_file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

file_age() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo 999999
    return 1
  fi
  local now mtime
  now="${_NOW:-$(date +%s)}"
  mtime=$(_file_mtime "$file")
  echo $((now - mtime))
}

cache_get() {
  local file="$1" ttl="$2"
  if [ -f "$file" ]; then
    local age
    age=$(file_age "$file")
    if [ "$age" -le "$ttl" ]; then
      cat "$file"
      return 0
    fi
  fi
  return 1
}

cache_set() {
  local file="$1" data="$2"
  local tmp
  tmp="${file}.tmp.$$"
  printf '%s' "$data" > "$tmp" && mv "$tmp" "$file"
}

# Cross-platform md5: macOS `md5 -q`, Linux `md5sum`
_hash_str() {
  printf '%s' "$1" | md5 -q 2>/dev/null || printf '%s' "$1" | md5sum 2>/dev/null | cut -d' ' -f1
}

# === Config ===

_config_defaults() {
  CFG_SHOW_COST="false"
  CFG_SHOW_SPEED="true"
  CFG_SHOW_TREND="true"
  CFG_SHOW_USAGE="true"
}

# Security: whitelist validation, no eval/source
load_config() {
  local config_file="$1"
  _config_defaults

  [ -f "$config_file" ] || return 0

  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # 值白名单：只允许字母数字和 _./ - （无括号、反引号、$）
      if [[ "$value" =~ ^[a-zA-Z0-9_./\ -]*$ ]]; then
        # 设置 CFG_<KEY> 变量，用 printf -v 避免 eval
        printf -v "CFG_${key}" '%s' "$value"
      fi
    fi
  done < "$config_file"
}

# === JSON Parse ===

_assign_parsed_fields() {
  IFS=$'\x1f' read -r \
    G_MODEL_ID G_MODEL_NAME G_CONTEXT_PCT G_CTX_SIZE \
    G_COST_USD G_DURATION_MS G_TRANSCRIPT_PATH \
    G_WORKTREE_NAME G_WORKTREE_BRANCH \
    G_WORKSPACE_DIR G_PROJECT_DIR \
    G_LINES_ADDED G_LINES_REMOVED \
    G_INPUT_TOKENS G_OUTPUT_TOKENS G_CACHE_READ_TOKENS \
    <<< "$1"
}

parse_stdin() {
  local raw
  raw=$(cat)

  local parsed
  if parsed=$(printf '%s' "$raw" | jq -r '
    [
      (.model.id // ""),
      (.model.display_name // "unknown"),
      (.context_window.used_percentage // ""),
      (.context_window.context_window_size // 0 | tostring),
      (.cost.total_cost_usd // ""),
      (.cost.total_duration_ms // 0 | floor | tostring),
      (.transcript_path // ""),
      (.worktree.name // ""),
      (.worktree.branch // ""),
      (.workspace.current_dir // "."),
      (.workspace.project_dir // "."),
      (.cost.total_lines_added // "" | tostring),
      (.cost.total_lines_removed // "" | tostring),
      (.context_window.current_usage.input_tokens // 0 | tostring),
      (.context_window.current_usage.output_tokens // 0 | tostring),
      (.context_window.current_usage.cache_read_input_tokens // 0 | tostring)
    ] | join("\u001f")
  ' 2>/dev/null); then
    _assign_parsed_fields "$parsed"
    # 缓存本次解析结果，供 jq 不可用时回退
    cache_set "${CACHE_PREFIX}-last-parse" "$parsed"
    return 0
  fi

  # jq 失败，尝试读取缓存的解析结果（最长保留 1 天）
  local cached
  if cached=$(cache_get "${CACHE_PREFIX}-last-parse" 86400 2>/dev/null); then
    _assign_parsed_fields "$cached"
    return 0
  fi

  # 无缓存，设置空默认值
  G_MODEL_ID="" G_MODEL_NAME="unknown" G_CONTEXT_PCT=""
  G_CTX_SIZE="0" G_COST_USD="" G_DURATION_MS="0"
  G_TRANSCRIPT_PATH="" G_WORKTREE_NAME="" G_WORKTREE_BRANCH=""
  G_WORKSPACE_DIR="." G_PROJECT_DIR="."
  G_LINES_ADDED="" G_LINES_REMOVED=""
  G_INPUT_TOKENS="0" G_OUTPUT_TOKENS="0" G_CACHE_READ_TOKENS="0"
  return 1
}

# === Modules ===
# 每个模块输出 ANSI 着色文本，读取 G_* 全局变量，绝不自行调用 jq。
# 失败时输出空字符串，绝不 exit 非零。

module_model() {
  local name="${G_MODEL_NAME:-unknown}"
  printf '%b[%s]%b' "$C_CYAN" "$name" "$C_RESET"
}

module_duration() {
  local ms="${G_DURATION_MS:-0}"
  local total_sec=$((ms / 1000))
  local hours=$((total_sec / 3600))
  local mins=$(( (total_sec % 3600) / 60 ))
  local secs=$((total_sec % 60))

  if [ "$hours" -gt 0 ]; then
    printf '%b%dh %dm%b' "$C_DIM" "$hours" "$mins" "$C_RESET"
  else
    printf '%b%dm %ds%b' "$C_DIM" "$mins" "$secs" "$C_RESET"
  fi
}

module_cost() {
  local cost="${G_COST_USD:-}"
  [ -z "$cost" ] && return 0

  printf '%b$%s%b' "$C_DIM" "$(printf '%.2f' "$cost")" "$C_RESET"
}

module_context() {
  local pct="${G_CONTEXT_PCT:-}"
  local ctx_size="${G_CTX_SIZE:-0}"

  local ctx_label
  if [ "$ctx_size" -ge 1000000 ] 2>/dev/null; then
    ctx_label="$((ctx_size / 1000000))M"
  elif [ "$ctx_size" -ge 1000 ] 2>/dev/null; then
    ctx_label="$((ctx_size / 1000))K"
  else
    ctx_label="$ctx_size"
  fi

  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    printf '%s ... of %s' "░░░░░░░░░░" "$ctx_label"
    return 0
  fi

  pct=$(printf '%.0f' "$pct" 2>/dev/null || echo 0)

  local bar_color
  if [ "$pct" -ge 70 ]; then
    bar_color="$C_RED"
  elif [ "$pct" -ge 40 ]; then
    bar_color="$C_YELLOW"
  else
    bar_color="$C_GREEN"
  fi

  local bar_width=10
  local filled=$((pct * bar_width / 100))
  [ "$filled" -gt "$bar_width" ] && filled="$bar_width"
  local empty=$((bar_width - filled))

  local bar=""
  [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '█')
  [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '░')"

  printf '%b%s%b %d%% of %s' "$bar_color" "$bar" "$C_RESET" "$pct" "$ctx_label"

  # 85%+ 时显示 input/output token 明细
  if [ "$pct" -ge 85 ] 2>/dev/null; then
    local in_k out_k
    in_k=$(( (${G_INPUT_TOKENS:-0} + ${G_CACHE_READ_TOKENS:-0}) / 1000 ))
    out_k=$(( ${G_OUTPUT_TOKENS:-0} / 1000 ))
    printf ' %b(in:%dk out:%dk)%b' "$C_DIM" "$in_k" "$out_k" "$C_RESET"
  fi
}

# 使用环形缓冲区（最多 10 条）追踪 context 使用趋势
module_trend() {
  local pct="${G_CONTEXT_PCT:-}"
  [ -z "$pct" ] || [ "$pct" = "null" ] && return 0

  pct=$(printf '%.0f' "$pct" 2>/dev/null || echo 0)
  local trend_file="${TREND_FILE:-${CACHE_PREFIX}-trend}"
  local now="${_NOW:-$(date +%s)}"

  # Read existing entries into array (no mapfile - bash 3.2 compat)
  local -a entries=()
  if [ -f "$trend_file" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
      entries+=("$_line")
    done < "$trend_file"
  fi

  local last_idx=$(( ${#entries[@]} - 1 ))
  local last_pct=""
  [ "$last_idx" -ge 0 ] && last_pct="${entries[$last_idx]#*:}"

  if [ "$pct" != "$last_pct" ]; then
    entries+=("${now}:${pct}")
    # 环形缓冲区：截断到最后 10 条
    if [ "${#entries[@]}" -gt 10 ]; then
      entries=("${entries[@]: -10}")
    fi
    printf '%s\n' "${entries[@]}" > "$trend_file"
  fi

  local n=${#entries[@]}
  [ "$n" -lt 2 ] && return 0

  local oldest_pct="${entries[0]#*:}"
  local newest_pct="${entries[$((n - 1))]#*:}"

  local diff=$((newest_pct - oldest_pct))
  local arrow
  if [ "$diff" -gt 2 ]; then
    arrow="↑"
  elif [ "$diff" -lt -2 ]; then
    arrow="↓"
  else
    arrow="→"
  fi

  local remaining=""
  if [ "$diff" -gt 0 ] && [ "${#entries[@]}" -ge 3 ]; then
    local remaining_pct=$((100 - newest_pct))
    local avg_per_step=$((diff / (${#entries[@]} - 1)))
    if [ "$avg_per_step" -gt 0 ]; then
      local est_steps=$((remaining_pct / avg_per_step))
      [ "$est_steps" -gt 0 ] && remaining=" ~${est_steps}r"
    fi
  fi

  printf '%s%s' "$arrow" "$remaining"
}

# === Git Module ===

module_git() {
  local dir="${G_PROJECT_DIR:-.}"
  local max_branch_len=35

  local dir_hash
  dir_hash=$(_hash_str "$dir")
  local cache_dir="${GIT_CACHE_DIR:-/tmp}"
  local cache_file="${cache_dir}/claude-lens-git-${dir_hash}"

  local cached
  if ! cached=$(cache_get "$cache_file" 5); then
    if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
      local branch diff_stats files added deleted
      branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null || echo "")
      diff_stats=$(git -C "$dir" --no-optional-locks diff HEAD --numstat 2>/dev/null || true)
      files=$(echo "$diff_stats" | awk 'NF{c++} END{print c+0}')
      added=$(echo "$diff_stats" | awk '{s+=$1} END{print s+0}')
      deleted=$(echo "$diff_stats" | awk '{s+=$2} END{print s+0}')
      local ahead=0 behind=0
      if git -C "$dir" --no-optional-locks rev-parse --verify '@{upstream}' > /dev/null 2>&1; then
        ahead=$(git -C "$dir" --no-optional-locks rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
        behind=$(git -C "$dir" --no-optional-locks rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
      fi
      cached="${branch}|${files}|${added}|${deleted}|${ahead}|${behind}"
      cache_set "$cache_file" "$cached"
    else
      return 0
    fi
  fi

  local branch files added deleted ahead behind
  IFS='|' read -r branch files added deleted ahead behind <<< "$cached"
  [ -z "$branch" ] && return 0

  if [ "${#branch}" -gt "$max_branch_len" ]; then
    branch="${branch:0:$max_branch_len}…"
  fi

  local git_arrows=""
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && git_arrows="${git_arrows}↑${ahead}"
  [ "${behind:-0}" -gt 0 ] 2>/dev/null && git_arrows="${git_arrows}↓${behind}"

  local git_status=""
  if [ "${files:-0}" -gt 0 ] 2>/dev/null; then
    git_status=$(printf ' %sf %b+%s%b %b-%s%b' "$files" "$C_GREEN" "$added" "$C_RESET" "$C_RED" "$deleted" "$C_RESET")
  fi

  printf '%s%s%s' "$branch" "${git_arrows:+ $git_arrows}" "$git_status"
}

# === Usage Module ===

_color_for_pct() {
  local val="$1"
  if [[ "$val" =~ ^[0-9]+$ ]]; then
    if [ "$val" -ge 90 ]; then printf '%s' "$C_RED"
    elif [ "$val" -ge 70 ]; then printf '%s' "$C_YELLOW"
    else printf '%s' "$C_GREEN"
    fi
  else
    printf '%s' "$C_RESET"
  fi
}

_fmt_pct() {
  [[ "$1" =~ ^[0-9]+$ ]] && printf '%s%%' "$1" || printf '%s' "$1"
}

# 计算 pace delta: 剩余储备（正=余裕，负=透支）
# 参数: actual(%) reset_minutes duration(分钟)
# 输出: 空(on-track) 或带颜色的 " +N%" / " -N%"
_pace_delta() {
  local actual="$1" reset_min="$2" duration="$3"

  # 数据缺失或异常时直接隐藏，避免误导状态栏
  [[ "$actual" =~ ^[0-9]+$ ]] || return 0
  [[ "$reset_min" =~ ^[0-9]+$ ]] || return 0
  [[ "$duration" =~ ^[0-9]+$ ]] || return 0
  (( duration > 0 )) || return 0
  (( reset_min <= duration )) || return 0

  local elapsed expected delta
  elapsed=$(( duration - reset_min ))
  expected=$(( elapsed * 100 / duration ))
  delta=$(( expected - actual ))

  # ±10 以内视为 on-track，不额外显示
  if (( delta > 10 )); then
    printf ' %b+%d%%%b' "$C_GREEN" "$delta" "$C_RESET"
  elif (( delta < -10 )); then
    printf ' %b%d%%%b' "$C_RED" "$delta" "$C_RESET"
  fi
}

# 判断 usage 缓存是否仍是旧 schema（少于 4 字段）
_usage_cache_needs_refresh() {
  local cache_file="$1"
  [ -f "$cache_file" ] || return 1

  local cache_raw
  cache_raw=$(cat "$cache_file" 2>/dev/null || true)
  [[ "$cache_raw" == *'|'*'|'*'|'* ]] || return 0
  return 1
}

# 按缓存年龄折算剩余分钟数，避免相对值随时间漂移
_age_usage_reset_min() {
  local reset_min="$1" cache_age="$2"
  [[ "$reset_min" =~ ^[0-9]+$ ]] || return 0
  [[ "$cache_age" =~ ^[0-9]+$ ]] || return 0

  local aged_min=$(( reset_min - (cache_age / 60) ))
  [ "$aged_min" -lt 0 ] && aged_min=0
  printf '%s' "$aged_min"
}

# 刷新失败时保留旧 usage 缓存，但把相对分钟数推进到当前时刻
_preserve_usage_cache_on_failure() {
  local cache_file="$1"
  [ -f "$cache_file" ] || return 1

  local cache_age five_h="--" seven_d="--" reset_min_5h="" reset_min_7d=""
  cache_age=$(file_age "$cache_file" 2>/dev/null || echo 0)
  IFS='|' read -r five_h seven_d reset_min_5h reset_min_7d < "$cache_file" 2>/dev/null || true

  reset_min_5h=$(_age_usage_reset_min "$reset_min_5h" "$cache_age")
  reset_min_7d=$(_age_usage_reset_min "$reset_min_7d" "$cache_age")
  cache_set "$cache_file" "${five_h}|${seven_d}|${reset_min_5h}|${reset_min_7d}"
}

# ISO timestamp -> remaining minutes from now
# W2: 去掉小数秒后缀时也丢失了时区信息，需显式指定 UTC
_parse_reset_epoch() {
  local reset_at="$1" now_epoch="$2"
  [ -z "$reset_at" ] && return 0
  local reset_ts="${reset_at%%.*}"
  local reset_epoch
  reset_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$reset_ts" +%s 2>/dev/null || date -d "${reset_ts}Z" +%s 2>/dev/null || true)
  if [ -n "$reset_epoch" ]; then
    local mins=$(( (reset_epoch - now_epoch) / 60 ))
    [ "$mins" -lt 0 ] && mins=0
    printf '%s' "$mins"
  fi
}

# stale-while-revalidate: 后台异步拉取 usage API 数据并写缓存
_fetch_usage_bg() {
  local cache_file="$1" lock_file="$2"
  (
    local keep_lock=""
    trap '[ -n "$keep_lock" ] || rm -f "$lock_file"' EXIT

    local cred_json access_token
    cred_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    access_token=$(printf '%s' "$cred_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null || true)

    local result=""
    if [ -n "$access_token" ]; then
      local api_resp
      api_resp=$(curl -s --max-time 3 \
        -H "Authorization: Bearer ${access_token}" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Content-Type: application/json" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null || true)

      local five_h seven_d
      five_h=$(printf '%s' "$api_resp" | jq -r '.five_hour.utilization // empty' 2>/dev/null | cut -d. -f1)
      seven_d=$(printf '%s' "$api_resp" | jq -r '.seven_day.utilization // empty' 2>/dev/null | cut -d. -f1)
      local now_epoch
      now_epoch=$(date +%s)

      local reset_at reset_minutes=""
      reset_at=$(printf '%s' "$api_resp" | jq -r '.five_hour.expires_at // .five_hour.resets_at // empty' 2>/dev/null || true)
      reset_minutes=$(_parse_reset_epoch "$reset_at" "$now_epoch")

      local reset_at_7d reset_minutes_7d=""
      reset_at_7d=$(printf '%s' "$api_resp" | jq -r '.seven_day.resets_at // .seven_day.expires_at // empty' 2>/dev/null || true)
      reset_minutes_7d=$(_parse_reset_epoch "$reset_at_7d" "$now_epoch")

      [ -n "$five_h" ] && [ -n "$seven_d" ] && result="${five_h}|${seven_d}|${reset_minutes}|${reset_minutes_7d}"
    fi

    if [ -n "$result" ]; then
      cache_set "$cache_file" "$result"
    elif [ -f "$cache_file" ]; then
      _preserve_usage_cache_on_failure "$cache_file"
      keep_lock=1
    else
      cache_set "$cache_file" "--|--||"
      keep_lock=1
    fi
  ) &
}

module_usage() {
  local cache_file="${USAGE_CACHE_FILE:-${CACHE_PREFIX}-usage}"
  local lock_file="${USAGE_LOCK_FILE:-${CACHE_PREFIX}-usage.lock}"
  local force_refresh="false"

  _usage_cache_needs_refresh "$cache_file" && force_refresh="true"

  # 若缓存过期（TTL 300s），用锁文件保证只启动一次后台刷新
  if [ "$force_refresh" = "true" ] || ! cache_get "$cache_file" 300 > /dev/null 2>&1; then
    if (set -o noclobber; echo $$ > "$lock_file") 2>/dev/null; then
      _fetch_usage_bg "$cache_file" "$lock_file"
    elif [ -f "$lock_file" ] && [ "$(file_age "$lock_file")" -gt 10 ]; then
      # 锁超过 10s 未释放，认为持锁进程已死，强制清锁重试
      rm -f "$lock_file"
      if (set -o noclobber; echo $$ > "$lock_file") 2>/dev/null; then
        _fetch_usage_bg "$cache_file" "$lock_file"
      fi
    fi
  fi

  # 从缓存读取（可能是过期数据，stale-while-revalidate）
  local five_h="--" seven_d="--" reset_min_5h="" reset_min_7d=""
  local cache_age="0"
  if [ -f "$cache_file" ]; then
    cache_age=$(file_age "$cache_file" 2>/dev/null || echo 0)
    IFS='|' read -r five_h seven_d reset_min_5h reset_min_7d < "$cache_file" 2>/dev/null || true
  fi
  five_h="${five_h:---}"
  seven_d="${seven_d:---}"
  reset_min_5h=$(_age_usage_reset_min "$reset_min_5h" "$cache_age")
  reset_min_7d=$(_age_usage_reset_min "$reset_min_7d" "$cache_age")

  local reset_str_5h="" reset_str_7d=""
  if [ -n "$reset_min_5h" ] && [[ "$reset_min_5h" =~ ^[0-9]+$ ]]; then
    if [ "$reset_min_5h" -ge 60 ]; then
      reset_str_5h=" ($((reset_min_5h / 60))h $((reset_min_5h % 60))m)"
    else
      reset_str_5h=" (${reset_min_5h}m)"
    fi
  fi
  if [ -n "$reset_min_7d" ] && [[ "$reset_min_7d" =~ ^[0-9]+$ ]]; then
    local days_7d=$(( reset_min_7d / 1440 ))
    local hours_7d=$(( (reset_min_7d % 1440) / 60 ))
    if [ "$days_7d" -gt 0 ]; then
      reset_str_7d=" (${days_7d}d ${hours_7d}h)"
    elif [ "$hours_7d" -gt 0 ]; then
      reset_str_7d=" (${hours_7d}h)"
    else
      reset_str_7d=" (${reset_min_7d}m)"
    fi
  fi

  # pace delta: 正=余裕(绿) 负=透支(红)，旧缓存缺字段时自动隐藏
  local delta_5h delta_7d
  delta_5h=$(_pace_delta "$five_h" "$reset_min_5h" 300)
  delta_7d=$(_pace_delta "$seven_d" "$reset_min_7d" 10080)

  # 显示为剩余百分比（余额视角），颜色仍基于已用量（越高越危险）
  local five_h_left="--" seven_d_left="--"
  [[ "$five_h" =~ ^[0-9]+$ ]] && five_h_left=$((100 - five_h))
  [[ "$seven_d" =~ ^[0-9]+$ ]] && seven_d_left=$((100 - seven_d))

  local five_h_color seven_d_color
  five_h_color=$(_color_for_pct "$five_h")
  seven_d_color=$(_color_for_pct "$seven_d")

  printf '5h: %b%s%b%s%s │ 7d: %b%s%b%s%s' \
    "$five_h_color" "$(_fmt_pct "$five_h_left")" "$C_RESET" "$delta_5h" "$reset_str_5h" \
    "$seven_d_color" "$(_fmt_pct "$seven_d_left")" "$C_RESET" "$delta_7d" "$reset_str_7d"
}

# === Path Display ===

# 格式化目录路径供 statusline 显示：
# - Worktree 路径：显示为 project/worktree-name
# - 普通路径：~ 缩写 + 超长时截断
format_path() {
  local dir="$1"
  local max_len=45
  local max_wt_len=35

  # 不用 \~ 以免产生字面反斜杠
  local short="${dir/#$HOME/~}"

  if [[ "$short" =~ /([^/]+)/\.claude/worktrees/([^/]+) ]]; then
    local project="${BASH_REMATCH[1]}"
    local wt_name="${BASH_REMATCH[2]}"
    if [ "${#wt_name}" -gt "$max_wt_len" ]; then
      wt_name="${wt_name:0:$max_wt_len}…"
    fi
    printf '%s/%s' "$project" "$wt_name"
    return 0
  fi

  if [ "${#short}" -gt "$max_len" ]; then
    short="…${short: -$((max_len - 1))}"
  fi

  printf '%s' "$short"
}

# === Transcript ===

# 增量读取 transcript 文件：追踪字节偏移，避免全量重扫
transcript_read() {
  local file="${G_TRANSCRIPT_PATH:-}"
  [ -z "$file" ] || [ ! -f "$file" ] && return 1

  # 用 transcript 文件路径哈希作为 offset 文件 key，隔离多 session 并发写入
  local file_hash
  file_hash=$(_hash_str "$file")
  local offset_file="${TRANSCRIPT_OFFSET_FILE:-${CACHE_PREFIX}-transcript-offset-${file_hash}}"
  local last_offset=0

  [ -f "$offset_file" ] && last_offset=$(cat "$offset_file" 2>/dev/null || echo 0)

  local file_size
  file_size=$(( $(wc -c < "$file" 2>/dev/null || echo 0) ))

  # 文件被截断说明是新 session，重置偏移
  if [ "$last_offset" -gt "$file_size" ]; then
    last_offset=0
  fi

  if [ "$last_offset" -ge "$file_size" ]; then
    return 0
  fi

  local new_data
  new_data=$(tail -c +$((last_offset + 1)) "$file" 2>/dev/null || true)

  printf '%s' "$file_size" > "$offset_file"
  printf '%s' "$new_data"
}

# 解析 transcript 增量数据，更新 _TS_* 全局状态变量
_update_transcript_state() {
  local cache_dir="${TRANSCRIPT_CACHE_DIR:-/tmp}"
  # 用 transcript 路径哈希隔离不同 session 的状态缓存，避免多 session 交叉污染
  local transcript_hash
  transcript_hash=$(_hash_str "${G_TRANSCRIPT_PATH:-unknown}")
  local state_cache="${cache_dir}/claude-lens-transcript-state-${transcript_hash}"

  if cache_get "$state_cache" 2 > /dev/null 2>&1; then
    return 0
  fi

  local new_data
  new_data=$(transcript_read 2>/dev/null || true)

  if [ -n "$new_data" ]; then
    local tools="" agents="" todos_done="0" todos_total="0" last_msg_len="0"

    local last_tools tool_file=""
    last_tools=$(printf '%s' "$new_data" | grep -o '"tool_calls":\[[^]]*\]' | tail -1 || true)
    if [ -n "$last_tools" ]; then
      tools=$(printf '%s' "$last_tools" | grep -o '"name":"[^"]*"' | grep -o '[^"]*"$' | tr -d '"' | head -3 | tr '\n' ',' | sed 's/,$//')
      local raw_path
      raw_path=$(printf '%s' "$new_data" | grep -o '"file_path":"[^"]*"' | tail -1 | sed 's/"file_path":"//;s/"//' || true)
      [ -n "$raw_path" ] && tool_file="${raw_path##*/}"
    fi

    # 提取最后一条包含 subagents 的行
    local last_agents agent_model="" agent_status=""
    last_agents=$(printf '%s' "$new_data" | grep -o '"subagents":\[[^]]*\]' | tail -1 || true)
    if [ -n "$last_agents" ]; then
      agents=$(printf '%s' "$last_agents" | grep -o '"name":"[^"]*"' | grep -o '[^"]*"$' | tr -d '"' | head -3 | tr '\n' ',' | sed 's/,$//')
      # S1: 取第一个 agent 的 model/status，与显示的 name 对齐（tail-1 会错配多 agent 场景）
      agent_model=$(printf '%s' "$last_agents" | grep -o '"model":"[^"]*"' | head -1 | sed 's/"model":"//;s/"//' || true)
      agent_status=$(printf '%s' "$last_agents" | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//' || true)
    fi

    # 提取最后一条包含 todos 的行
    # S2: todo_content 靠 grep 无法可靠定位 in-progress 项（status 和 content 是独立字段），
    #     改为只显示计数，todo_content 保留为空以维持缓存格式兼容
    local last_todos todo_content=""
    last_todos=$(printf '%s' "$new_data" | grep -o '"todos":\[[^]]*\]' | tail -1 || true)
    if [ -n "$last_todos" ]; then
      todos_total=$(( $(printf '%s' "$last_todos" | grep -o '"status"' | wc -l) ))
      todos_done=$(( $(printf '%s' "$last_todos" | grep -o '"completed"' | wc -l) ))
    fi

    # 最后一条消息长度，用于估算 token 速率
    local last_msg
    last_msg=$(printf '%s' "$new_data" | grep -o '"message":"[^"]*"' | tail -1 || true)
    if [ -n "$last_msg" ]; then
      last_msg_len=${#last_msg}
    fi

    # W1: 净化可能含 | 的字段（缓存分隔符），防止读回时字段错位
    tool_file=$(printf '%s' "$tool_file" | tr '|' ' ')
    agent_model=$(printf '%s' "$agent_model" | tr '|' ' ')

    _TS_TOOLS="$tools"
    _TS_TOOL_FILE="$tool_file"
    _TS_AGENTS="$agents"
    _TS_AGENT_MODEL="$agent_model"
    _TS_AGENT_STATUS="$agent_status"
    _TS_TODOS_DONE="$todos_done"
    _TS_TODOS_TOTAL="$todos_total"
    _TS_TODO_CONTENT="$todo_content"
    _TS_LAST_MSG_LEN="$last_msg_len"

    cache_set "$state_cache" "${_TS_TOOLS}|${_TS_TOOL_FILE}|${_TS_AGENTS}|${_TS_AGENT_MODEL}|${_TS_AGENT_STATUS}|${_TS_TODOS_DONE}|${_TS_TODOS_TOTAL}|${_TS_TODO_CONTENT}|${_TS_LAST_MSG_LEN}"
  fi

  # 从缓存加载（包含刚才写入的，或上次的 stale 值）
  if [ -f "$state_cache" ]; then
    IFS='|' read -r _TS_TOOLS _TS_TOOL_FILE _TS_AGENTS _TS_AGENT_MODEL _TS_AGENT_STATUS _TS_TODOS_DONE _TS_TODOS_TOTAL _TS_TODO_CONTENT _TS_LAST_MSG_LEN \
      < "$state_cache" 2>/dev/null || true
  fi
}

module_tools() {
  local tools="${_TS_TOOLS:-}"
  [ -z "$tools" ] && return 0

  local -a _arr
  IFS=',' read -ra _arr <<< "$tools"
  local count=${#_arr[@]}
  local first_tool="${_arr[0]}"

  # 显示工具名 + 文件名(如果有)
  local file_info=""
  [ -n "${_TS_TOOL_FILE:-}" ] && file_info=": ${_TS_TOOL_FILE}"

  if [ "$count" -gt 1 ]; then
    printf '⚙ %s%s(+%d)' "$first_tool" "$file_info" "$((count - 1))"
  else
    printf '⚙ %s%s' "$first_tool" "$file_info"
  fi
}

module_agents() {
  local agents="${_TS_AGENTS:-}"
  [ -z "$agents" ] && return 0

  local -a _arr
  IFS=',' read -ra _arr <<< "$agents"
  local count=${#_arr[@]}
  local first_agent="${_arr[0]}"

  # 状态图标：running = ◐, completed = ✓
  local status="${_TS_AGENT_STATUS:-running}"
  local icon
  if [ "$status" = "completed" ] || [ "$status" = "done" ]; then
    icon="${C_GREEN}✓${C_RESET}"
  else
    icon="${C_YELLOW}◐${C_RESET}"
  fi

  # 模型名(如果有)
  local model_info=""
  [ -n "${_TS_AGENT_MODEL:-}" ] && model_info=" ${C_DIM}[${_TS_AGENT_MODEL}]${C_RESET}"

  if [ "$count" -gt 1 ]; then
    printf '%b %s%b(+%d)' "$icon" "$first_agent" "$model_info" "$((count - 1))"
  else
    printf '%b %s%b' "$icon" "$first_agent" "$model_info"
  fi
}

module_todos() {
  local done="${_TS_TODOS_DONE:-0}"
  local total="${_TS_TODOS_TOTAL:-0}"

  [ "$total" -eq 0 ] 2>/dev/null && return 0

  # 全部完成用绿色 ✓，否则用黄色 ▸；S2: 不再显示 todo 文本，只显示计数
  local icon
  if [ "$done" -eq "$total" ] 2>/dev/null; then
    icon="${C_GREEN}✓${C_RESET}"
  else
    icon="${C_YELLOW}▸${C_RESET}"
  fi

  printf '%b %d/%d' "$icon" "$done" "$total"
}

module_speed() {
  local msg_len="${_TS_LAST_MSG_LEN:-0}"
  [ "$msg_len" -lt 10 ] 2>/dev/null && return 0

  local est_tokens=$((msg_len / 4))
  [ "$est_tokens" -gt 0 ] && printf '%b%d tok/s%b' "$C_DIM" "$est_tokens" "$C_RESET"
}

# === Render ===

# 渲染完整两行 statusline
# Line 1: [model] path │ git │ duration  (身份行)
# Line 2: context+trend │ usage │ cost │ ...  (指标行)
render() {
  _update_transcript_state 2>/dev/null || true
  local sep=" │ "

  # --- Line 1 ---
  local model_out path_out git_out duration_out
  model_out=$(module_model 2>/dev/null || true)
  path_out=$(format_path "${G_PROJECT_DIR:-.}")
  git_out=$(module_git 2>/dev/null || true)
  duration_out=$(module_duration 2>/dev/null || true)

  # 拼接 line 1：model + path，再可选追加 git 和 duration
  local line1="${model_out} ${path_out}"
  [ -n "$git_out" ] && line1="${line1}${sep}${git_out}"
  [ -n "$duration_out" ] && line1="${line1}${sep}${duration_out}"

  # --- Line 2 ---
  local context_out trend_out usage_out cost_out
  local tools_out agents_out todos_out speed_out

  context_out=$(module_context 2>/dev/null || true)

  # trend 直接附着在 context 输出末尾（如 "24%↓"），不用分隔符
  trend_out=""
  [ "${CFG_SHOW_TREND:-true}" != "false" ] && trend_out=$(module_trend 2>/dev/null || true)

  [ "${CFG_SHOW_USAGE:-true}" != "false" ] && usage_out=$(module_usage 2>/dev/null || true)
  [ "${CFG_SHOW_COST:-false}" = "true" ] && cost_out=$(module_cost 2>/dev/null || true)
  tools_out=$(module_tools 2>/dev/null || true)
  agents_out=$(module_agents 2>/dev/null || true)
  todos_out=$(module_todos 2>/dev/null || true)
  [ "${CFG_SHOW_SPEED:-true}" != "false" ] && speed_out=$(module_speed 2>/dev/null || true)

  # trend 箭头紧贴 context（不插入空格或分隔符）
  local context_with_trend="${context_out}${trend_out}"

  # 将非空 segment 用 sep 串联为 line 2
  local line2="$context_with_trend"
  local segments=("$usage_out" "$cost_out" "$tools_out" "$agents_out" "$todos_out" "$speed_out")
  for seg in "${segments[@]}"; do
    [ -n "$seg" ] && line2="${line2}${sep}${seg}"
  done

  # ANSI 码已由各模块 printf '%b' 展开为原始字节，用 printf '%s' 直传不再二次解释
  printf '%s\n' "$line1"
  printf '%s\n' "$line2"
}

# === Main ===

# 所有数据源失败时的兜底输出
_fallback_output() {
  printf '%b[claude-lens]%b waiting for data...\n' "$C_CYAN" "$C_RESET"
  printf '%s\n' "░░░░░░░░░░"
}

# benchmark 模式：运行 N 次并报告耗时分布
_benchmark() {
  local iterations="${1:-100}"
  local times=()

  echo "claude-lens v${VERSION} benchmark (${iterations} iterations)"
  echo "---"

  local sample_input='{"model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"context_window":{"used_percentage":45,"context_window_size":200000},"cost":{"total_cost_usd":0.42,"total_duration_ms":5400000},"workspace":{"current_dir":".","project_dir":"."}}'

  for ((i = 1; i <= iterations; i++)); do
    local start end elapsed
    start=$(gdate +%s%N 2>/dev/null || date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    printf '%s' "$sample_input" | _run_once > /dev/null 2>&1
    end=$(gdate +%s%N 2>/dev/null || date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    elapsed=$(( (end - start) / 1000000 ))
    times+=("$elapsed")
  done

  IFS=$'\n' sorted=($(sort -n <<< "${times[*]}")); unset IFS

  local count=${#sorted[@]}
  local p50=${sorted[$((count * 50 / 100))]}
  local p95=${sorted[$((count * 95 / 100))]}
  local p99=${sorted[$((count * 99 / 100))]}
  local min=${sorted[0]}
  local max=${sorted[$((count - 1))]}

  printf 'p50: %dms\n' "$p50"
  printf 'p95: %dms\n' "$p95"
  printf 'p99: %dms\n' "$p99"
  printf 'min: %dms  max: %dms\n' "$min" "$max"

  if [ "$p95" -le 35 ]; then
    echo -e "${C_GREEN}PASS${C_RESET} - p95 within 35ms budget"
  else
    echo -e "${C_RED}FAIL${C_RESET} - p95 exceeds 35ms budget"
  fi
}

# 执行一次 statusline 渲染（benchmark 和正常模式共用）
_run_once() {
  _NOW=$(date +%s)
  local config_file="${CLAUDE_PLUGIN_DATA:-}/config"
  [ ! -f "$config_file" ] && config_file="${HOME}/.config/claude-lens/config"
  load_config "$config_file"

  if ! parse_stdin; then
    _fallback_output
    return 0
  fi

  render
}

# 将脚本注册为 Claude Code statusline（写入 settings.json）
_install() {
  local script_path settings_file tmp_file
  # realpath 解析符号链接和相对路径，确保写入绝对路径
  script_path="$(realpath "$0" 2>/dev/null)" || true
  if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
    echo "Error: cannot resolve script path" >&2
    return 1
  fi
  settings_file="${CLAUDE_LENS_SETTINGS:-${HOME}/.claude/settings.json}"

  mkdir -p "$(dirname "$settings_file")"
  # 原子创建初始 settings（与项目 cache_set 模式一致）
  if [ ! -f "$settings_file" ]; then
    tmp_file=$(mktemp)
    printf '{}' > "$tmp_file" && mv "$tmp_file" "$settings_file"
  fi

  tmp_file=$(mktemp)
  if jq --arg cmd "$script_path" \
    '.statusLine = {"type":"command","command":$cmd}' \
    "$settings_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$settings_file"; then
    echo "claude-lens activated: ${script_path}"
    echo "Restart Claude Code to apply."
  else
    rm -f "$tmp_file"
    echo "Error: failed to update ${settings_file}" >&2
    return 1
  fi
}

# 从 settings.json 中移除 statusLine 配置
_uninstall() {
  local settings_file tmp_file
  settings_file="${CLAUDE_LENS_SETTINGS:-${HOME}/.claude/settings.json}"

  if [ ! -f "$settings_file" ]; then
    echo "claude-lens deactivated (no settings file)."
    return 0
  fi

  tmp_file=$(mktemp)
  if jq 'del(.statusLine)' "$settings_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$settings_file"; then
    echo "claude-lens deactivated. Restart Claude Code to apply."
  else
    rm -f "$tmp_file"
    echo "Error: failed to update ${settings_file}" >&2
    return 1
  fi
}

main() {
  case "${1:-}" in
    --version)     echo "claude-lens v${VERSION}"; return 0 ;;
    --install)     _install; return $? ;;      # 可能失败，传播退出码
    --uninstall)   _uninstall; return $? ;;   # 同上
    --benchmark)   _benchmark "${2:-100}"; return 0 ;;
    --source-only) return 0 ;;
  esac

  _run_once
}

# Allow sourcing without executing main (for testing)
if [[ "${1:-}" != "--source-only" ]]; then
  main "$@"
fi
