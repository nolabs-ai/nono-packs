#!/bin/bash
# nono-hook.sh — GitHub Copilot CLI nono sandbox diagnostics hook
# Version: 0.1.0
#
# Fires on PostToolUseFailure. Reads context from ../context/denial.txt,
# substitutes live capability data, and injects it so the agent understands
# what was blocked and how the user can fix it.
#
# Input schema (VS Code compat): { hook_event_name, tool_name, tool_input, error }
# Output schema: { hookSpecificOutput: { hookEventName, additionalContext } }
# NOTE: output schema needs verification against Copilot CLI hook runtime.
# See NOTES.md for details.
NONO_HOOK_DEBUG=1
LOG_FILE="${NONO_HOOK_LOG:-$HOME/.copilot/nono-hook.log}"
log() { [ "${NONO_HOOK_DEBUG:-0}" = "1" ] && echo "$(date -Iseconds) [nono-hook] $*" >> "$LOG_FILE"; }

# Only run inside a nono sandbox
if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    log "skipped: not in a nono sandbox (NONO_CAP_FILE not set or missing)"
    exit 0
fi
if ! command -v jq &> /dev/null; then
    log "skipped: jq not found"
    exit 0
fi

log "invoked"
INPUT=$(cat)

# Gate: only fire on actual sandbox denial signatures.
if ! echo "$INPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    log "skipped: no denial pattern in input"
    exit 0
fi

log "denial pattern detected"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTEXT_FILE="$SCRIPT_DIR/denial.txt"
if [ ! -f "$CONTEXT_FILE" ]; then
    log "context file not found: $CONTEXT_FILE"
    exit 0
fi

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

TEMPLATE=$(cat "$CONTEXT_FILE")
CONTEXT="${TEMPLATE//__CAPS__/$CAPS}"
CONTEXT="${CONTEXT//__NET__/$NET}"

log "injecting denial context"
jq -n --arg ctx "$CONTEXT" '{
  "additionalContext": $ctx
}'
