# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Pace Sparklines is a lightweight statusline plugin for Claude Code that tracks quota usage and displays a real-time pace indicator with inline sparkline graphs. It is a fork of [Astro-Han/claude-pace](https://github.com/Astro-Han/claude-pace).

The entire tool is a single Bash script (`claude-pace-sparklines.sh`) with zero npm/Node.js dependencies. The only runtime dependency is `jq`.

## Commands

```bash
# Run tests (no framework — just bash)
bash test.sh

# Run the script manually with test input (reads JSON from stdin)
echo '{"model":"claude-sonnet-4-20250514","contextWindow":{"used":50000,"total":200000}}' | bash claude-pace-sparklines.sh
```

There is no build step, linter, or package manager for the main project.

## Architecture

### `claude-pace-sparklines.sh` — Single-file architecture (~380 lines)

The script reads JSON from stdin (provided by Claude Code's statusline system) and outputs a two-line statusline string with ANSI color codes.

**Data flow:**
1. **Parse input** — Single `jq` call extracts model, context, usage %, countdown times, rate limits
2. **Git info** — Branch name + diff stats, cached per-repo for 5 seconds (atomic file writes)
3. **Usage data** — Two sources:
   - Preferred: `rate_limits` from stdin (CC ≥ 2.1.80, no network needed)
   - Fallback: Anthropic Usage API with background async fetch, 300s cache TTL
4. **History** — Appends to `~/.claude/claude-pace-sparklines-history.tsv` at 10-min intervals, auto-rotates at 1500 lines
5. **Sparklines** — 8 slots for 5h window, 7 slots for 7d window. Past slots colored by pace (green=under, red=over), future slots show dark gray pace reference line
6. **Output assembly** — Two lines with symmetric pipe alignment (measures plain text width excluding ANSI codes)

### Key design decisions

- **Performance target:** ~10ms execution (3% of refresh cycle)
- **Atomic file operations** for cache/history to prevent partial reads under concurrency
- **Background async API fetches** so network latency never blocks the statusline
- **Reset detection:** 5% drop threshold detects when usage windows reset mid-cycle
- **Forward-fill with monotonicity enforcement** preserves the cumulative property in sparkline visualization

### `test.sh` — Test suite (~210 lines, 17 test cases)

Tests use helper functions: `strip_ansi()` removes color codes, `assert_line()` does regex matching on output lines, `assert_aligned()` verifies pipe column alignment. Tests cover model names, context formatting, git stats, countdown formatting, pace deltas, sparklines, and window reset detection.

### Plugin system

- `.claude-plugin/plugin.json` — Plugin metadata and version
- `commands/setup.md` — Interactive setup guide executed during plugin installation
