#!/usr/bin/env bash
# Regression tests for claude-lens statusline
# Usage: bash test.sh
set -euo pipefail

PASS=0 FAIL=0
strip_ansi() { perl -pe 's/\e\[[0-9;]*m//g'; }

assert_line() {
  local name="$1" line_num="$2" pattern="$3" actual
  actual=$(echo "$OUTPUT" | sed -n "${line_num}p")
  if [[ "$actual" =~ $pattern ]]; then
    ((PASS++))
    echo "  PASS: $name"
  else
    ((FAIL++))
    echo "  FAIL: $name"
    echo "    expected pattern: $pattern"
    echo "    actual:           $actual"
  fi
}

# Pipe alignment check: | must be at same column on both lines
assert_aligned() {
  local name="$1"
  local col1 col2 l1 l2
  l1=$(echo "$OUTPUT" | sed -n '1p') l2=$(echo "$OUTPUT" | sed -n '2p')
  col1=${l1%%|*} col2=${l2%%|*}
  col1=${#col1} col2=${#col2}
  if [[ "$col1" == "$col2" ]]; then
    ((PASS++))
    echo "  PASS: $name (col $col1)"
  else
    ((FAIL++))
    echo "  FAIL: $name (L1=$col1 L2=$col2)"
  fi
}

NOW=$(date +%s)
run() { echo "$1" | bash claude-lens.sh 2>/dev/null | strip_ansi; }

# ── Test 1: MODEL_SHORT strips "(1M context)" → "(1M)" ──
echo "Test 1: MODEL_SHORT"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":16,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":17,"resets_at":'$((NOW + 2580))'},"seven_day":{"used_percentage":21,"resets_at":'$((NOW + 345600))'}}}')
assert_line "model shows (1M) not (1M context)" 1 'Opus 4\.6 \(1M\)'
assert_line "no brackets around model" 1 '^Opus'

# ── Test 2: Model without context in name gets (CL) appended ──
echo "Test 2: MODEL_SHORT append"
OUTPUT=$(run '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":50,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":57,"resets_at":'$((NOW + 7200))'},"seven_day":{"used_percentage":35,"resets_at":'$((NOW + 432000))'}}}')
assert_line "appends (200K)" 1 'Sonnet 4\.6 \(200K\)'

# ── Test 3: CTX=0 should NOT append "(0K)" ──
echo "Test 3: CTX=0 guard"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":0,"context_window_size":0}}')
assert_line "no (0K) in model" 1 '^Opus 4\.6 [^(]'

# ── Test 4: Branch in parentheses ──
echo "Test 4: branch format"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":16,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":17,"resets_at":'$((NOW + 2580))'},"seven_day":{"used_percentage":21,"resets_at":'$((NOW + 345600))'}}}')
assert_line "branch in parens (main)" 1 '\(main\)'
assert_line "project name only" 1 'claude-lens'

# ── Test 5: Pipe alignment ──
echo "Test 5: pipe alignment"
assert_aligned "| aligned between lines"

# ── Test 6: Line 2 format - single pipe, no colons, no parens on countdown ──
echo "Test 6: line 2 format"
assert_line "single pipe on L2" 2 '^[^|]+\|[^|]*$'
assert_line "no colon after 5h" 2 '5h [0-9]'
assert_line "no colon after 7d" 2 '7d [0-9]'
assert_line "no parens on countdown" 2 '[0-9]+[dhm][^)]'
assert_line "no 'of' before context size" 2 '^[^ ]+ [0-9]+% [0-9]+[MK] '

# ── Test 7: Different model alignment ──
echo "Test 7: Sonnet alignment"
OUTPUT=$(run '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":50,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":57,"resets_at":'$((NOW + 7200))'},"seven_day":{"used_percentage":35,"resets_at":'$((NOW + 432000))'}}}')
assert_aligned "| aligned for Sonnet"

# ── Test 8: 100% context alignment ──
echo "Test 8: 100% context alignment"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":100,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":92,"resets_at":'$((NOW + 600))'},"seven_day":{"used_percentage":79,"resets_at":'$((NOW + 172800))'}}}')
assert_aligned "| aligned at 100%"

# ── Test 9: Worktree path ──
echo "Test 9: worktree"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$HOME"'/workspace/dev/claude-lens/.claude/worktrees/fix-auth"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'$((NOW + 12000))'},"seven_day":{"used_percentage":15,"resets_at":'$((NOW + 500000))'}}}')
assert_line "worktree shows repo name" 1 'claude-lens'

# ── Test 10: Long model name truncation ──
echo "Test 10: long model truncation"
OUTPUT=$(run '{"model":{"display_name":"claude-3-opus-20240229-extended"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":25,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":'$((NOW + 14000))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW + 500000))'}}}')
assert_aligned "| aligned for long model"

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
