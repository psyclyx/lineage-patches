{ pkgs ? import <nixpkgs> {
    crossSystem = {
      config = "aarch64-unknown-linux-gnu";
    };
  }
}:

pkgs.mkShell {
  depsBuildBuild = with pkgs.buildPackages; [
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
  ];

  buildInputs = with pkgs; [
    libdrm
    wayland
    wayland-protocols
    libxcb
    xorg.libX11
    xorg.libXrandr
    xorg.libxshmfence
    xorg.xorgproto
    expat
    zlib
    zstd
    spirv-tools
    vulkan-loader
    xorg.xcbutilkeysyms
    libxml2
  ];

  shellHook = ''
    echo "Mesa Turnip KGSL cross-compilation environment"
    echo "Target: aarch64-unknown-linux-gnu"
    echo ""
    echo "Usage:"
    echo "  cd mesa-26.0.3"
    echo "  meson setup build --cross-file ../meson-cross.ini ..."
    echo "  ninja -C build"

    # Build PKG_CONFIG_PATH from all aarch64 buildInputs so the cross
    # pkg-config wrapper can find .pc files for target dependencies.
    export NIX_PKG_CONFIG_WRAPPER_FLAGS_SET_aarch64_unknown_linux_gnu=1
    export PKG_CONFIG_PATH_aarch64_unknown_linux_gnu=""
    for dir in ${builtins.concatStringsSep " " (map (p: "${p}/lib/pkgconfig ${p}/share/pkgconfig") [
      pkgs.libdrm.dev
      pkgs.wayland.dev
      pkgs.wayland-protocols
      pkgs.libxcb.dev
      pkgs.xorg.libX11.dev
      pkgs.xorg.libXrandr.dev
      pkgs.xorg.libxshmfence.dev
      pkgs.xorg.xorgproto
      pkgs.expat.dev
      pkgs.zlib.dev
      pkgs.zstd.dev
      pkgs.spirv-tools
      pkgs.vulkan-loader.dev
      pkgs.xorg.xcbutilkeysyms.dev
      pkgs.libxml2.dev
      pkgs.xorg.libXrender.dev
      pkgs.xorg.libXext.dev
    ])}; do
      if [ -d "$dir" ]; then
        export PKG_CONFIG_PATH_aarch64_unknown_linux_gnu="''${PKG_CONFIG_PATH_aarch64_unknown_linux_gnu:+$PKG_CONFIG_PATH_aarch64_unknown_linux_gnu:}$dir"
      fi
    done
  '';
}
