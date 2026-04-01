#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_ROOT="${LINEAGE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)/lineage}"

usage() {
    echo "Usage: $0 <device-codename> [repo-path ...]"
    echo "       $0 --common <feature-name> [repo-path ...]"
    echo ""
    echo "Generates patches from commits on top of upstream in each repo."
    echo "If repo-paths are given, only those repos are processed."
    echo "Otherwise, scans all repos for local commits."
    echo ""
    echo "Each repo's patches are stored as git format-patch output."
    echo "The upstream tracking branch is determined automatically."
    exit 1
}

repo_to_dirname() {
    echo "${1//\//_}"
}

generate_patches_for_repo() {
    local repo_path="$1"
    local output_dir="$2"
    local target="$TREE_ROOT/$repo_path"

    if [ ! -d "$target/.git" ]; then
        echo "WARN: $repo_path not found"
        return
    fi

    # Find upstream: the branch the repo was synced to
    local upstream
    upstream="$(git -C "$target" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || true

    if [ -z "$upstream" ]; then
        # Try common remote tracking branches
        for try in origin/lineage-23.2 origin/lineage-22.1 origin/main origin/master; do
            if git -C "$target" rev-parse "$try" &>/dev/null; then
                upstream="$try"
                break
            fi
        done
    fi

    if [ -z "$upstream" ]; then
        echo "WARN: $repo_path — can't find upstream branch, skipping"
        return
    fi

    # Check for local commits
    local count
    count="$(git -C "$target" rev-list --count "$upstream..HEAD" 2>/dev/null)" || count=0

    if [ "$count" -eq 0 ]; then
        # Also check for uncommitted changes
        if git -C "$target" diff --quiet && git -C "$target" diff --cached --quiet; then
            return  # Nothing to capture
        fi
        echo "  $repo_path: uncommitted changes (commit first to generate patches)"
        return
    fi

    local dirname
    dirname="$(repo_to_dirname "$repo_path")"
    local patch_out="$output_dir/$dirname"

    rm -rf "$patch_out"
    mkdir -p "$patch_out"

    git -C "$target" format-patch -o "$patch_out" "$upstream..HEAD" --quiet
    echo "  $repo_path: $count patch(es) -> $dirname/"
}

if [ $# -lt 1 ]; then
    usage
fi

if [ "$1" = "--common" ]; then
    feature="${2:?Missing feature name}"
    shift 2
    output_dir="$SCRIPT_DIR/patches/common/$feature"
    echo "Generating common/$feature patches from $TREE_ROOT"
else
    device="$1"
    shift
    output_dir="$SCRIPT_DIR/patches/device/$device"
    echo "Generating device/$device patches from $TREE_ROOT"
fi

mkdir -p "$output_dir"

if [ $# -gt 0 ]; then
    # Specific repos
    for repo_path in "$@"; do
        generate_patches_for_repo "$repo_path" "$output_dir"
    done
else
    # Scan all repos for local commits
    echo "Scanning for modified repos..."
    while IFS= read -r repo_path; do
        generate_patches_for_repo "$repo_path" "$output_dir"
    done < <(cd "$TREE_ROOT" && repo list -p 2>/dev/null || find . -name ".git" -maxdepth 4 -type d | sed 's|/\.git$||; s|^\./||' | sort)
fi

echo ""
echo "Done. Patches in: $output_dir"
