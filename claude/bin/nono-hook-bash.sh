#!/usr/bin/env bash
# nono-hook-bash.sh - PostToolUse hook for Bash commands
# Version: 1.2.0
#
# Inspects a Bash tool result for sandbox-denial patterns and injects
# context so Claude can guide the user.
#
# 1.2.0: A refused sandbox re-initialization (sandbox_apply / sandbox_init
# with EPERM, forbidden-sandbox-reinit) names no path, so it gets its own
# context instead of the path-grant steps. The generic context no longer
# asserts nono as the cause and requires a concrete path before `nono why`
# or a grant is offered (nolabs-ai/nono#1646).
# 1.1.0: Option B now points at ~/.config/nono/profile-drafts/ + promote
# CLI, since profiles/ is no longer writable from inside the sandbox.

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null)

if ! echo "$OUTPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    exit 0
fi

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

# A refused sandbox re-initialization is a different failure from a denied
# path: macOS Seatbelt rejects sandbox_init() inside an already-sandboxed
# process. No path grant, profile draft, or `nono why --path` query changes
# it, so the path-grant steps must not run for it. The pattern is
# order-independent, like the CLI classifier in
# crates/nono-cli/src/diagnostic/formatter.rs (`looks_like_sandbox_reinit`).
if echo "$OUTPUT" | grep -qiE '(sandbox_apply|sandbox_init).*(operation not permitted|EPERM)|(operation not permitted|EPERM).*(sandbox_apply|sandbox_init)|forbidden-sandbox-reinit'; then
    CONTEXT="[NONO SANDBOX - NESTED SANDBOX REFUSED]

The command tried to start its own sandbox (sandbox-exec / sandbox_init) inside nono's sandbox. macOS refuses sandbox re-initialization from an already-sandboxed process (forbidden-sandbox-reinit). This is not a denied path.

Allowed paths (for reference only; none of them is the cause):
$CAPS
Network: $NET

Do NOT run \`nono why --path\` for this failure: there is no blocked path to query. Do NOT offer \`nono run --allow\`, a profile draft, chmod, sudo, or System Settings: none of them changes this outcome.

Tell the user what does change it:
  - Run the tool with its built-in sandbox disabled, so nono stays the enforcement boundary (Codex: \`nono run --profile <name> -- codex --sandbox danger-full-access --ask-for-approval on-request\`).
  - If the failing command was itself \`nono run\`, drop the inner nono: the outer sandbox already applies.

Include the failing line verbatim in your reply."
else
    CONTEXT="[NONO SANDBOX - PERMISSION DENIAL SIGNATURE]

The command output matched a permission-denial signature (EPERM, EACCES, \"Operation not permitted\", \"Permission denied\"). That signature alone does not identify the cause: it may be the nono sandbox boundary, or something nono did not decide. Do not assert nono as the cause until \`nono why\` confirms it.

Allowed paths:
$CAPS
Network: $NET

DO NOT ask the user for permission. Take these steps in order, every time:

1. If the failing output names a concrete path, run \`nono why --self --path <that-path> --op <read|write|readwrite>\` immediately and include its output verbatim in your reply. A result with status DENIED confirms the nono boundary, even when the reason is path_not_granted.
2. If no concrete path is named, or \`nono why\` does not report DENIED, reply exactly: \`Nono sandbox unconfirmed; this permission failure needs a non-sandbox diagnosis.\` Do not invent a path, and do not offer the options below.
3. Only for a confirmed DENIED path, present the user with these two options as their NEXT decision point:

   Option A (quick fix): exit and restart with the path allowed:
     nono run --allow /path/to/needed -- claude

   Option B (persistent fix): draft a nono profile. The profiles/ directory is read-only from inside the sandbox; drafts go to profile-drafts/. Run \`nono profile guide\` for the schema (also without asking). If updating an existing user profile, read ~/.config/nono/profiles/<name>.json, compute the SHA-256 of those exact bytes, write the full proposed profile to ~/.config/nono/profile-drafts/<name>.json, and write the hash to ~/.config/nono/profile-drafts/<name>.base. If ~/.config/nono/profile-drafts does not exist or cannot be written, or \`nono profile promote --help\` is unavailable, do not try to modify profiles directly; tell the user to upgrade nono, then rerun the draft flow. If the current profile is pack-provided or built-in, draft <active>-local extending <active> instead of replacing it. Tell the user:
     Drafted <name>. Run \`nono profile promote <name>\` to review and apply, then start sessions with \`nono run --profile <name> -- claude\`.

Step 1 is non-optional whenever a path is named and must run before you reply. Do not ask whether to run it."
fi

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
