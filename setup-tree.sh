#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_ROOT="${LINEAGE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)/lineage}"

echo "Setting up source tree at $TREE_ROOT"

# --- Replace AOSP clang Go wrappers with symlinks to clang-real ---
# Required for ccache + icecc to work (Go wrapper breaks icecc distribution)
echo ""
echo "=== Fixing AOSP clang Go wrappers ==="
for dir in "$TREE_ROOT"/prebuilts/clang/host/linux-x86/clang-r*/bin; do
    [ -d "$dir" ] || continue
    if [ -f "$dir/clang" ] && file "$dir/clang" | grep -q "Go BuildID"; then
        echo "  $(basename "$(dirname "$dir")"): replacing Go wrapper -> clang-real"
        mv "$dir/clang" "$dir/clang.go-wrapper.bak"
        mv "$dir/clang++" "$dir/clang++.go-wrapper.bak"
        ln -s clang-real "$dir/clang"
        ln -s clang-real "$dir/clang++"
    fi
done

# --- Copy dev-defaults if present ---
# The dev-defaults directory is gitignored in the device tree but
# lives in lineage-patches (also gitignored there via .gitignore)
for device_dir in "$SCRIPT_DIR"/dev-defaults/*/; do
    [ -d "$device_dir" ] || continue
    codename="$(basename "$device_dir")"
    target="$TREE_ROOT/device"

    # Find the device tree path (e.g., device/oneplus/dre)
    device_path="$(find "$target" -maxdepth 2 -name "$codename" -type d | head -1)"
    if [ -n "$device_path" ] && [ -d "$device_path" ]; then
        echo "  Copying dev-defaults for $codename"
        cp -r "$device_dir" "$device_path/dev-defaults"
    fi
done

echo ""
echo "Done. Now run: ./apply.sh <device-codename>"
