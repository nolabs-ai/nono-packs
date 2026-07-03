#!/usr/bin/env bash
# nono-hook-session.sh - Codex SessionStart hook
# Version: 1.2.0
#
# Compatibility no-op. Older installs may still have this SessionStart
# hook registered in ~/.codex/hooks.json; emitting additionalContext makes
# Codex render a noisy "hook context" block at the top of every session.
exit 0
