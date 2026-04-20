---
title: Tests silently pass after renaming cache/data paths
date: 2026-04-20
category: test-failures
module: claude-pace
problem_type: test_failure
component: testing_framework
symptoms:
  - All tests pass despite path mismatch between script and test setup
  - Security injection tests pass vacuously — poison placed in old cache dir, script reads from new dir
  - User sparkline history lost on upgrade due to unrenamed history file
root_cause: test_isolation
resolution_type: test_fix
severity: high
tags:
  - bash-testing
  - path-isolation
  - silent-failure
  - security-testing
  - data-migration
---

# Tests silently pass after renaming cache/data paths

## Problem

When renaming internal path identifiers (cache dirs, history files) in a bash script, tests that independently construct those paths via hardcoded strings continue to pass because they create directories the script never reads. Security injection tests pass vacuously and user data is lost on upgrade.

## Symptoms

- 35/35 tests pass after renaming `claude-pace` to `claude-pace-sparklines` in the script
- Security tests inject poison into `$INJECT_RUNTIME/claude-pace/` but script reads from `$INJECT_RUNTIME/claude-pace-sparklines/`
- Sparkline history tests write mock data to `claude-pace-history.tsv` but script reads `claude-pace-sparklines-history.tsv`
- Existing users lose accumulated sparkline history on upgrade

## What Didn't Work

- **Test pass rate as correctness signal** — all tests green despite 5 broken cache paths and 1 broken history path
- **Manual review of the rename diff** — path mismatches in test setup were not caught until structured code review (ce:review) with adversarial and correctness reviewers cross-referencing script and test code

## Solution

Three changes applied:

**1. Sync test cache paths** (5 occurrences in test.sh):

```bash
# Before
INJECT_CACHE_ROOT="$INJECT_RUNTIME/claude-pace"

# After
INJECT_CACHE_ROOT="$INJECT_RUNTIME/claude-pace-sparklines"
```

**2. Sync test history path:**

```bash
# Before
_HIST="$HOME/.claude/claude-pace-history.tsv"

# After
_HIST="$HOME/.claude/claude-pace-sparklines-history.tsv"
```

**3. Add data migration for existing users:**

```bash
# One-liner after HIST variable declaration
[ ! -f "$HIST" ] && [ -f "$HOME/.claude/claude-pace-history.tsv" ] && mv "$HOME/.claude/claude-pace-history.tsv" "$HIST"
```

## Why This Works

Tests and script must agree on paths for injection tests to actually exercise the code under test. When the script creates cache dir `claude-pace-sparklines` and the test injects poison into `claude-pace`, the script never finds the poison — the test passes without testing anything. Syncing paths ensures poison is placed where the script reads, validating that the script correctly handles malicious cache content.

The migration one-liner preserves user data by atomically renaming the old history file on first run. Existence checks prevent re-running on subsequent invocations.

## Prevention

- **After any path rename, grep tests for hardcoded references:** `grep -r 'claude-pace[^-]' test.sh` would have caught all 6 mismatches immediately
- **Consider deriving test paths from the script** rather than duplicating string constants — e.g., source a shared variable or extract the cache dir name from the script
- **Data file renames always need migration code** — no rename-only refactors for user-visible files
- **Adversarial code review question:** "If I change a data path in the main code, would tests still pass for the wrong reason?"

## Related Issues

- First solution doc for this repo; no prior related documentation
