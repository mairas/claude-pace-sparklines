#!/usr/bin/env bats

setup() {
  load '../helpers'
  load_claude_lens
  setup_temp
}

teardown() {
  teardown_temp
}

@test "load_config reads valid key=value pairs" {
  echo 'PRESET=minimal' > "$TEST_CACHE_DIR/config"
  load_config "$TEST_CACHE_DIR/config"
  [ "$CFG_PRESET" = "minimal" ]
}

@test "load_config skips comments and blank lines" {
  printf '# comment\n\nPRESET=standard\n' > "$TEST_CACHE_DIR/config"
  load_config "$TEST_CACHE_DIR/config"
  [ "$CFG_PRESET" = "standard" ]
}

@test "load_config rejects keys with lowercase" {
  echo 'bad_key=value' > "$TEST_CACHE_DIR/config"
  load_config "$TEST_CACHE_DIR/config"
  [ -z "${CFG_BAD_KEY:-}" ]
}

@test "load_config rejects values with shell metacharacters" {
  echo 'SHOW_COST=$(rm -rf /)' > "$TEST_CACHE_DIR/config"
  load_config "$TEST_CACHE_DIR/config"
  [ "$CFG_SHOW_COST" = "false" ]
}

@test "load_config rejects values with backticks" {
  printf 'SHOW_COST=\x60whoami\x60\n' > "$TEST_CACHE_DIR/config"
  load_config "$TEST_CACHE_DIR/config"
  [ "$CFG_SHOW_COST" = "false" ]
}

@test "load_config uses defaults when file missing" {
  load_config "/nonexistent/path/config"
  [ "$CFG_SHOW_COST" = "false" ]
}

@test "load_config reads SHOW_COST toggle" {
  echo 'SHOW_COST=true' > "$TEST_CACHE_DIR/config"
  load_config "$TEST_CACHE_DIR/config"
  [ "$CFG_SHOW_COST" = "true" ]
}
