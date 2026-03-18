#!/usr/bin/env bats

# 集成测试：端到端验证 claude-lens.sh 实际输出行为
# 使用绝对路径避免 BATS_TEST_DIRNAME 在不同执行上下文下的歧义

SCRIPT="${BATS_TEST_DIRNAME}/../../claude-lens.sh"
FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"

setup() {
  # 只删 claude-lens 的缓存文件（非 test- 临时目录），确保每个测试从干净状态开始
  find /tmp -maxdepth 1 -name 'claude-lens-*' ! -name 'claude-lens-test-*' -type f -delete 2>/dev/null || true
}

teardown() {
  find /tmp -maxdepth 1 -name 'claude-lens-*' ! -name 'claude-lens-test-*' -type f -delete 2>/dev/null || true
}

@test "normal JSON produces two-line output" {
  run bash -c "cat '${FIXTURES}/normal.json' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -eq 2 ]
}

@test "normal JSON includes model name" {
  run bash -c "cat '${FIXTURES}/normal.json' | '$SCRIPT'"
  [[ "$output" == *"Opus 4.6"* ]]
}

@test "normal JSON includes context percentage" {
  run bash -c "cat '${FIXTURES}/normal.json' | '$SCRIPT'"
  [[ "$output" == *"45%"* ]]
}

@test "null context shows waiting state" {
  # null used_percentage 时输出应包含等待占位符（... 或空心进度条）
  run bash -c "cat '${FIXTURES}/null-context.json' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"..."* ]] || [[ "$output" == *"░░░░░░░░░░"* ]]
}

@test "empty stdin produces fallback output" {
  # 空输入时脚本应降级输出 unknown/等待状态，而非崩溃
  run bash -c "echo '' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]] || [[ "$output" == *"..."* ]] || [[ "$output" == *"claude-lens"* ]]
}

@test "malformed JSON produces fallback output" {
  # 非法 JSON 时脚本不能崩溃，必须有非空输出
  run bash -c "echo 'not json at all' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "worktree JSON shows worktree name" {
  # worktree fixture 包含 worktree.name=fix-auth-bug，应体现在输出中
  run bash -c "cat '${FIXTURES}/worktree.json' | '$SCRIPT'"
  [[ "$output" == *"fix-auth-bug"* ]] || [[ "$output" == *"project"* ]]
}

@test "--version outputs version string" {
  run "$SCRIPT" --version
  [[ "$output" == "claude-lens v"* ]]
}

@test "repeated invocations produce consistent output" {
  # 缓存命中下，两次调用结果应完全一致
  local fixture="${FIXTURES}/normal.json"
  local out1 out2
  out1=$(cat "$fixture" | "$SCRIPT" 2>/dev/null)
  out2=$(cat "$fixture" | "$SCRIPT" 2>/dev/null)
  [ "$out1" = "$out2" ]
}
