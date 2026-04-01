#!/usr/bin/env bash
set -euo pipefail

TREE_ROOT="${LINEAGE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lineage}"

echo "Scanning $TREE_ROOT for modified repos..."
echo ""

found=0
while IFS= read -r repo_path; do
    target="$TREE_ROOT/$repo_path"
    [ -d "$target/.git" ] || continue

    upstream="$(git -C "$target" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || true
    if [ -z "$upstream" ]; then
        for try in origin/lineage-23.2 origin/lineage-22.1 origin/main origin/master; do
            if git -C "$target" rev-parse "$try" &>/dev/null; then
                upstream="$try"
                break
            fi
        done
    fi
    [ -n "$upstream" ] || continue

    commits="$(git -C "$target" rev-list --count "$upstream..HEAD" 2>/dev/null)" || commits=0
    dirty=""
    git -C "$target" diff --quiet 2>/dev/null || dirty=" [dirty]"
    git -C "$target" diff --cached --quiet 2>/dev/null || dirty="$dirty [staged]"

    if [ "$commits" -gt 0 ] || [ -n "$dirty" ]; then
        echo "  $repo_path: $commits commit(s) ahead of $upstream$dirty"
        if [ "$commits" -gt 0 ]; then
            git -C "$target" log --oneline "$upstream..HEAD" | sed 's/^/    /'
        fi
        found=$((found + 1))
    fi
done < <(cd "$TREE_ROOT" && repo list -p 2>/dev/null || find . -name ".git" -maxdepth 4 -type d | sed 's|/\.git$||; s|^\./||' | sort)

if [ "$found" -eq 0 ]; then
    echo "  (no modified repos)"
fi
