#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"

if ! printf '%s' "$payload" | grep -Eiq 'operation not permitted|permission denied|access denied|sandbox|deny|denied|forbidden|not authorized'; then
  exit 0
fi

cat >&2 <<'EOF'
warning: nono sandbox denial

Goose hit an OS sandbox boundary. A Goose or MCP approval can ask for action,
but it cannot grant filesystem, process, network, keychain, or launch-service
access that the active nono profile does not allow.

Useful next steps:
- Keep the work inside the current project or an allowed Goose directory.
- If this path or command should be trusted, ask the user to update the nono
  profile instead of retrying with broader Goose permissions.
- For new profile grants, prefer narrow path-specific allowances and keep
  generated caches, build output, and credentials out of broad write scopes.

Profile draft marker: ~/.config/nono/profile-drafts/.nono-goose-pack-marker
EOF
