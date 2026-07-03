#!/bin/bash
# nono-hook-bash.sh - PostToolUse hook for Bash commands
# Version: 1.0.0
#
# Inspects a Bash tool result for sandbox-denial patterns and injects
# context so Claude can guide the user.

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)
OUTPUT=$(printf "%s\n" "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null)

if ! printf "%s\n" "$OUTPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
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

   Option B (persistent fix): write a nono profile. Run \`nono profile guide\` for the schema (also without asking), then save a profile JSON at ~/.config/nono/profiles/<name>.json. Start sessions with:
     nono run --profile <name> -- claude

Step 1 is non-optional and must run before you reply. Do not ask whether to run it."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
