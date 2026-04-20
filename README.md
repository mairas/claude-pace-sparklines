# Claude Pace Sparklines

A statusline for Claude Code with pace tracking and sparkline usage graphs. Single Bash file, zero npm. Only requires `jq`.

![claude-pace statusline](.github/sparklines.png)

## What It Shows

Most statuslines show "you used 60%." That number means nothing without context — 60% with 30 minutes left is fine, but 60% with 4 hours left means you're about to hit the wall. Claude Pace compares your usage rate to the time remaining and shows the delta.

**Line 1:** model, effort indicator (●/◑/◔), context window bar, project (branch), git diff stats

**Line 2:** 5h and 7d usage windows, each with:

- **Sparkline graph** (▁▂▃▄▅▆▇█) — past slots colored green (under pace) or red (over pace), future slots show the pace reference line in dark gray
- **Used %** — current usage in the window
- **Pace delta** — **⇣15%** green = 15% under pace, headroom; **⇡15%** red = 15% over pace, slow down
- **Countdown** — time until the window resets

## Install

Requires `jq` (`brew install jq` on macOS, `apt install jq` on Linux).

```bash
curl -fsSL -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/mairas/claude-pace-sparklines/main/claude-pace-sparklines.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Restart Claude Code. Done.

To upgrade, re-run the `curl` command. To remove, delete the `statusLine` block from `~/.claude/settings.json`.

## Under the Hood

Claude Code polls the statusline every ~300ms:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, cost | stdin JSON (single `jq` call) | None needed |
| Quota (5h, 7d, pace) | stdin `rate_limits` | None needed (real-time) |
| Git branch + diff | `git` commands | Private cache dir, 5s TTL |
| Sparkline history | `~/.claude/claude-pace-sparklines-history.tsv` | Append-only, 10-min interval, auto-rotates at 1500 lines |

Usage data comes directly from stdin — no network calls needed. Git cache files live in a private per-user directory (`$XDG_RUNTIME_DIR/claude-pace-sparklines` or `~/.cache/claude-pace-sparklines`, mode 700). No files are ever written to shared `/tmp`.

## Attribution

Forked from [Astro-Han/claude-pace](https://github.com/Astro-Han/claude-pace). This fork adds sparkline usage graphs and is maintained independently.

## License

MIT
