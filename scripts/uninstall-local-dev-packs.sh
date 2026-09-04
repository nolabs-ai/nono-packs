#!/usr/bin/env bash
# Remove every pack installed by scripts/install-pack-local.sh, including
# any files that pack's wiring wrote outside the nono package store
# (e.g. $HOME/.config/<tool>/skills/..., $NONO_CONFIG/profile-drafts markers).
#
# Safe to run repeatedly. Skips (and warns about) any wiring destination
# that is also owned by a real, registry-installed pack for the same tool,
# so this never deletes something the published pack needs.
#
# Usage:
#   scripts/uninstall-local-dev-packs.sh [namespace]
#
#   namespace  Local dev namespace to sweep (default: local). Pass
#              "always-further" to clean up packs installed before this
#              script switched to the "local" namespace.

set -euo pipefail

NAMESPACE="${1:-local}"

NONO_CONFIG="${NONO_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nono}"
PACKAGES_DIR="$NONO_CONFIG/packages"
LOCKFILE="$PACKAGES_DIR/lockfile.json"

if [[ ! -f "$LOCKFILE" ]]; then
    echo "No lockfile at $LOCKFILE — nothing to do."
    exit 0
fi

expand_dest() {
    local dest="$1"
    dest="${dest//\$HOME/$HOME}"
    dest="${dest//\$NONO_CONFIG/$NONO_CONFIG}"
    echo "$dest"
}

# Real (registry) package keys currently installed, e.g. "nolabs-ai/kilo"
REAL_KEYS=$(jq -r '.packages | keys[] | select(. != null)' "$LOCKFILE" | grep -vE "^($NAMESPACE|always-further)/" || true)

REMOVED_ANY=0

while IFS= read -r pack_key; do
    [[ -z "$pack_key" ]] && continue
    REMOVED_ANY=1

    dev_name="${pack_key#*/}"          # e.g. kilo-dev
    base_name="${dev_name%-dev}"       # e.g. kilo
    pack_dir="$PACKAGES_DIR/$pack_key"

    echo "Removing $pack_key"

    # A real pack for the same base tool is one whose store name matches
    # base_name exactly (namespace ignored) and isn't itself a dev pack.
    real_owner=""
    while IFS= read -r real_key; do
        [[ -z "$real_key" ]] && continue
        if [[ "${real_key#*/}" == "$base_name" ]]; then
            real_owner="$real_key"
            break
        fi
    done <<< "$REAL_KEYS"

    if [[ -f "$pack_dir/package.json" ]]; then
        while IFS= read -r wiring_entry; do
            [[ -z "$wiring_entry" ]] && continue
            dest=$(echo "$wiring_entry" | jq -r '.dest')
            dest=$(expand_dest "$dest")

            if [[ -n "$real_owner" ]]; then
                echo "  SKIP wiring dest (owned by real pack $real_owner): $dest"
                continue
            fi

            if [[ -e "$dest" ]]; then
                echo "  removing wired file: $dest"
                rm -f "$dest"
                # Clean up now-empty parent dirs this pack created, but never
                # touch shared roots like $HOME/.config or $NONO_CONFIG.
                parent=$(dirname "$dest")
                while [[ "$parent" != "$HOME" && "$parent" != "$NONO_CONFIG" && "$parent" != "/" && -d "$parent" ]]; do
                    rmdir "$parent" 2>/dev/null || break
                    parent=$(dirname "$parent")
                done
            fi
        done < <(jq -c '.wiring[]?' "$pack_dir/package.json" 2>/dev/null)
    fi

    rm -rf "$pack_dir"

    tmp=$(mktemp)
    jq --arg key "$pack_key" 'del(.packages[$key])' "$LOCKFILE" > "$tmp"
    mv "$tmp" "$LOCKFILE"

done < <(jq -r --arg ns "$NAMESPACE" '.packages | keys[] | select(startswith($ns + "/"))' "$LOCKFILE")

# Also remove the namespace dir itself if now empty
rmdir "$PACKAGES_DIR/$NAMESPACE" 2>/dev/null || true

if [[ "$REMOVED_ANY" -eq 0 ]]; then
    echo "No packs found under namespace '$NAMESPACE'."
else
    echo "Done."
fi
