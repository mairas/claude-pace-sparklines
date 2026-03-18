---
name: configure
description: Use this skill when the user wants to configure claude-lens, change presets, toggle modules, or customize the statusline display. Supports preset selection (minimal/standard/full) and individual module toggles.
---

# claude-lens Configure

## Presets

Present the user with these preset options:

| Preset | Line 1 | Line 2 | Best For |
|--------|--------|--------|----------|
| **minimal** | Model, Context, Duration | Git | Clean, distraction-free |
| **standard** (default) | Model, Context, Trend, Duration | Git, Tools, Agents, Todos, Usage | Balanced information |
| **full** | Model, Context, Trend, Duration | Git, Tools, Agents, Todos, Cost, Speed, Usage | Maximum visibility |

## Module Toggles

These modules can be individually toggled on/off regardless of preset:

| Module | Config Key | Default | Description |
|--------|-----------|---------|-------------|
| Cost | SHOW_COST | false | Session cost in USD |
| Speed | SHOW_SPEED | true | Token output speed (tok/s) |
| Trend | SHOW_TREND | true | Context trend arrows |
| Usage | SHOW_USAGE | true | API rate limits (5h/7d) |

## How to Apply

Write the user's choices to the config file:

```bash
CONFIG_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.config/claude-lens}"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/config"

cat > "$CONFIG_FILE" << 'CONF'
# claude-lens configuration
# Preset: minimal | standard | full
PRESET=standard

# Module toggles (true/false)
SHOW_COST=false
SHOW_SPEED=true
SHOW_TREND=true
SHOW_USAGE=true
CONF
```

## Notes

- Changes take effect immediately on the next statusline refresh (~300ms).
- If no config file exists, claude-lens uses the standard preset with default toggles.
- The config file uses strict key=value format. Keys must be UPPERCASE_WITH_UNDERSCORES.
