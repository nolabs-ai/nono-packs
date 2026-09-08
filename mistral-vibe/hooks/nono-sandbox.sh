#!/usr/bin/env bash
# Vibe post_tool hook for nono sandbox diagnostics.
# Receives Vibe's post_tool JSON payload on stdin and returns a Vibe hook
# response on stdout.

set -euo pipefail

if [[ -z "${NONO_CAP_FILE:-}" || ! -f "$NONO_CAP_FILE" ]] || ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

payload="$(cat)"

if ! printf '%s' "$payload" | grep -Eiq 'operation not permitted|permission denied|EPERM|EACCES|sandbox[^[:alnum:]]+denied|landlock'; then
  exit 0
fi

caps="$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null || true)"
net="$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null || true)"

context="[NONO SANDBOX - PERMISSION DENIED]

This is a nono OS sandbox denial. Vibe or a tool approval cannot grant access outside the active nono profile.

Allowed paths in this session:
$caps
Network: ${net:-unknown}

Diagnose the boundary before replying:
1. Run: nono why --self --path <blocked-path> --op read. Include its output.
2. For a one-off fix, exit and restart with: nono run --profile mistral-vibe --allow /absolute/path -- vibe.
3. For repeated access, draft a child profile extending mistral-vibe under ~/.config/nono/profile-drafts/, then have the user run: nono profile promote <name>.

Do not suggest sudo, chmod, Full Disk Access, or retrying the same operation."

jq -n --arg context "$context" '{
  "hook_specific_output": {"additional_context": $context}
}'
