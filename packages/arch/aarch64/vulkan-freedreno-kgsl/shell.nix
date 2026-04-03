# nix-shell for cross-compiling Mesa Turnip (Vulkan) with KGSL for aarch64.
# Usage: nix-shell shell.nix
#        ./build.sh
{ pkgs ? import <nixpkgs> {} }:

let
  crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
  cc = crossPkgs.stdenv.cc;
in pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    python3
    python3Packages.mako
    python3Packages.packaging
    python3Packages.ply
    python3Packages.pycparser
    python3Packages.pyyaml
    glslang
    cmake
    bison
    flex
    wayland-scanner
    cc
  ];

  # Cross-compiled target libraries
  buildInputs = with crossPkgs; [
    libdrm
    wayland
    wayland-protocols
    libxcb
    xorg.libX11
    xorg.libXrandr
    xorg.libxshmfence
    expat
    zlib
    zstd
    spirv-tools
    glslang
    vulkan-loader
    xorg.xcbutilkeysyms
    libxml2
    libarchive
    ncurses
    elfutils
  ];

  shellHook = ''
    export CROSS_PREFIX="${cc.targetPrefix}"
    echo "Cross-compiler: ''${CROSS_PREFIX}gcc"
    echo "Run: ./build.sh"
  '';
}
