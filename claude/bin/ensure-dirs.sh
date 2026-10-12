#!/usr/bin/env bash
# nono session_hooks.before script.
#
# Runs on the host with host privileges, before the sandbox is applied.
# Landlock/Seatbelt can only attach a rule to a path that already exists, and
# silently drops the grant for one that does not.
#
# Only paths that nothing else can create belong here. Anything the pack's
# install wiring writes, or that the sandbox can create for itself because the
# profile grants its parent, is left alone.
set -euo pipefail

# Linux only
if [ "$(uname -s)" = "Linux" ]; then
  # Temp files. /tmp is tmpfs, and system_write_linux grants it write-only, so
  # Claude Code can create this but cannot read back what it wrote; the
  # profile's own /tmp/claude-$UID grant is what makes it readable, and that
  # grant needs the directory to exist first. Claude Code requires it owned by
  # us and 0700, and refuses it otherwise.
  mkdir -m 700 -p "/tmp/claude-$UID"

  # MCP and error logs, keyed by cwd. The profile takes the narrow
  # claude_cache_linux grant, which leaves ~/.cache itself unwritable.
  mkdir -p "$HOME/.cache/claude-cli-nodejs"

  # Claude Code's cross-session messaging sockets. XDG_RUNTIME_DIR is usually
  # /run/user/1000. If XDG_RUNTIME_DIR isn't set, also the profile rule won't
  # apply so we can't create a fallback directory.
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    mkdir -m 700 -p "$XDG_RUNTIME_DIR/cc-socks"
  fi
fi
