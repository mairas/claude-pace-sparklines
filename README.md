# Claude Lens

A lightweight statusline for Claude Code. ~150 lines of Bash + jq.

Other statuslines show how much you *used*. Claude Lens shows whether your *pace* is sustainable -- so you know to keep pushing or ease off before hitting a wall.

![claude-lens statusline](.github/claude-lens-showcase.png)

Reading the screenshot:

- **92%** remaining in the 5h window, **29%** remaining in the 7d window
- **+17%** green = you've used 17% less than expected at this point. Headroom. Keep going.
- **(3h)** = this window resets in 3 hours
- Colors: green (>30% left), yellow (11-30%), red (<=10%)

The top line shows model, effort, context size, project directory, and git branch with diff stats.

## Install

Requires `jq`.

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-lens/main/claude-lens.sh
chmod +x ~/.claude/statusline.sh

claude config set statusLine.command ~/.claude/statusline.sh
```

Restart Claude Code. That's it.

To remove: `claude config set statusLine.command ""`

## Under the Hood

Claude Code polls the statusline every ~300ms, so speed matters:

| Data | Source | Cache |
|------|--------|-------|
| Model, context, duration, cost | stdin JSON (single `jq` call) | None needed |
| Git branch + diff | `git` commands | `/tmp`, 5s TTL |
| Quota (5h, 7d, extra usage) | Anthropic Usage API | `/tmp`, 300s TTL, async background refresh |

Usage API calls happen in a background subshell -- the statusline never blocks on the network. If the API is unreachable, cached data stays visible until the next successful refresh.

## License

MIT
