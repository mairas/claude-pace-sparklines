#!/usr/bin/env bash
# Regression tests for claude-pace statusline
# Usage: bash test.sh
set -euo pipefail

PASS=0 FAIL=0
strip_ansi() { perl -pe 's/\e\[[0-9;]*m//g'; }
TEST_TMP=$(mktemp -d)
USAGE_ARITH_MARKER="/tmp/claudepaceusagearith$$"
cleanup_test_artifacts() {
  rm -f "$USAGE_ARITH_MARKER"
  rm -rf "$TEST_TMP"
}
trap cleanup_test_artifacts EXIT

assert_line() {
  local name="$1" line_num="$2" pattern="$3" actual
  actual=$(echo "$OUTPUT" | sed -n "${line_num}p")
  if [[ "$actual" =~ $pattern ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
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
    PASS=$((PASS + 1))
    echo "  PASS: $name (col $col1)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (L1=$col1 L2=$col2)"
  fi
}

assert_missing_path() {
  local name="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    path exists: $path"
  fi
}

assert_line_count() {
  local name="$1" expected="$2" actual
  actual=$(printf '%s\n' "$OUTPUT" | wc -l | tr -d ' ')
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected line count: $expected"
    echo "    actual line count:   $actual"
  fi
}

NOW=$(date +%s)
REPO_NAME=$(basename "$PWD")
run() { echo "$1" | bash claude-pace-sparklines.sh 2>/dev/null | strip_ansi; }
invoke_with_env() {
  local home_dir="$1" runtime_dir="$2" input="$3"
  env HOME="$home_dir" XDG_RUNTIME_DIR="$runtime_dir" USER=tester PATH="$PATH" \
    bash claude-pace-sparklines.sh 2>/dev/null <<<"$input"
}
run_with_env() {
  invoke_with_env "$1" "$2" "$3" | strip_ansi
}
run_side_effect_with_env() {
  invoke_with_env "$1" "$2" "$3" >/dev/null
}
git_cache_path_for_dir() {
  local dir="$1"
  printf '/tmp/claude-sl-git-%s\n' "${dir//[^a-zA-Z0-9]/_}"
}

init_test_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -b main >/dev/null 2>&1
  git -C "$repo_dir" config user.name tester
  git -C "$repo_dir" config user.email tester@example.com
  printf 'ok\n' >"$repo_dir/readme.txt"
  git -C "$repo_dir" add readme.txt
  git -C "$repo_dir" commit -m init >/dev/null 2>&1
}

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
assert_line "project name only" 1 "$REPO_NAME"

# ── Test 5: Pipe alignment ──
echo "Test 5: pipe alignment"
assert_aligned "| aligned between lines"

# ── Test 6: Line 2 format - single pipe, no colons, no parens on countdown ──
echo "Test 6: line 2 format"
assert_line "single pipe on L2" 2 '^[^|]+\|[^|]*$'
assert_line "no colon after 5h" 2 '5h [^:]+[0-9]'
assert_line "no colon after 7d" 2 '7d [^:]+[0-9]'
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
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'/.claude/worktrees/fix-auth"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'$((NOW + 12000))'},"seven_day":{"used_percentage":15,"resets_at":'$((NOW + 500000))'}}}')
assert_line "worktree shows repo name" 1 "$REPO_NAME"

# ── Test 10: Long model name truncation ──
echo "Test 10: long model truncation"
OUTPUT=$(run '{"model":{"display_name":"claude-3-opus-20240229-extended"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":25,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":'$((NOW + 14000))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW + 500000))'}}}')
assert_aligned "| aligned for long model"

# ── Test 11: Pace delta arrows (small values must show after threshold removal) ──
echo "Test 11: pace delta"
# 5h window=300min, resets_at=NOW+150min → expected=50%.
# used=51 → d=+1 (⇡1%, minimum positive boundary)
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":51,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":50,"resets_at":'$((NOW + 302400))'}}}')
assert_line "⇡1% shown for min overspend" 2 '5h [^:]+51% ⇡1%'
# used=49 → d=-1 (⇣1%, minimum negative boundary)
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":49,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":50,"resets_at":'$((NOW + 302400))'}}}')
assert_line "⇣1% shown for min surplus" 2 '5h [^:]+49% ⇣1%'
# used=50 → d=0 (no arrow on 5h). 7d also d=0 so no arrow anywhere.
# 7d window=10080min, resets_at=NOW+302400s=5040min → expected=(10080-5040)*100/10080=50
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":50,"resets_at":'$((NOW + 302400))'}}}')
assert_line "no arrow at d=0" 2 '5h [^:]+50% [0-9]'

# ── Test 12: Sparkline with mock history ──
echo "Test 12: sparkline rendering"
# Create mock history: 5 data points over 2.5 hours, usage rising from 5% to 50%
_HIST="$HOME/.claude/claude-pace-history.tsv"
_HIST_BAK=""
[ -f "$_HIST" ] && { _HIST_BAK=$(mktemp /tmp/claude-sl-hist-bak-XXXXXX); cp "$_HIST" "$_HIST_BAK"; }
# Window resets in 150 min (2.5h elapsed of 5h), so wstart = NOW - 150*60
_WS=$((NOW - 150 * 60))
cat >"$_HIST" <<EOF
$((_WS + 0))	5	2
$((_WS + 1800))	10	4
$((_WS + 3600))	20	6
$((_WS + 5400))	35	8
$((_WS + 7200))	50	10
EOF
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":40,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW + 600000))'}}}')
# 5h sparkline should have 8 block characters (data + future) between "5h " and the percentage
assert_line "5h sparkline present" 2 '5h .{7,}[0-9]+%'
# 7d sparkline should have 7 chars
assert_line "7d sparkline present" 2 '7d .{7,}[0-9]+%'

# ── Test 13: Sparkline without history file ──
echo "Test 13: sparkline no history"
rm -f "$_HIST"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":40,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW + 600000))'}}}')
# Should still render (empty data slots + future pace line)
assert_line "5h sparkline renders without history" 2 '5h .+[0-9]+%'
assert_aligned "| aligned with sparklines"

# ── Test 14: Sparkline alignment with rate limits ──
echo "Test 14: sparkline alignment"
OUTPUT=$(run '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":40,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'$((NOW + 9000))'},"seven_day":{"used_percentage":10,"resets_at":'$((NOW + 600000))'}}}')
assert_aligned "| aligned with sparklines (Sonnet)"

# ── Test 15: Sparkline block character correctness ──
echo "Test 15: sparkline block chars"
# Fresh session start (RM5≈300): all future pace = clean staircase ▁▂▃▄▅▆▇█
rm -f "$_HIST"
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":2,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":'$((NOW + 295*60))'},"seven_day":{"used_percentage":1,"resets_at":'$((NOW + 9999*60))'}}}')
assert_line "5h pace staircase ▁▂▃▄▅▆▇█" 2 '5h ▁▂▃▄▅▆▇█'
assert_line "7d pace staircase ▁▂▃▄▅▆▇" 2 '7d ▁▂▃▄▅▆▇'
# Near-zero data should be visible (▁ baseline, not space)
_WS2=$((NOW - 280 * 60))
cat >"$_HIST" <<EOF
$((_WS2 + 60))	1	1
EOF
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":2,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":2,"resets_at":'$((NOW + 20*60))'},"seven_day":{"used_percentage":1,"resets_at":'$((NOW + 9999*60))'}}}')
assert_line "near-zero uses ▁ not space" 2 '5h ▁'

# ── Test 16: Reset detection ──
echo "Test 16: reset detection"
# History with a mid-window reset: usage climbs to 38% then drops to 3%
_WS3=$((NOW - 200 * 60))
cat >"$_HIST" <<EOF
$((_WS3 + 1800))	10	5
$((_WS3 + 3600))	20	8
$((_WS3 + 5400))	30	10
$((_WS3 + 7200))	38	12
$((_WS3 + 9000))	3	12
$((_WS3 + 10800))	8	13
EOF
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'$((NOW + 100*60))'},"seven_day":{"used_percentage":13,"resets_at":'$((NOW + 600000))'}}}')
# After reset, data slots should only contain low values (▁).
L2=$(echo "$OUTPUT" | sed -n '2p')
SL_5H=$(echo "$L2" | sed 's/.*5h //' | head -c 8)
SL_DATA="${SL_5H:0:5}"
if echo "$SL_DATA" | grep -q '[▃▄▅▆▇█]'; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: pre-reset data leaked into graph"
  echo "    data slots: $SL_DATA"
else
  PASS=$((PASS + 1))
  echo "  PASS: reset clears pre-reset data"
fi

# ── Test 17: Low-usage reset detection ──
echo "Test 17: low-usage reset"
# Usage drops from 3% to 0% — must still detect reset
_WS4=$((NOW - 200 * 60))
cat >"$_HIST" <<EOF
$((_WS4 + 1800))	1	5
$((_WS4 + 3600))	3	8
$((_WS4 + 5400))	0	10
$((_WS4 + 7200))	2	12
EOF
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":10,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":4,"resets_at":'$((NOW + 100*60))'},"seven_day":{"used_percentage":12,"resets_at":'$((NOW + 600000))'}}}')
# After low-usage reset, pre-reset data (1%, 3%) should be cleared
# Only post-reset data (0%, 2%, live 4%) should appear
assert_line "low-usage reset detected" 2 '5h ▁'

# Restore original history file
if [ -n "$_HIST_BAK" ]; then
  mv "$_HIST_BAK" "$_HIST"
else
  rm -f "$_HIST"
fi

# ── Test 12: Branch cache must not inject newlines into output ──
echo "Test 12: branch cache newline injection"
INJECT_HOME="$TEST_TMP/inject-home"
INJECT_RUNTIME="$TEST_TMP/inject-runtime"
INJECT_DIR="$TEST_TMP/non-git-escape"
INJECT_CACHE_ROOT="$INJECT_RUNTIME/claude-pace"
mkdir -p "$INJECT_HOME" "$INJECT_RUNTIME" "$INJECT_DIR" "$INJECT_CACHE_ROOT"
GC="$INJECT_CACHE_ROOT/claude-sl-git-${INJECT_DIR//[^a-zA-Z0-9]/_}"
printf 'feature\\nPWN|0|0|0\n' >"$GC"
OUTPUT=$(run_with_env "$INJECT_HOME" "$INJECT_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$INJECT_DIR"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}')
assert_line_count "branch cache keeps output to two lines" 2

# ── Test 13: Git cache arithmetic payload must not execute ──
echo "Test 13: git cache arithmetic injection"
INJECT_GIT_HOME="$TEST_TMP/non-git-arith-home"
INJECT_GIT_RUNTIME="$TEST_TMP/non-git-arith-runtime"
INJECT_GIT_DIR="$TEST_TMP/non-git-arith"
INJECT_GIT_CACHE_ROOT="$INJECT_GIT_RUNTIME/claude-pace"
mkdir -p "$INJECT_GIT_HOME" "$INJECT_GIT_RUNTIME" "$INJECT_GIT_DIR" "$INJECT_GIT_CACHE_ROOT"
GC="$INJECT_GIT_CACHE_ROOT/claude-sl-git-${INJECT_GIT_DIR//[^a-zA-Z0-9]/_}"
GIT_MARKER="$TEST_TMP/git-arith-marker"
FC_PAYLOAD="a[\$(printf git >$GIT_MARKER)]"
printf 'main|%s|0|0\n' "$FC_PAYLOAD" >"$GC"
run_side_effect_with_env "$INJECT_GIT_HOME" "$INJECT_GIT_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$INJECT_GIT_DIR"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
assert_missing_path "git cache arithmetic payload is not executed" "$GIT_MARKER"

# ── Test 14: Usage cache arithmetic payload must not execute ──
echo "Test 14: usage cache arithmetic injection"
USAGE_HOME="$TEST_TMP/usage-arith-home"
USAGE_RUNTIME="$TEST_TMP/usage-arith-runtime"
USAGE_CACHE_ROOT="$USAGE_RUNTIME/claude-pace"
mkdir -p "$USAGE_HOME" "$USAGE_RUNTIME" "$USAGE_CACHE_ROOT"
XU_PAYLOAD="a[\$(printf usage >$USAGE_ARITH_MARKER)]"
printf '%s\n' "--|--|1|$XU_PAYLOAD|0||" >"$USAGE_CACHE_ROOT/claude-sl-usage"
run_side_effect_with_env "$USAGE_HOME" "$USAGE_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PWD"'"},"context_window":{"used_percentage":20,"context_window_size":200000}}'
assert_missing_path "usage cache arithmetic payload is not executed" "$USAGE_ARITH_MARKER"

# ── Test 15: Shared /tmp git cache must be ignored when using a private cache root ──
echo "Test 15: private cache root ignores shared tmp git cache"
PRIVATE_HOME="$TEST_TMP/private-home"
PRIVATE_RUNTIME="$TEST_TMP/private-runtime"
PRIVATE_REPO="$TEST_TMP/private-repo"
mkdir -p "$PRIVATE_HOME" "$PRIVATE_RUNTIME"
init_test_repo "$PRIVATE_REPO"
GC=$(git_cache_path_for_dir "$PRIVATE_REPO")
printf 'evil|0|0|0\n' >"$GC"
OUTPUT=$(run_with_env "$PRIVATE_HOME" "$PRIVATE_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PRIVATE_REPO"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}')
if [[ "$OUTPUT" =~ \(main\) ]] && [[ ! "$OUTPUT" =~ \(evil\) ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: private cache root ignores poisoned shared tmp cache"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: private cache root ignores poisoned shared tmp cache"
  echo "    actual line: $(printf '%s\n' "$OUTPUT" | sed -n '1p')"
fi

# ── Test 16: Cache format must preserve branch names that contain | ──
echo "Test 16: branch names containing pipes survive cache round-trip"
PIPE_HOME="$TEST_TMP/pipe-home"
PIPE_RUNTIME="$TEST_TMP/pipe-runtime"
PIPE_REPO="$TEST_TMP/pipe-repo"
mkdir -p "$PIPE_HOME" "$PIPE_RUNTIME"
init_test_repo "$PIPE_REPO"
git -C "$PIPE_REPO" checkout -b 'feat|pipe' >/dev/null 2>&1
OUTPUT=$(run_with_env "$PIPE_HOME" "$PIPE_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$PIPE_REPO"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}')
if [[ "$OUTPUT" =~ \(feat\|pipe\) ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: cache preserves branch names containing pipes"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: cache preserves branch names containing pipes"
  echo "    actual line: $(printf '%s\n' "$OUTPUT" | sed -n '1p')"
fi

# ── Test 17: Git fallback write must not follow symlinks ──
echo "Test 17: git fallback does not clobber symlink targets"
SYMLINK_HOME="$TEST_TMP/symlink-home"
SYMLINK_RUNTIME="$TEST_TMP/symlink-runtime"
SYMLINK_PROJECT="$TEST_TMP/symlink-project"
SYMLINK_CACHE_ROOT="$SYMLINK_RUNTIME/claude-pace"
SYMLINK_TARGET="$TEST_TMP/git-fallback-target"
mkdir -p "$SYMLINK_HOME" "$SYMLINK_RUNTIME" "$SYMLINK_PROJECT" "$SYMLINK_CACHE_ROOT"
GC="$SYMLINK_CACHE_ROOT/claude-sl-git-${SYMLINK_PROJECT//[^a-zA-Z0-9]/_}"
ln -s "$SYMLINK_TARGET" "$GC"
run_side_effect_with_env "$SYMLINK_HOME" "$SYMLINK_RUNTIME" '{"model":{"display_name":"Opus 4.6"},"workspace":{"project_dir":"'"$SYMLINK_PROJECT"'"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'"$((NOW + 12000))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW + 500000))"'}}}'
assert_missing_path "git fallback leaves symlink target untouched" "$SYMLINK_TARGET"

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
