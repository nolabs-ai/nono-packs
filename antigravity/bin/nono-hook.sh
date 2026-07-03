#!/usr/bin/env bash
# nono-hook.sh — Antigravity CLI (agy) PostToolUse hook for nono sandbox diagnostics
# Version: 0.2.0
#
# Fires on PostToolUse for every tool. Scans the full tool-result payload for a
# nono sandbox-denial signature and, only when one is present, returns a
# systemMessage so the agent guides the user instead of flailing.
#
# Input  (agy PostToolUse, JSON on stdin — proto-backed, field names vary).
# Output (JSON on stdout): { "systemMessage": "<diagnostic>" }

NONO_HOOK_DEBUG="${NONO_HOOK_DEBUG:-0}"
LOG_FILE="${NONO_HOOK_LOG:-$HOME/.gemini/antigravity-cli/nono-hook.log}"
log() { [ "$NONO_HOOK_DEBUG" = "1" ] && echo "$(date -Iseconds) [nono-hook] $*" >> "$LOG_FILE" 2>/dev/null; }

# Only relevant inside a nono sandbox.
if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    log "skipped: not in a nono sandbox (NONO_CAP_FILE unset or missing)"
    exit 0
fi
if ! command -v jq &> /dev/null; then
    log "skipped: jq not found"
    exit 0
fi

INPUT=$(cat)

# Field names differ across agy versions (proto camelCase vs snake_case), so
# scan the entire payload rather than guessing tool_response / toolOutput.
if ! printf '%s' "$INPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    log "no sandbox-denial signature in tool result; passing through"
    exit 0
fi

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/denial.txt"
if [ ! -f "$TEMPLATE" ]; then
    log "denial template not found: $TEMPLATE"
    exit 0
fi

CONTEXT=$(cat "$TEMPLATE")
CONTEXT="${CONTEXT//__CAPS__/$CAPS}"
CONTEXT="${CONTEXT//__NET__/$NET}"

log "sandbox denial detected; injecting diagnostic"
jq -n --arg msg "$CONTEXT" '{ "systemMessage": $msg }'
