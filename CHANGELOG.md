# Changelog

## 0.7.2

- Fix OAuth token exposure in Usage API fallback: avoid leaking bearer token in curl argv / process listings
- Reject malformed tokens containing CR/LF before invoking curl

## 0.7.1

- Harden cache handling: move from shared `/tmp` to private per-user directory (`$XDG_RUNTIME_DIR/claude-pace` or `~/.cache/claude-pace`, mode 700)
- Validate all cache-read fields before arithmetic evaluation
- Switch cache delimiter from `|` to ASCII Unit Separator (branch names with `|` no longer corrupt parsing)
- Disable caching entirely when no safe cache directory is available

## 0.7.0

- Rename project from claude-lens to claude-pace
- Add `npx claude-pace` one-step installer
- Add plugin marketplace support

## 0.6.2

- Fix `((var++))` unsafe under `set -e` (exit status 1 when variable is 0)

## 0.6.1

- Remove ±5% silent zone for pace delta (any non-zero delta now visible)

## 0.6.0

- Display usage as used% instead of remaining% (lower = better)
- Use ⇡/⇣ arrows for pace delta (⇡ = overspend, ⇣ = surplus)
- Invert pace delta sign to match intuitive convention

## 0.5.0

- Symmetric single-pipe alignment redesign (~270 lines)
- Add performance metrics to comparison table
- Remove session duration display
