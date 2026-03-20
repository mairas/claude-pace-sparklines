---
description: Install and configure claude-lens statusline
allowed-tools: Bash, Read, Write, Edit
---

# claude-lens Setup

You are setting up claude-lens, a lightweight statusline for Claude Code.

Follow these steps in order. If any step fails, stop and explain the issue to the user.

## Step 1: Check prerequisites

Run: `command -v jq`

If jq is not found, tell the user to install it (`brew install jq` on macOS, `apt install jq` on Linux) and stop.

## Step 2: Determine plugin install path

The plugin was installed via the Claude Code plugin system. Find the claude-lens.sh script within the plugin directory.

Run: `find ~/.claude/plugins/claude-lens* -name "claude-lens.sh" 2>/dev/null | head -1`

If found, save that path as SCRIPT_PATH.

If not found, fall back to downloading:
```bash
curl -fsSL -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/Astro-Han/claude-lens/main/claude-lens.sh
chmod +x ~/.claude/statusline.sh
```
Set SCRIPT_PATH to `~/.claude/statusline.sh`.

## Step 3: Ensure the script is executable

Run: `chmod +x <SCRIPT_PATH>`

## Step 4: Configure statusline

Run: `claude config set statusLine.command <SCRIPT_PATH>`

## Step 5: Confirm

Tell the user:

- claude-lens has been configured successfully.
- Restart Claude Code (or start a new session) to see the statusline.
- To remove later: `claude config set statusLine.command ""`
