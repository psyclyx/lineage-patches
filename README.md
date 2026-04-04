# lineage-patches

Custom LineageOS build for OnePlus Nord N200 (dre) with embedded Wayland compositor.

Based on lineage-23.2 (Android 16). Changes are maintained as branches on
GitHub forks, pulled in via `local_manifest.xml`.

## Setup

```bash
# After repo init for lineage-23.2:
cp local_manifest.xml .repo/local_manifests/
repo sync
```

## Forked repos

| Repo | Branch | Changes |
|------|--------|---------|
| `frameworks/native` | `wayland-compositor` | Embedded Wayland compositor in SurfaceFlinger (wl_shm, linux-dmabuf, xdg-shell, wl_seat, wl_drm); zero-copy dmabuf import with QTI gralloc; GPU fence sync via DMA_BUF_IOCTL_EXPORT_SYNC_FILE |
| `external/wayland` | `wayland-compositor` | libwayland built for Android (server + client) |
| `system/sepolicy` | `su-whitelist+wayland-compositor` | SELinux policies for su whitelist + WaylandHost binder service |
| `vendor/lineage` | `su-whitelist` | Root access via UID whitelist (no Superuser app) |
| `system/extras` | `su-whitelist` | su daemon whitelist support |
| `packages/apps/Settings` | `su-whitelist` | Root access settings UI |
| `kernel/oneplus/sm4350` | `dre` | Touch display fix; DMA_BUF_IOCTL_EXPORT/IMPORT_SYNC_FILE backport from kernel 5.17 |
| `device/oneplus/dre` | `dre` | Dev defaults; VINTF kernel requirements workaround |
| `device/qcom/sepolicy` | `dre` | Disable dumpstate→vold binder_call (neverallow conflict) |
| `device/qcom/sepolicy_vndr` | `dre` | Remove typec genfscon entries (platform compat conflict) |

## Supplementary files

- `tools/device.sh` — adb automation helpers (screenshot, tap, push-sf, etc.)
- `tools/setup-arch-chroot.sh` — Arch Linux ARM chroot setup for GTK4/Wayland apps
- `packages/arch/` — Arch package build scripts (Mesa Turnip KGSL Vulkan driver)
- `wayland-host/` — WaylandHost Android app (Activity bridge, app launcher)
- `dev-defaults/` — Device-specific dev config (gitignored, contains credentials)

## Build

```bash
cd /path/to/lineage
nix-shell --run "lineage-env -c 'source build/envsetup.sh && lunch lineage_dre-trunk_staging-userdebug && mka bacon'"
```
