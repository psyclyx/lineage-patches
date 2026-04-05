#!/bin/bash
# Install encabulator into the arch chroot on device.
# Run from this directory with the device connected via adb (as root).
set -e

CHROOT="/data/arch"
DEST="$CHROOT/opt/encabulator"
DESKTOP_DIR="$CHROOT/usr/share/applications"

adb shell "mkdir -p $DEST $DESKTOP_DIR"
adb push retroencabulator.py "$DEST/retroencabulator.py"
for f in *.desktop; do
    adb push "$f" "$DESKTOP_DIR/$f"
done

echo "Installed encabulator to $DEST"
