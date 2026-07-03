#!/bin/bash
# nono-hook-bash.sh — PostToolUse hook for Copilot CLI bash tool
# Version: 0.1.0
#
# Fires on PostToolUse for all tools. Filters to bash tool only, then
# inspects the tool result for sandbox-denial patterns. Reads context
# from ../context/denial.txt and injects it so the agent can guide the user.
#
# Input schema (VS Code compat):
#   { hook_event_name, tool_name, tool_input, tool_result: { result_type, text_result_for_llm } }
# Output schema: { hookSpecificOutput: { hookEventName, additionalContext } }
# NOTE: output schema needs verification against Copilot CLI hook runtime.
# See NOTES.md for details.
NONO_HOOK_DEBUG=0
LOG_FILE="${NONO_HOOK_LOG:-$HOME/.copilot/nono-hook.log}"
log() { [ "${NONO_HOOK_DEBUG:-0}" = "1" ] && echo "$(date -Iseconds) [nono-hook-bash] $*" >> "$LOG_FILE"; }

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

# Only fire for the bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [ "$TOOL_NAME" != "bash" ]; then
    log "skipped: tool is '$TOOL_NAME', not bash"
    exit 0
fi

# Extract output text — Copilot uses tool_result.text_result_for_llm
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result.text_result_for_llm // ""' 2>/dev/null)

# Gate: only fire on actual sandbox denial signatures
if ! echo "$OUTPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    log "skipped: no denial pattern in bash output"
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
