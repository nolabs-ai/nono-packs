#!/usr/bin/env bash
# nono session_hooks.before script.
#
# Runs before the sandboxed command starts. Nono resolves filesystem
# capabilities before this hook runs, so a hook cannot rescue a standalone
# grant that was dropped because its path did not exist. New runtime paths
# must live beneath an existing parent that the profile already grants.
#
set -euo pipefail

require_absolute_root() {
  local name="$1"
  local value="$2"

  case "$value" in
    /*) ;;
    *)
      printf 'nono claude setup: %s must be an absolute path: %s\n' "$name" "$value" >&2
      return 1
      ;;
  esac
}

ensure_private_dir() {
  local dir="$1"

  # Claude Code rejects its private runtime directories when they are symlinks,
  # owned by another user, or accessible by group/other. Reject unsafe existing
  # paths rather than following a predictable name in a shared temp directory.
  if [ -L "$dir" ]; then
    printf 'nono claude setup: refusing symlink: %s\n' "$dir" >&2
    return 1
  fi

  if [ ! -e "$dir" ]; then
    # The parent must already exist. Avoid mkdir -p here so an invalid root
    # cannot create an unexpected directory tree.
    if ! mkdir -m 700 "$dir"; then
      # Another process may have created it between the existence check and
      # mkdir. Validate the resulting path below; otherwise report the error.
      [ -e "$dir" ] || return 1
    fi
  fi

  if [ -L "$dir" ] || [ ! -d "$dir" ] || [ ! -O "$dir" ]; then
    printf 'nono claude setup: private directory must be a user-owned directory: %s\n' "$dir" >&2
    return 1
  fi

  # mkdir -m does not repair an existing directory's mode.
  chmod 700 "$dir"
}

# Preserve the directories prepared by earlier pack versions. They may be
# absent on a fresh installation or after a cache cleanup, and their parents
# are not generally writable inside the sandbox.
mkdir -p \
  "$HOME/.claude" \
  "$HOME/.cache/claude" \
  "$HOME/.local/state/claude/locks"

# The profile points TMPDIR inside ~/.claude, whose parent is prepared by nono
# before capability resolution and granted readwrite as a whole. A before-hook
# cannot make a missing standalone profile path usable for the current session:
# nono has already resolved capabilities by the time the hook runs.
ensure_private_dir "$HOME/.claude/tmp"
ensure_private_dir "$HOME/.claude/tmp/claude-$UID"

# Linux-only paths.
if [ "$(uname -s)" = "Linux" ]; then
  # Claude Code's cross-session messaging sockets. XDG_RUNTIME_DIR is usually
  # /run/user/1000. If XDG_RUNTIME_DIR isn't set, also the profile rule won't
  # apply so we can't create a fallback directory.
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    require_absolute_root XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
    ensure_private_dir "$XDG_RUNTIME_DIR/cc-socks"
  fi
fi
