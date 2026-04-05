#!/system/bin/sh
# Setup Arch Linux ARM chroot on Android for running Wayland GTK apps.
# Run as root on the device.

set -e

CHROOT_DIR="/data/arch"
ROOTFS_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
ROOTFS_TAR="/data/local/tmp/archlinux-arm.tar.gz"

echo "=== Arch Linux ARM chroot setup ==="

# Step 1: Download rootfs if not present
if [ ! -f "$ROOTFS_TAR" ]; then
    echo "Downloading Arch Linux ARM rootfs..."
    # Use curl or wget - Android typically has curl via toybox
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$ROOTFS_TAR" "$ROOTFS_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$ROOTFS_TAR" "$ROOTFS_URL"
    else
        echo "ERROR: No curl or wget available. Download manually:"
        echo "  $ROOTFS_URL -> $ROOTFS_TAR"
        exit 1
    fi
fi

# Step 2: Extract rootfs
if [ ! -d "$CHROOT_DIR/usr" ]; then
    echo "Extracting rootfs to $CHROOT_DIR..."
    mkdir -p "$CHROOT_DIR"
    tar xzf "$ROOTFS_TAR" -C "$CHROOT_DIR" 2>/dev/null || \
        busybox tar xzf "$ROOTFS_TAR" -C "$CHROOT_DIR"
    echo "Rootfs extracted."
else
    echo "Rootfs already present at $CHROOT_DIR"
fi

# Step 3: Setup DNS
echo "nameserver 8.8.8.8" > "$CHROOT_DIR/etc/resolv.conf"

# Step 4: Create mount script
cat > "$CHROOT_DIR/../arch-mount.sh" << 'MOUNT_EOF'
#!/system/bin/sh
CHROOT_DIR="/data/arch"

mount_if_needed() {
    mountpoint -q "$2" 2>/dev/null || mount "$@"
}

mount_if_needed -t proc proc "$CHROOT_DIR/proc"
mount_if_needed -t sysfs sysfs "$CHROOT_DIR/sys"
mount_if_needed -o bind /dev "$CHROOT_DIR/dev"
mount_if_needed -o bind /dev/pts "$CHROOT_DIR/dev/pts"
mount_if_needed -t tmpfs tmpfs "$CHROOT_DIR/tmp"

# Bind-mount Wayland socket directory
mkdir -p "$CHROOT_DIR/run/wayland"
mount_if_needed -o bind /data/wayland "$CHROOT_DIR/run/wayland"

echo "Mounts ready."
MOUNT_EOF
chmod +x "$CHROOT_DIR/../arch-mount.sh"

# Step 5: Install Wayland profile into chroot
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/wayland-profile.sh" "$CHROOT_DIR/etc/profile.d/wayland.sh"
chmod 644 "$CHROOT_DIR/etc/profile.d/wayland.sh"

# Step 6: Create enter script
cat > "$CHROOT_DIR/../arch-enter.sh" << 'ENTER_EOF'
#!/system/bin/sh
CHROOT_DIR="/data/arch"

# Mount if needed
sh /data/arch-mount.sh

# Enter chroot — env vars come from /etc/profile.d/wayland.sh via login shell
chroot "$CHROOT_DIR" /bin/env \
    HOME=/root \
    TERM=linux \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash -l
ENTER_EOF
chmod +x "$CHROOT_DIR/../arch-enter.sh"

# Step 7: Create first-boot setup script (run inside chroot)
cat > "$CHROOT_DIR/root/first-setup.sh" << 'SETUP_EOF'
#!/bin/bash
# Run this inside the chroot after first entering it.
set -e

echo "=== Arch Linux ARM first-time setup ==="

# Initialize pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Update system
pacman -Syu --noconfirm

# Install essential packages for Wayland + GTK
pacman -S --noconfirm --needed \
    gtk4 \
    mesa \
    vulkan-freedreno \
    wayland \
    xkeyboard-config \
    libxkbcommon \
    fontconfig \
    ttf-dejavu \
    dbus

echo "=== Setup complete! ==="
echo "Test with: gtk4-demo"
SETUP_EOF
chmod +x "$CHROOT_DIR/root/first-setup.sh"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Usage:"
echo "  1. Mount filesystems:  sh /data/arch-mount.sh"
echo "  2. Enter chroot:       sh /data/arch-enter.sh"
echo "  3. First time only:    /root/first-setup.sh"
echo "  4. Run GTK app:        gtk4-demo"
echo ""
echo "The Wayland socket is at /run/wayland/wayland-0 inside the chroot."
