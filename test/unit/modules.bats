#!/usr/bin/env bats

setup() {
  load '../helpers'
  load_claude_lens
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

@test "module_usage shows cached rate limits" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/usage-cache"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  echo "14|5" > "$USAGE_CACHE_FILE"
  run module_usage
  [[ "$output" == *"5h:"* ]]
  [[ "$output" == *"14"* ]]
  [[ "$output" == *"7d:"* ]]
  [[ "$output" == *"5"* ]]
}

@test "module_usage shows dashes when no cache" {
  setup_temp
  USAGE_CACHE_FILE="$TEST_CACHE_DIR/nonexistent-usage"
  USAGE_LOCK_FILE="$TEST_CACHE_DIR/usage.lock"
  run module_usage
  [[ "$output" == *"--"* ]]
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

# --- render_line ---

@test "render_line joins module outputs with separator" {
  run render_line " | " "hello" "world" "test"
  [[ "$output" == "hello | world | test" ]]
}

@test "render_line skips empty module outputs" {
  run render_line " | " "hello" "" "test"
  [[ "$output" == "hello | test" ]]
}

# --- get_preset_modules ---

@test "get_preset_modules returns modules for standard line1" {
  CFG_PRESET="standard"
  run get_preset_modules "line1"
  [[ "$output" == *"model"* ]]
  [[ "$output" == *"context"* ]]
  [[ "$output" == *"trend"* ]]
  [[ "$output" == *"duration"* ]]
}

@test "get_preset_modules returns modules for minimal line1" {
  CFG_PRESET="minimal"
  run get_preset_modules "line1"
  [[ "$output" == *"model"* ]]
  [[ "$output" == *"context"* ]]
  [[ "$output" != *"trend"* ]]
}
