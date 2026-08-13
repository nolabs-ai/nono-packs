#!/usr/bin/env bash
# Smoke test a single nono pack.
#
# The pack must already be present in the nono package store — use
# scripts/install-pack-local.sh to inject it before running this.
#
# Usage:
#   NONO_BIN=./nono scripts/smoke-test-pack.sh <namespace/pack>
#
# Optional env:
#   NONO_BIN          Path to nono binary (default: nono)
#   NONO_SKIP_SANDBOX Set to 1 to skip sandboxed execution tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

PACK="${1:-}"
if [[ -z "$PACK" ]]; then
    echo "Usage: $0 <namespace/pack>" >&2
    exit 1
fi

echo "Smoke test: $PACK"

verify_nono_binary

TMPDIR=$(setup_test_dir)
trap 'cleanup_test_dir "$TMPDIR"' EXIT

export NONO_NO_UPDATE_CHECK=1
export NONO_NO_MIGRATE=1
export NONO_NO_SAVE_PROMPT=1

echo "list"

name="${PACK#*/}"
expect_output_contains "nono list shows $PACK" "$name" \
    "$NONO_BIN" list --installed

echo "profile resolution"

expect_success "profile validate $PACK" \
    "$NONO_BIN" profile validate "$PACK"

expect_success "profile show $PACK" \
    "$NONO_BIN" profile show "$PACK"

expect_output_contains "profile show $PACK lists filesystem" "Filesystem:" \
    "$NONO_BIN" profile show "$PACK"

expect_success "profile diff $PACK default" \
    "$NONO_BIN" profile diff "$PACK" default

echo "dry-run execution"

mkdir -p "$TMPDIR/workdir"

expect_success "dry-run under $PACK succeeds" \
    "$NONO_BIN" run --profile "$PACK" --workdir "$TMPDIR/workdir" --dry-run -- echo "smoke"

expect_output_contains "dry-run under $PACK shows Capabilities" "Capabilities:" \
    "$NONO_BIN" run --profile "$PACK" --workdir "$TMPDIR/workdir" --dry-run -- echo "smoke"

echo "sandboxed execution"

if require_working_sandbox "sandboxed execution"; then
    NONO_BIN_ABS="$(cd "$(dirname "$NONO_BIN")" && pwd)/$(basename "$NONO_BIN")"
    expect_success "sandboxed echo under $PACK exits 0" \
        bash -lc "cd \"$TMPDIR/workdir\" && \"$NONO_BIN_ABS\" run --profile \"$PACK\" --allow-cwd --no-audit -- echo smoke"
fi

if [[ "$name" == "opencode" ]]; then
    echo "AWS credential route handling (opencode only)"

    expect_output_contains "profile show $PACK lists a bedrock credential route" "bedrock_" \
        "$NONO_BIN" profile show "$PACK"

    if require_working_sandbox "AWS credential phantom substitution"; then
        NONO_BIN_ABS="$(cd "$(dirname "$NONO_BIN")" && pwd)/$(basename "$NONO_BIN")"

        # Sentinel values deliberately avoid AWS's real credential-value shapes (e.g. the
        # "AKIA" access-key-ID prefix) so they can never be mistaken for a genuine leaked
        # secret by GitHub's or any other secret scanner watching this repo's CI output.
        # Capture ONE sandboxed `env` execution and assert everything against that single
        # output — running one assertion per `nono run` invocation let a crashed/partial
        # run silently skip coverage for whichever assertion didn't happen to run last.
        sandboxed_aws_env() {
            AWS_ACCESS_KEY_ID="NONO-SMOKE-TEST-LEAK-SENTINEL-ACCESS-KEY-ID" \
            AWS_SECRET_ACCESS_KEY="NONO-SMOKE-TEST-LEAK-SENTINEL-SECRET-KEY" \
            AWS_ACCESS_KEY="NONO-SMOKE-TEST-LEAK-SENTINEL-LEGACY-ACCESS-KEY" \
            AWS_SECRET_KEY="NONO-SMOKE-TEST-LEAK-SENTINEL-LEGACY-SECRET-KEY" \
            AWS_SECURITY_TOKEN="NONO-SMOKE-TEST-LEAK-SENTINEL-SECURITY-TOKEN" \
            AWS_CREDENTIAL_FILE="/tmp/nono-smoke-test-leak-sentinel-credential-file" \
            bash -lc "cd \"$TMPDIR/workdir\" && \"$NONO_BIN_ABS\" run --profile \"$PACK\" --allow-cwd --no-audit -- env && echo NONO-SMOKE-TEST-ENV-DUMP-COMPLETE"
        }

        # The `|| SANDBOXED_ENV_RC=$?` form (rather than a bare `$?` on the next line) is
        # required under `set -e`: without it, a nonzero exit from the command substitution
        # aborts the whole script right here instead of letting us record and assert on it.
        SANDBOXED_ENV_RC=0
        SANDBOXED_ENV_OUTPUT="$(sandboxed_aws_env 2>&1)" || SANDBOXED_ENV_RC=$?

        if [[ $SANDBOXED_ENV_RC -ne 0 ]] || ! grep -qF -- "NONO-SMOKE-TEST-ENV-DUMP-COMPLETE" <<< "$SANDBOXED_ENV_OUTPUT"; then
            _fail "sandboxed env dump under $PACK completed successfully" \
                "command exited $SANDBOXED_ENV_RC or completion marker missing — $(echo "$SANDBOXED_ENV_OUTPUT" | head -3)"
        else
            _pass "sandboxed env dump under $PACK completed successfully"

            for leaked_value in \
                "NONO-SMOKE-TEST-LEAK-SENTINEL-ACCESS-KEY-ID" \
                "NONO-SMOKE-TEST-LEAK-SENTINEL-SECRET-KEY" \
                "NONO-SMOKE-TEST-LEAK-SENTINEL-LEGACY-ACCESS-KEY" \
                "NONO-SMOKE-TEST-LEAK-SENTINEL-LEGACY-SECRET-KEY" \
                "NONO-SMOKE-TEST-LEAK-SENTINEL-SECURITY-TOKEN" \
                "/tmp/nono-smoke-test-leak-sentinel-credential-file"
            do
                if grep -qF -- "$leaked_value" <<< "$SANDBOXED_ENV_OUTPUT"; then
                    _fail "sandboxed process under $PACK never sees real value '$leaked_value'" \
                        "pattern unexpectedly found in output"
                else
                    _pass "sandboxed process under $PACK never sees real value '$leaked_value'"
                fi
            done

            if grep -qF -- "AWS_ACCESS_KEY_ID=nono-phantom-access-key" <<< "$SANDBOXED_ENV_OUTPUT"; then
                _pass "sandboxed process under $PACK sees the phantom AWS_ACCESS_KEY_ID instead"
            else
                _fail "sandboxed process under $PACK sees the phantom AWS_ACCESS_KEY_ID instead" \
                    "phantom value not found in output"
            fi
        fi
    fi
fi

print_summary
