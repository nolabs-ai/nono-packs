#!/bin/sh
# nono session before-hook for the kimchi pack.
#
# Captures the nono invocation that launched this session and exposes it
# to the sandboxed process via NONO_ENV_FILE. The nono-sandbox extension
# reads KIMCHI_NONO_COMMAND at session_start and parses --profile / tail
# from it in TypeScript, so this hook only needs to capture the raw
# command line.
#
# Runs on the HOST, outside the sandbox, with host privileges. Stays simple
# and side-effect-free apart from appending to NONO_ENV_FILE. Never aborts
# the session: on any error it exits 0 so nono proceeds to start.

set -u

# Nothing to write without an env file or a parent pid.
[ -n "${NONO_ENV_FILE:-}" ] || exit 0
[ -n "${PPID:-}" ] || exit 0

# Read the parent (nono) process command line.
# Linux /proc/<pid>/cmdline is NUL-separated; macOS/other fall back to ps.
cmd=""
if [ -r "/proc/${PPID}/cmdline" ]; then
	cmd=$(tr '\0' ' ' < "/proc/${PPID}/cmdline" 2>/dev/null || true)
else
	cmd=$(ps -o args= -p "${PPID}" 2>/dev/null || true)
fi
# Strip trailing whitespace left by the NUL-to-space conversion.
cmd=$(printf '%s' "$cmd" | sed 's/[[:space:]]*$//')

[ -n "$cmd" ] || exit 0

# Append the command line to NONO_ENV_FILE. The nono-sandbox extension
# parses --profile and the tail (after --) from this string in TypeScript.
# Best-effort: a failure here must not block the session.
printf 'KIMCHI_NONO_COMMAND=%s\n' "$cmd" >> "$NONO_ENV_FILE" 2>/dev/null || true

exit 0
