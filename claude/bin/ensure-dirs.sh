#!/usr/bin/env bash
# nono session_hooks.before script.
#
# Runs on the host with host privileges, before the sandbox is applied.
# Landlock/Seatbelt can only attach a rule to a path that already exists, and
# silently drops the grant for one that does not.
set -euo pipefail

mkdir -p \
  "$HOME/.claude" \
  "$HOME/.cache/claude" \
  "$HOME/.local/state/claude/locks"

# Claude Code's cross-session messaging sockets. XDG_RUNTIME_DIR is usually
# /run/user/1000. If XDG_RUNTIME_DIR isn't set, also the profile rule won't
# apply so we can't create a fallback directory.
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  mkdir -m 700 -p "$XDG_RUNTIME_DIR/cc-socks"
fi
