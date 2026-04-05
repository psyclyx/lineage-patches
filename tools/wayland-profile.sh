# /etc/profile.d/wayland.sh — Wayland environment for Linux apps on Android
# Installed by setup-arch-chroot.sh into the chroot's /etc/profile.d/

export XDG_RUNTIME_DIR=/run/wayland
export WAYLAND_DISPLAY=wayland-0
export GDK_BACKEND=wayland
export LANG=C.UTF-8
