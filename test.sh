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
OUTPUT=$(run '{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"project_dir":"'"$HOME"'/workspace/dev/claude-lens/.claude/worktrees/fix-auth"},"context_window":{"used_percentage":20,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":'$((NOW + 12000))'},"seven_day":{"used_percentage":15,"resets_at":'$((NOW + 500000))'}}}')
assert_line "worktree shows repo name" 1 'claude-lens'

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
_HIST="$HOME/.claude/claude-lens-history.tsv"
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

# ── Summary ──
echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
