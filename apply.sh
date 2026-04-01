#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_ROOT="${LINEAGE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)/lineage}"

usage() {
    echo "Usage: $0 <device-codename> [--dry-run]"
    echo "       $0 --common <feature-name> [--dry-run]"
    echo ""
    echo "Applies common patches + device-specific patches to the source tree."
    echo "Set LINEAGE_ROOT to override source tree location."
    exit 1
}

apply_patch_dir() {
    local patch_dir="$1"
    local dry_run="${2:-}"

    if [ ! -d "$patch_dir" ]; then
        return 0
    fi

    for repo_dir in "$patch_dir"/*/; do
        [ -d "$repo_dir" ] || continue
        local repo_name
        repo_name="$(basename "$repo_dir")"
        # Convert underscores back to slashes for repo path
        local repo_path="${repo_name//_//}"
        local target="$TREE_ROOT/$repo_path"

        if [ ! -d "$target/.git" ]; then
            echo "WARN: repo $repo_path not found at $target, skipping"
            continue
        fi

        local patches=("$repo_dir"*.patch)
        if [ ! -f "${patches[0]}" ]; then
            continue
        fi

        echo "  $repo_path: ${#patches[@]} patch(es)"
        if [ -z "$dry_run" ]; then
            git -C "$target" am --3way "${patches[@]}" || {
                echo "ERROR: Failed to apply patches to $repo_path"
                echo "  Resolve conflicts, then: git -C $target am --continue"
                echo "  Or abort: git -C $target am --abort"
                exit 1
            }
        fi
    done
}

if [ $# -lt 1 ]; then
    usage
fi

DRY_RUN=""
if [[ " $* " == *" --dry-run "* ]]; then
    DRY_RUN="yes"
    echo "(dry run — not applying)"
fi

if [ "$1" = "--common" ]; then
    feature="${2:?Missing feature name}"
    echo "Applying common/$feature patches to $TREE_ROOT"
    apply_patch_dir "$SCRIPT_DIR/patches/common/$feature" "$DRY_RUN"
else
    device="$1"
    echo "Applying patches for device '$device' to $TREE_ROOT"
    echo ""

    # Apply all common patches first
    if [ -d "$SCRIPT_DIR/patches/common" ]; then
        for feature_dir in "$SCRIPT_DIR/patches/common"/*/; do
            [ -d "$feature_dir" ] || continue
            local_feature="$(basename "$feature_dir")"
            echo "=== common/$local_feature ==="
            apply_patch_dir "$feature_dir" "$DRY_RUN"
        done
    fi

    # Then device-specific
    if [ -d "$SCRIPT_DIR/patches/device/$device" ]; then
        echo "=== device/$device ==="
        apply_patch_dir "$SCRIPT_DIR/patches/device/$device" "$DRY_RUN"
    else
        echo "No device-specific patches for '$device'"
    fi
fi

echo ""
echo "Done."
