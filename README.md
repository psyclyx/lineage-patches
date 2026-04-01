# lineage-patches

Patch management for multi-device LineageOS builds.

## Structure

```
patches/
├── common/                    # Applied to ALL device builds
│   ├── surfaceflinger-wayland/
│   └── nix-on-droid/
└── device/                    # Per-device patches
    ├── dre/                   # OnePlus Nord N200
    ├── cuttlefish/            # Emulator
    └── <codename>/
```

Each patch directory contains subdirectories named after the repo path
(with `/` replaced by `_`), containing `git format-patch` output:

```
patches/device/dre/
├── kernel_oneplus_sm4350/
│   ├── 0001-touch-Copy-msm_drm.dsi_display0-to-tp_dsi_display.patch
│   └── 0002-oplus_project-Fallback-to-cmdline-prj_version.patch
└── device_oneplus_dre/
    └── 0001-dev-defaults-skip-wizard-enable-adb.patch
```

## Usage

```bash
# Apply all patches for a device (includes common + device-specific)
./apply.sh dre

# Generate patches from current tree (captures uncommitted work too)
./generate.sh dre

# Unapply patches (reset repos to upstream)
./unapply.sh dre

# List what's modified
./status.sh
```

## Adding a new device

1. Create `patches/device/<codename>/`
2. Make your changes in the source tree
3. Run `./generate.sh <codename>` to capture them
4. Commit to this repo

## Adding a cross-device feature

1. Create `patches/common/<feature-name>/`
2. Make changes in the source tree
3. Run `./generate.sh --common <feature-name>` to capture them
