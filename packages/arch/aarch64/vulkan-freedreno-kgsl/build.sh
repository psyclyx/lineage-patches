#!/usr/bin/env bash
set -euo pipefail

MESA_VERSION="26.0.3"
MESA_TARBALL="mesa-${MESA_VERSION}.tar.xz"
MESA_URL="https://archive.mesa3d.org/${MESA_TARBALL}"
BUILD_DIR="build-aarch64"
SRC_DIR="mesa-${MESA_VERSION}"

cd "$(dirname "$0")"

# Download source if needed
if [ ! -f "$MESA_TARBALL" ]; then
  echo "==> Downloading Mesa ${MESA_VERSION}..."
  curl -LO "$MESA_URL"
fi

# Extract if needed
if [ ! -d "$SRC_DIR" ]; then
  echo "==> Extracting..."
  tar xf "$MESA_TARBALL"
fi

# Build a cross-only pkg-config wrapper that searches aarch64 paths.
CROSS_PKGCONFIG="$(pwd)/cross-pkg-config"
CROSS_PKG_CONFIG_PATH="${PKG_CONFIG_PATH_aarch64_unknown_linux_gnu:-}"

# If the nix cross env didn't set the paths, fall back to scanning PKG_CONFIG_PATH
if [[ -z "$CROSS_PKG_CONFIG_PATH" ]]; then
  for p in ${PKG_CONFIG_PATH:-}; do
    if [[ "$p" == *aarch64* ]] || [[ "$p" == *xorgproto* ]] || [[ "$p" == *wayland-protocols* ]]; then
      CROSS_PKG_CONFIG_PATH="${CROSS_PKG_CONFIG_PATH:+${CROSS_PKG_CONFIG_PATH}:}$p"
    fi
  done
fi

# Find the real (unwrapped) pkg-config binary by looking at the cross wrapper
CROSS_PKG_CONFIG_BIN="$(which ${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}pkg-config 2>/dev/null || true)"
REAL_PKG_CONFIG="$(which pkg-config 2>/dev/null || true)"
if [[ -z "$REAL_PKG_CONFIG" && -n "$CROSS_PKG_CONFIG_BIN" ]]; then
  # Extract the underlying pkg-config path from the wrapper script
  REAL_PKG_CONFIG="$(grep -oP '/nix/store/[^ ]*pkg-config-[0-9][^/]*/bin/pkg-config' "$CROSS_PKG_CONFIG_BIN" 2>/dev/null | head -1)"
fi
if [[ -z "$REAL_PKG_CONFIG" ]]; then
  echo "ERROR: Cannot find pkg-config binary" >&2
  exit 1
fi
echo "==> Using pkg-config: $REAL_PKG_CONFIG"

cat > "$CROSS_PKGCONFIG" <<WRAPPER
#!/bin/sh
export PKG_CONFIG_PATH="$CROSS_PKG_CONFIG_PATH"
exec "$REAL_PKG_CONFIG" "\$@"
WRAPPER
chmod +x "$CROSS_PKGCONFIG"

echo "==> Cross pkg-config paths:"
echo "$CROSS_PKG_CONFIG_PATH" | tr ':' '\n' | head -20

# Generate meson cross file.
# If nix provides a cross-file via $mesonFlags, augment it with pkgconfig.
# Otherwise generate a standalone one.
CROSS_FILE="meson-cross-aarch64.ini"
NIX_CROSS_FILE=""
if [[ "${mesonFlags:-}" == *cross-file=* ]]; then
  NIX_CROSS_FILE="${mesonFlags#*cross-file=}"
fi

if [[ -n "$NIX_CROSS_FILE" && -f "$NIX_CROSS_FILE" ]]; then
  # Augment nix cross-file with pkgconfig binary
  cp "$NIX_CROSS_FILE" "$CROSS_FILE"
  CROSS_CC="$(which ${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}gcc 2>/dev/null || true)"
  CROSS_CXX="$(which ${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}g++ 2>/dev/null || true)"
  CROSS_AR="$(which ${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}ar 2>/dev/null || true)"
  CROSS_STRIP="$(which ${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}strip 2>/dev/null || true)"
  CROSS_PKG="$CROSS_PKGCONFIG"  # always use our wrapper with hardcoded paths
  # Append compilers and pkgconfig to [binaries] section
  cat >> "$CROSS_FILE" <<EOF
c = '${CROSS_CC}'
cpp = '${CROSS_CXX}'
ar = '${CROSS_AR}'
strip = '${CROSS_STRIP}'
pkgconfig = '${CROSS_PKG}'
EOF
else
  cat > "$CROSS_FILE" <<EOF
[binaries]
c = '${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}gcc'
cpp = '${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}g++'
ar = '${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}ar'
strip = '${CROSS_PREFIX:-aarch64-unknown-linux-gnu-}strip'
pkgconfig = '${CROSS_PKGCONFIG}'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
fi

echo "==> Cross file: $CROSS_FILE"
echo "==> Configuring Mesa (Turnip + KGSL only)..."

meson setup "$SRC_DIR" "$BUILD_DIR" \
  --cross-file "$CROSS_FILE" \
  --prefix=/usr \
  --buildtype=release \
  -D platforms=x11,wayland \
  -D gallium-drivers= \
  -D vulkan-drivers=freedreno \
  -D freedreno-kmds=kgsl,msm \
  -D gles1=disabled \
  -D gles2=disabled \
  -D opengl=false \
  -D gbm=disabled \
  -D glx=disabled \
  -D egl=disabled \
  -D glvnd=disabled \
  -D llvm=disabled \
  -D microsoft-clc=disabled \
  -D valgrind=disabled \
  -D b_ndebug=true

# Workaround: meson may resolve SPIRV-Tools from native glslang (x86_64)
# instead of cross glslang (aarch64) when both are in PKG_CONFIG_PATH.
# Patch build.ninja to use the cross glslang libs.
NATIVE_GLSLANG_LIB=$(grep -oP '/nix/store/[^/]+-glslang-[0-9.]+/lib' "$BUILD_DIR/build.ninja" | grep -v aarch64 | head -1)
CROSS_GLSLANG_LIB=$(grep -oP '/nix/store/[^/]+-glslang-aarch64[^/]*/lib' "$BUILD_DIR/build.ninja" | head -1)
if [ -n "$NATIVE_GLSLANG_LIB" ] && [ -n "$CROSS_GLSLANG_LIB" ]; then
  echo "==> Patching build.ninja: $NATIVE_GLSLANG_LIB -> $CROSS_GLSLANG_LIB"
  sed -i "s|$NATIVE_GLSLANG_LIB|$CROSS_GLSLANG_LIB|g" "$BUILD_DIR/build.ninja"
fi

echo "==> Building..."
ninja -C "$BUILD_DIR" -j"$(nproc)"

echo "==> Build complete!"
SO_PATH="$BUILD_DIR/src/freedreno/vulkan/libvulkan_freedreno.so"
ICD_PATH="$BUILD_DIR/src/freedreno/vulkan/freedreno_icd.aarch64.json"

if [ -f "$SO_PATH" ]; then
  echo "Output:"
  echo "  $SO_PATH ($(du -h "$SO_PATH" | cut -f1))"
  echo "  $ICD_PATH"
  file "$SO_PATH"
else
  echo "ERROR: libvulkan_freedreno.so not found!"
  exit 1
fi
