---
name: setup
description: Use this skill when the user wants to set up claude-lens as their statusline, install claude-lens, or configure the statusline path. Handles first-time setup by pointing Claude Code's statusline setting to the claude-lens script.
---

# claude-lens Setup

## What This Does

Configures Claude Code to use claude-lens as its statusline by setting the statusLine field in ~/.claude/settings.json.

## Steps

1. **Find claude-lens.sh** - Locate the claude-lens.sh script. It should be in the plugin's install directory.

2. **Verify the script works** - Run a quick test:
   ```bash
   echo '{"model":{"display_name":"test"},"context_window":{},"cost":{},"workspace":{"current_dir":".","project_dir":"."}}' | /path/to/claude-lens.sh
   ```

3. **Update settings.json** - Read ~/.claude/settings.json, set the statusline command:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/absolute/path/to/claude-lens.sh"
     }
   }
   ```

4. **Confirm** - Tell the user that claude-lens is now active. The statusline will update on the next Claude Code refresh (~300ms).

## Notes

- If the user already has a statusline configured, warn them and ask before overwriting.
- The script path must be absolute (no ~ or $HOME).
- No other configuration is needed - claude-lens works with zero-config defaults.
