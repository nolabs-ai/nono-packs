#!/usr/bin/env bash
# nono session_hooks.before script. Runs on the host with host privileges,
# before the sandbox goes up: Landlock can only attach a rule to a path that
# already exists, and silently drops the grant for one that does not.
set -euo pipefail

mkdir -p \
  "$HOME/.claude" \
  "$HOME/.cache/claude" \
  "$HOME/.local/state/claude/locks"

# Claude Code's cross-session messaging sockets. On tmpfs, so gone after every
# logout. An unset XDG_RUNTIME_DIR is a skip, not an error: nono leaves the
# matching profile path unexpanded and drops that grant too.
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  mkdir -m 700 -p "$XDG_RUNTIME_DIR/cc-socks"
fi
