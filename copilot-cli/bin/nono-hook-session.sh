#!/bin/bash
# nono-hook-session.sh — GitHub Copilot CLI SessionStart hook
# Version: 0.1.0
#
# Brief boundary statement at session start. Reads context from
# ../context/session.txt and injects it into the session.
#
# Input schema (VS Code compat): { hook_event_name, session_id, timestamp, cwd, source }
# Output schema: { hookSpecificOutput: { hookEventName, additionalContext } }
# NOTE: output schema needs verification against Copilot CLI hook runtime.
# See NOTES.md for details.
NONO_HOOK_DEBUG=-
LOG_FILE="${NONO_HOOK_LOG:-$HOME/.copilot/nono-hook.log}"
log() { [ "${NONO_HOOK_DEBUG:-0}" = "1" ] && echo "$(date -Iseconds) [nono-hook-session] $*" >> "$LOG_FILE"; }

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    log "skipped: not in a nono sandbox (NONO_CAP_FILE not set or missing)"
    exit 0
fi
if ! command -v jq &> /dev/null; then
    log "skipped: jq not found"
    exit 0
fi

log "invoked"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTEXT_FILE="$SCRIPT_DIR/session.txt"
if [ ! -f "$CONTEXT_FILE" ]; then
    log "context file not found: $CONTEXT_FILE"
    exit 0
fi

CONTEXT=$(cat "$CONTEXT_FILE")

log "injecting session context"
jq -n --arg ctx "$CONTEXT" '{
  "additionalContext": $ctx
}'
