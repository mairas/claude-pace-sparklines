#!/usr/bin/env bats

setup() {
  load '../helpers'
  load_claude_lens
}

strip_ansi() {
  printf '%s' "$1" | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'
}

# --- module_model ---

@test "module_model displays model name" {
  G_MODEL_NAME="Opus 4.6"
  run module_model
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 4.6"* ]]
}

@test "module_model shows unknown when model name empty" {
  G_MODEL_NAME=""
  run module_model
  [[ "$output" == *"unknown"* ]]
}

# --- module_duration ---

@test "module_duration formats seconds correctly" {
  G_DURATION_MS="45000"
  run module_duration
  [[ "$output" == *"0m 45s"* ]]
}

@test "module_duration formats minutes and seconds" {
  # 5分30秒 = 330000ms，不满 1 小时，应显示 5m 30s
  G_DURATION_MS="330000"
  run module_duration
  [[ "$output" == *"5m 30s"* ]]
}

@test "module_duration handles zero" {
  G_DURATION_MS="0"
  run module_duration
  [[ "$output" == *"0m 0s"* ]]
}

@test "module_duration handles hours" {
  G_DURATION_MS="7200000"
  run module_duration
  [[ "$output" == *"2h 0m"* ]]
}

# --- module_cost ---

@test "module_cost displays dollar amount" {
  G_COST_USD="0.42"
  run module_cost
  [[ "$output" == *'$0.42'* ]]
}

@test "module_cost returns empty for missing cost" {
  G_COST_USD=""
  run module_cost
  [ -z "$output" ]
}

@test "module_cost formats zero cost" {
  G_COST_USD="0"
  run module_cost
  [[ "$output" == *'$0.00'* ]]
}

# --- module_context ---

@test "module_context shows green bar under 40%" {
  G_CONTEXT_PCT="35"
  G_CTX_SIZE="200000"
  run module_context
  [[ "$output" == *"35%"* ]]
  [[ "$output" == *"200K"* ]]
}

@test "module_context shows yellow bar at 45%" {
  G_CONTEXT_PCT="45"
  G_CTX_SIZE="200000"
  run module_context
  [[ "$output" == *"45%"* ]]
}

@test "module_context shows red bar at 85%" {
  G_CONTEXT_PCT="85"
  G_CTX_SIZE="1000000"
  run module_context
  [[ "$output" == *"85%"* ]]
  [[ "$output" == *"1M"* ]]
}

@test "module_context shows waiting text when pct is empty" {
  G_CONTEXT_PCT=""
  G_CTX_SIZE="200000"
  run module_context
  [[ "$output" == *"..."* ]]
}

# --- module_trend ---

@test "module_trend shows nothing with no history" {
  setup_temp
  G_CONTEXT_PCT="45"
  TREND_FILE="$TEST_CACHE_DIR/trend"
  run module_trend
  # 第一个数据点，无方向判断，输出为空
  [ "$status" -eq 0 ]
}

@test "module_trend shows up arrow when context increasing" {
  setup_temp
  TREND_FILE="$TEST_CACHE_DIR/trend"
  printf '%s\n' "100:20" "200:30" "300:40" > "$TREND_FILE"
  G_CONTEXT_PCT="50"
  run module_trend
  [[ "$output" == *"↑"* ]]
}

@test "module_trend shows down arrow when context decreasing" {
  setup_temp
  TREND_FILE="$TEST_CACHE_DIR/trend"
  printf '%s\n' "100:80" "200:70" "300:60" > "$TREND_FILE"
  G_CONTEXT_PCT="50"
  run module_trend
  [[ "$output" == *"↓"* ]]
}

@test "module_trend shows flat arrow when context stable" {
  setup_temp
  TREND_FILE="$TEST_CACHE_DIR/trend"
  printf '%s\n' "100:50" "200:50" "300:50" > "$TREND_FILE"
  G_CONTEXT_PCT="50"
  run module_trend
  [[ "$output" == *"→"* ]]
}

@test "module_trend ring buffer truncates at 10 entries" {
  setup_temp
  TREND_FILE="$TEST_CACHE_DIR/trend"
  for i in $(seq 1 12); do
    echo "${i}00:${i}0" >> "$TREND_FILE"
  done
  G_CONTEXT_PCT="55"
  module_trend
  local lines
  lines=$(wc -l < "$TREND_FILE" | tr -d ' ')
  [ "$lines" -le 10 ]
}

# --- module_git ---

@test "module_git shows branch and diff stats from cache" {
  setup_temp
  GIT_CACHE_DIR="$TEST_CACHE_DIR"
  G_PROJECT_DIR="/tmp/test-project"
  local hash
  hash=$(printf '%s' "/tmp/test-project" | md5 -q 2>/dev/null || printf '%s' "/tmp/test-project" | md5sum 2>/dev/null | cut -d' ' -f1)
  # 新格式：branch|files|added|deleted|ahead|behind（6 字段）
  echo "main|3|45|12|0|0" > "$TEST_CACHE_DIR/claude-lens-git-${hash}"
  run module_git
  [[ "$output" == *"main"* ]]
  [[ "$output" == *"3f"* ]]
  [[ "$output" == *"+45"* ]]
  [[ "$output" == *"-12"* ]]
}

@test "module_git shows empty for non-git directory" {
  setup_temp
  GIT_CACHE_DIR="$TEST_CACHE_DIR"
  G_PROJECT_DIR="/tmp/nonexistent-dir-12345"
  run module_git
  [ -z "$output" ]
}

# --- module_usage ---

@test "module_usage shows remaining percentage" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  # used: 5h=14%, 7d=5% → remaining: 5h=86%, 7d=95%
  echo "14|5" > "$USAGE_CACHE_FILE"
  run module_usage
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"86%"* ]]
  [[ "$output" == *"7d:"* ]]
  [[ "$output" == *"95%"* ]]
}

@test "module_usage shows dashes when no cache" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/nonexistent-usage"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  run module_usage
  [[ "$output" == *"--"* ]]
}

@test "module_usage shows deficit delta on 5h (red -N%)" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  # used: 5h=60%, 7d=15% → remaining: 5h=40%, 7d=85%
  # 5h: expected_used=40%, reserve=40-60=-20 (deficit)
  # 7d: expected_used=20%, reserve=20-15=+5 (within threshold)
  echo "60|15|180|8000" > "$USAGE_CACHE_FILE"
  run module_usage
  local plain
  plain=$(strip_ansi "$output")
  printf '%s' "$plain" | grep -F "5h: 40% -20% (3h 0m)" > /dev/null
  # 7d on-track, no delta
  [[ "$plain" == *"7d: 85%"* ]]
  [[ "$plain" != *"7d: 85% +"* ]]
  [[ "$plain" != *"7d: 85% -"* ]]
}

@test "module_usage shows reserve delta on 7d (green +N%)" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  # used: 5h=40%, 7d=10% → remaining: 5h=60%, 7d=90%
  # 5h: expected_used=40%, on-track
  # 7d: expected_used=50%, reserve=50-10=+40 (green)
  echo "40|10|180|5000" > "$USAGE_CACHE_FILE"
  run module_usage
  local plain
  plain=$(strip_ansi "$output")
  printf '%s' "$plain" | grep -F "5h: 60% (3h 0m)" > /dev/null
  printf '%s' "$plain" | grep -F "7d: 90% +40%" > /dev/null
}

@test "module_usage handles old 3-field cache gracefully" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  echo "14|5|90" > "$USAGE_CACHE_FILE"
  run module_usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"7d:"* ]]
}

@test "module_usage handles 2-field cache gracefully" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  echo "14|5" > "$USAGE_CACHE_FILE"
  run module_usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"7d:"* ]]
}

@test "module_usage refreshes fresh legacy 3-field cache in background" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  echo "14|5|90" > "$USAGE_CACHE_FILE"
  _fetch_usage_bg() {
    printf 'called' > "$TEST_CACHE_DIR/fetch-called"
  }
  run module_usage
  [ -f "$TEST_CACHE_DIR/fetch-called" ]
}

@test "module_usage ages reset minutes using cache file age" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  echo "60|15|180|8000" > "$USAGE_CACHE_FILE"
  local old_ts
  old_ts=$(date -v-3M +%Y%m%d%H%M.%S 2>/dev/null || date -d '3 minutes ago' +%Y%m%d%H%M.%S)
  touch -t "$old_ts" "$USAGE_CACHE_FILE"
  run module_usage
  local plain
  plain=$(strip_ansi "$output")
  # used=60% → remaining=40%; aged: reset_min_5h=180-3=177, expected=41, reserve=41-60=-19
  printf '%s' "$plain" | grep -F "5h: 40% -19% (2h 57m)" > /dev/null
}

# --- _pace_delta ---

@test "_pace_delta returns empty when on-track (reserve within ±10)" {
  # actual=40, expected=40, reserve=0
  run _pace_delta 40 180 300
  [ "$output" = "" ]
}

@test "_pace_delta returns green +N% when reserve (under-consuming)" {
  # actual=10, expected=40, reserve=+30
  run _pace_delta 10 180 300
  local plain
  plain=$(strip_ansi "$output")
  [ "$plain" = " +30%" ]
}

@test "_pace_delta returns red -N% when deficit (over-consuming)" {
  # actual=60, expected=40, reserve=-20
  run _pace_delta 60 180 300
  local plain
  plain=$(strip_ansi "$output")
  [ "$plain" = " -20%" ]
}

@test "_pace_delta returns empty at ±10 boundary (reserve=-10)" {
  # actual=50, expected=40, reserve=-10 (within threshold)
  run _pace_delta 50 180 300
  [ "$output" = "" ]
}

@test "_pace_delta returns -N% just beyond -10 boundary" {
  # actual=51, expected=40, reserve=-11
  run _pace_delta 51 180 300
  local plain
  plain=$(strip_ansi "$output")
  [ "$plain" = " -11%" ]
}

@test "_pace_delta returns empty when reset_min is empty" {
  run _pace_delta 42 "" 300
  [ "$output" = "" ]
}

@test "_pace_delta returns empty when reset_min is non-numeric" {
  run _pace_delta 42 "abc" 300
  [ "$output" = "" ]
}

@test "_pace_delta returns empty when reset_min > duration" {
  run _pace_delta 42 400 300
  [ "$output" = "" ]
}

# --- format_path ---

@test "format_path shortens home directory" {
  run format_path "${HOME}/project"
  [[ "$output" == "~/project" ]]
}

@test "format_path detects worktree path" {
  run format_path "/Users/test/project/.claude/worktrees/fix-auth-bug"
  [[ "$output" == "project/fix-auth-bug" ]]
}

@test "format_path truncates long paths" {
  run format_path "/very/long/path/that/goes/on/and/on/and/on/and/on/forever/project"
  [ "${#output}" -le 46 ]
}
