#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_ROOT="${LINEAGE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)/lineage}"

usage() {
    echo "Usage: $0 <device-codename> [repo-path ...]"
    echo "       $0 --all"
    echo ""
    echo "Resets repos to their upstream state, removing applied patches."
    echo "If repo-paths are given, only those repos are reset."
    exit 1
}

reset_repo() {
    local repo_path="$1"
    local target="$TREE_ROOT/$repo_path"

    if [ ! -d "$target/.git" ]; then
        return
    fi

    local upstream
    upstream="$(git -C "$target" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || true

    if [ -z "$upstream" ]; then
        for try in origin/lineage-23.2 origin/lineage-22.1 origin/main origin/master; do
            if git -C "$target" rev-parse "$try" &>/dev/null; then
                upstream="$try"
                break
            fi
        done
    fi

    if [ -z "$upstream" ]; then
        echo "WARN: $repo_path — can't find upstream, skipping"
        return
    fi

    local count
    count="$(git -C "$target" rev-list --count "$upstream..HEAD" 2>/dev/null)" || count=0

    if [ "$count" -gt 0 ]; then
        echo "  $repo_path: resetting $count commit(s) to $upstream"
        git -C "$target" reset --hard "$upstream"
    fi
}

collect_repos_from_patches() {
    local device="$1"
    local repos=()

    for dir in "$SCRIPT_DIR/patches/common"/*/  "$SCRIPT_DIR/patches/device/$device"/; do
        [ -d "$dir" ] || continue
        for repo_dir in "$dir"*/; do
            [ -d "$repo_dir" ] || continue
            local repo_name
            repo_name="$(basename "$repo_dir")"
            repos+=("${repo_name//_//}")
        done
    done

    printf '%s\n' "${repos[@]}" | sort -u
}

if [ $# -lt 1 ]; then
    usage
fi

if [ "$1" = "--all" ]; then
    echo "Resetting ALL repos in $TREE_ROOT to upstream"
    echo "This will discard all local commits. Continue? [y/N]"
    read -r confirm
    [ "$confirm" = "y" ] || exit 0
    cd "$TREE_ROOT"
    repo forall -c 'git checkout . && git clean -fd' 2>/dev/null
    echo "Done."
    exit 0
fi

device="$1"
shift

if [ $# -gt 0 ]; then
    for repo_path in "$@"; do
        reset_repo "$repo_path"
    done
else
    echo "Resetting patched repos for device '$device'"
    while IFS= read -r repo_path; do
        [ -n "$repo_path" ] && reset_repo "$repo_path"
    done < <(collect_repos_from_patches "$device")
fi

echo "Done."
