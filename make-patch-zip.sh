#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_ROOT="${LINEAGE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)/lineage}"
OUT="$TREE_ROOT/out/target/product/${1:?Usage: $0 <device-codename> [output.zip]}"
OUTPUT="${2:-$SCRIPT_DIR/patch-$(date +%Y%m%d-%H%M).zip}"

if [ ! -d "$OUT" ]; then
    echo "ERROR: Build output not found at $OUT"
    echo "Run a build first: breakfast $1 && mka bacon"
    exit 1
fi

WORK="$(mktemp -d)"
trap "rm -rf $WORK" EXIT

mkdir -p "$WORK/META-INF/com/google/android"
mkdir -p "$WORK/patch-files"

# --- The update-binary is a shell script that recovery executes ---
cat > "$WORK/META-INF/com/google/android/update-binary" << 'UPDATER'
#!/sbin/sh
# Shell-based flashable zip installer for A/B devices
# Recovery passes: update-binary <api> <fd> <zip>
OUTFD="/proc/self/fd/$2"
ZIPFILE="$3"

ui_print() { echo "ui_print $1" > "$OUTFD"; echo "ui_print" > "$OUTFD"; }

ui_print "================================"
ui_print " LineageOS Patch Installer"
ui_print "================================"

# Detect slot
SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
[ -z "$SLOT" ] && SLOT="_a"
ui_print "Active slot: $SLOT"

TMPDIR=/tmp/patch-install
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

# Extract zip
ui_print "Extracting files..."
unzip -o "$ZIPFILE" -d "$TMPDIR" >/dev/null 2>&1

# Mount system partitions
for part in system system_ext vendor product; do
    BLOCK="/dev/block/mapper/${part}${SLOT}"
    MOUNT="/${part}"
    [ "$part" = "system" ] && MOUNT="/system_root"

    if [ -e "$BLOCK" ]; then
        # Try to mount read-write
        mount -o rw "$BLOCK" "$MOUNT" 2>/dev/null || \
        mount -o rw,remount "$MOUNT" 2>/dev/null || true
    fi
done

# Ensure /system points to /system_root/system
[ -d /system_root/system ] && mount --bind /system_root/system /system 2>/dev/null || true

# Install patch files
if [ -f "$TMPDIR/patch-files/file-list.txt" ]; then
    while IFS='|' read -r src dest; do
        [ -z "$src" ] && continue
        dir="$(dirname "$dest")"
        mkdir -p "$dir"
        cp -f "$TMPDIR/patch-files/$src" "$dest"
        # Restore standard permissions
        chmod 644 "$dest" 2>/dev/null
        chown 0:0 "$dest" 2>/dev/null
        ui_print "  -> $dest"
    done < "$TMPDIR/patch-files/file-list.txt"
fi

# Handle executables (need +x)
if [ -f "$TMPDIR/patch-files/exec-list.txt" ]; then
    while IFS='|' read -r src dest; do
        [ -z "$src" ] && continue
        dir="$(dirname "$dest")"
        mkdir -p "$dir"
        cp -f "$TMPDIR/patch-files/$src" "$dest"
        chmod 755 "$dest" 2>/dev/null
        chown 0:2000 "$dest" 2>/dev/null  # root:shell
        ui_print "  -> $dest (exec)"
    done < "$TMPDIR/patch-files/exec-list.txt"
fi

# Handle SELinux policy
if [ -d "$TMPDIR/patch-files/selinux-system" ]; then
    cp -rf "$TMPDIR/patch-files/selinux-system/"* /system/etc/selinux/ 2>/dev/null
    ui_print "  -> /system/etc/selinux/ (policy)"
fi
if [ -d "$TMPDIR/patch-files/selinux-vendor" ]; then
    cp -rf "$TMPDIR/patch-files/selinux-vendor/"* /vendor/etc/selinux/ 2>/dev/null
    ui_print "  -> /vendor/etc/selinux/ (policy)"
fi

# Cleanup
rm -rf "$TMPDIR"
sync

ui_print ""
ui_print "Patch installed successfully!"
ui_print "================================"
exit 0
UPDATER
chmod 755 "$WORK/META-INF/com/google/android/update-binary"

# Dummy updater-script (required by some recoveries)
echo '#this is a dummy' > "$WORK/META-INF/com/google/android/updater-script"

# --- Collect changed files from build output ---
echo "Collecting files from $OUT ..."

# File list format: relative-name-in-zip|absolute-path-on-device
> "$WORK/patch-files/file-list.txt"
> "$WORK/patch-files/exec-list.txt"

add_file() {
    local src="$1"    # path relative to OUT
    local dest="$2"   # absolute path on device
    local name="$(echo "$src" | tr '/' '_')"

    if [ ! -f "$OUT/$src" ]; then
        echo "WARN: $OUT/$src not found, skipping"
        return
    fi

    cp "$OUT/$src" "$WORK/patch-files/$name"
    echo "${name}|${dest}" >> "$WORK/patch-files/file-list.txt"
    echo "  + $dest"
}

add_exec() {
    local src="$1"
    local dest="$2"
    local name="$(echo "$src" | tr '/' '_')"

    if [ ! -f "$OUT/$src" ]; then
        echo "WARN: $OUT/$src not found, skipping"
        return
    fi

    cp "$OUT/$src" "$WORK/patch-files/$name"
    echo "${name}|${dest}" >> "$WORK/patch-files/exec-list.txt"
    echo "  + $dest (exec)"
}

add_selinux() {
    if [ -d "$OUT/system/etc/selinux" ]; then
        cp -r "$OUT/system/etc/selinux" "$WORK/patch-files/selinux-system"
        echo "  + system SELinux policy"
    fi
    if [ -d "$OUT/vendor/etc/selinux" ]; then
        cp -r "$OUT/vendor/etc/selinux" "$WORK/patch-files/selinux-vendor"
        echo "  + vendor SELinux policy"
    fi
}

# --- Define what to include ---
# Read the manifest file if it exists, otherwise include common targets
MANIFEST="$SCRIPT_DIR/patch-manifest.txt"
if [ -f "$MANIFEST" ]; then
    echo "Using manifest: $MANIFEST"
    while IFS='|' read -r type src dest; do
        [ -z "$type" ] || [ "${type:0:1}" = "#" ] && continue
        case "$type" in
            file) add_file "$src" "$dest" ;;
            exec) add_exec "$src" "$dest" ;;
            selinux) add_selinux ;;
        esac
    done < "$MANIFEST"
else
    echo "No manifest found. Include files by creating patch-manifest.txt"
    echo "Format: type|build-output-path|device-path"
    echo "Types: file, exec, selinux"
    echo ""
    echo "Example patch-manifest.txt:"
    echo "  exec|system/xbin/su|/system/xbin/su"
    echo "  file|system/priv-app/LineageParts/LineageParts.apk|/system/priv-app/LineageParts/LineageParts.apk"
    echo "  selinux||"
    exit 1
fi

# --- Build the zip ---
echo ""
echo "Creating zip: $OUTPUT"
cd "$WORK"
zip -r "$OUTPUT" . -x "*.DS_Store" >/dev/null
echo "Done: $(ls -lh "$OUTPUT" | awk '{print $5}') — $OUTPUT"
