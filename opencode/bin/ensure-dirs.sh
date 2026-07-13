#!/usr/bin/env bash
# nono session_hooks.before script.
#
# Runs on the host with host privileges, before the sandbox is applied.
# Landlock/Seatbelt can only grant a filesystem rule for a path that already
# exists, so on first run (before opencode has ever created its state dirs)
# every "$HOME/..." entry in policy.json's filesystem.allow list is missing
# and the sandboxed opencode process fails to start. Create them here, before
# the sandbox boundary goes up.
set -euo pipefail

mkdir -p \
  "$HOME/.opencode" \
  "$HOME/.config/opencode" \
  "$HOME/.cache/opencode" \
  "$HOME/.local/share/opencode" \
  "$HOME/.local/share/opentui" \
  "$HOME/.local/state/opencode"
