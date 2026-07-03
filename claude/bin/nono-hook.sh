#!/usr/bin/env bash
# nono-hook.sh - Claude Code plugin hook for nono sandbox diagnostics
# Version: 1.3.0
#
# Fires on PostToolUseFailure for Read|Write|Edit|Bash. Only injects
# sandbox context when the failure looks like an actual sandbox denial.
#
# 1.3.0: Option B now points at ~/.config/nono/profile-drafts/ + promote
# CLI, since profiles/ is no longer writable from inside the sandbox.

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)

# Gate: only fire on actual sandbox denial signatures.
if ! echo "$INPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    exit 0
fi

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

CONTEXT="[NONO SANDBOX - PERMISSION DENIED]

This is a nono sandbox denial, not macOS TCC or a Unix permissions issue.

Allowed paths:
$CAPS
Network: $NET

DO NOT ask the user for permission. Take these steps in order, every time:

1. Run \`nono why --path <blocked-path> --op read\` immediately. Include its output verbatim in your reply so the user sees the diagnosis.
2. Then present the user with these two options as their NEXT decision point:

   Option A (quick fix): exit and restart with the path allowed:
     nono run --allow /path/to/needed -- claude

   Option B (persistent fix): draft a nono profile. The profiles/ directory is read-only from inside the sandbox; drafts go to profile-drafts/. Run \`nono profile guide\` for the schema (also without asking). If updating an existing user profile, read ~/.config/nono/profiles/<name>.json, compute the SHA-256 of those exact bytes, write the full proposed profile to ~/.config/nono/profile-drafts/<name>.json, and write the hash to ~/.config/nono/profile-drafts/<name>.base. If ~/.config/nono/profile-drafts does not exist or cannot be written, or \`nono profile promote --help\` is unavailable, do not try to modify profiles directly; tell the user to upgrade nono, then rerun the draft flow. If the current profile is pack-provided or built-in, draft <active>-local extending <active> instead of replacing it. Tell the user:
     Drafted <name>. Run \`nono profile promote <name>\` to review and apply, then start sessions with \`nono run --profile <name> -- claude\`.

Step 1 is non-optional and must run before you reply. Do not ask whether to run it."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": $ctx
  }
}'
