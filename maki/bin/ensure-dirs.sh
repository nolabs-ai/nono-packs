#!/usr/bin/env bash
# nono session_hooks.before script. Runs on the host with host privileges,
# before the sandbox goes up: Landlock can only attach a rule to a path that
# already exists, and silently drops the grant for one that does not.
set -euo pipefail

mkdir -p \
  "$HOME/.config/maki" \
  "$HOME/.local/share/maki" \
  "$HOME/.local/state/maki" \
  "$HOME/.local/logs/maki" \
  "$HOME/.cache/maki"

# Never create "$HOME/.maki" here: maki collapses its whole layout onto the
# legacy directory the moment it exists, which would bypass the XDG paths
# this profile grants.
