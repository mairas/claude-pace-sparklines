# Claude Lens

> Same features, 10x faster.

A lightweight statusline plugin for [Claude Code](https://code.claude.com/), designed as a high-performance alternative to [claude-hud](https://github.com/jarrodwatts/claude-hud).

## Why

claude-hud (6K+ stars) is the only mainstream statusline solution for Claude Code. It works, but has a structural performance problem: **every 300ms, it spawns a new Node.js process, full-scans the transcript JSONL, and re-reads config files**. On long sessions, this becomes increasingly expensive.

| | claude-hud | claude-lens |
|--|-----------|-------------|
| Runtime | Node.js (cold start every 300ms) | Bash + jq |
| Single invocation | 150-300ms, 30-50MB | ~35ms, ~2.5MB |
| Transcript parsing | Full scan O(n), degrades with session length | Incremental tail O(1), constant performance |
| Cache strategy | In-memory (lost on process restart) | File-based (survives across invocations) |
| Usage API | Re-fetches on cache miss every restart | Async background fetch + stale-while-revalidate |
| Long session (8h+) | Noticeable lag | No degradation |

## Background

This project grew out of a hand-crafted `statusline.sh` (226 lines of bash) that already outperformed claude-hud on core metrics: context bar, git status, usage rate limits, and session duration. The script's file-based caching patterns (git info cached 5s, usage API cached 300s with `noclobber` file locks and atomic writes) proved both faster and more robust than claude-hud's approach.

claude-lens takes that foundation and adds the features claude-hud pioneered - tool activity tracking, subagent status, and todo progress - without sacrificing performance.

## Design Principles

1. **Bash runtime for the hot path** - The statusline is called every ~300ms. Bash + jq completes in ~35ms. Node.js cold start alone takes 80-150ms. No contest.
2. **File-based caching** - Git info, usage data, and transcript state are cached to `/tmp` files with TTLs. Survives process restarts, prevents redundant work.
3. **Incremental transcript reading** - Track file offset, only read new lines. O(1) per invocation regardless of session length.
4. **Stale-while-revalidate** - When cached data expires, serve stale data immediately while refreshing in the background. Never block the statusline on a slow API call.
5. **Plugin packaging for usability** - Core is bash, but configuration uses Claude Code's plugin skill system for interactive setup.

## Architecture

```
Every ~300ms (Claude Code calls the statusline):

  stdin JSON ──> claude-lens.sh ──> stdout (rendered lines)
                    │
                    ├── context/model/duration: direct from stdin JSON
                    ├── git info: file cache (TTL 5s)
                    ├── usage API: file cache (TTL 300s) + async bg fetch
                    └── tools/agents/todos: transcript offset cache (TTL 2s)
                              │
                              └── tail -c +<offset> transcript.jsonl
                                  (only reads new bytes since last check)

One-time setup (plugin skills):

  /claude-lens:setup      ──> configure statusline path
  /claude-lens:configure  ──> interactive preset/toggle selection
```

## Feature Parity with claude-hud

| Feature | claude-hud | claude-lens |
|---------|-----------|-------------|
| Model name + plan | Yes | Yes |
| Context progress bar | Yes | Yes (color-coded thresholds) |
| Usage rate limits (5h/7d) | Yes | Yes (stale-while-revalidate) |
| Git branch + status | Yes | Yes (+ diff line counts) |
| Session duration | Yes | Yes |
| Tool activity tracking | Yes | Yes (incremental transcript) |
| Subagent status | Yes | Yes (incremental transcript) |
| Todo progress | Yes | Yes (incremental transcript) |
| Worktree-aware paths | No | Yes |
| Interactive config | Yes | Yes (plugin skills) |
| Token output speed | Yes | Yes (estimated from transcript) |

## Unique Advantages

- **Worktree-aware path display**: Detects `.claude/worktrees/` paths and shows `project/worktree-name` instead of the full path.
- **Diff line statistics**: Shows `3f +45 -12` (files changed, lines added, lines deleted), not just a dirty indicator.
- **Robust lock handling**: `noclobber`-based file locks with stale lock detection (10s timeout), solving claude-hud's [#220](https://github.com/jarrodwatts/claude-hud/issues/220) permanently.
- **Graceful degradation**: If any data source fails, serves last known good value. Never shows a blank statusline.

## Market Context

Statusline monitoring is a growing category driven by Claude Code's ecosystem expansion:

- **1M context GA** (2026-03-13): Larger context windows make real-time usage monitoring essential, not optional.
- **Output limits doubled** (CC v2.1.77, 2026-03-17): Opus 4.6 output cap raised to 64K-128K tokens, amplifying the need for context visibility.
- **Plugin infrastructure matured** (CC v2.1.78, 2026-03-17): `${CLAUDE_PLUGIN_DATA}` for persistent state, `StopFailure` hooks - plugins are now first-class citizens.

claude-hud gained 466 stars in a single day (2026-03-18) on these tailwinds alone - no viral post, just organic demand from an expanding user base. The bigger the context, the longer the session, the more users need monitoring. This is exactly where claude-lens's O(1) performance advantage matters most.

## Status

V1 complete. All features implemented with 50 tests (unit + integration). Plugin packaging with setup and configure skills ready. Performance benchmark: p50 ~37ms.

## License

MIT
