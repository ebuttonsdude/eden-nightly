#!/bin/sh
set -ex

case "$TARGET" in
  FreeBSD)
    sed -i '' -e 's/quarterly/latest/' /etc/pkg/FreeBSD.conf
    export ASSUME_ALWAYS_YES=true
    pkg install -y autoconf bash boost-libs catch2 cmake ffmpeg gcc gmake git glslang libfmt libzip nasm llvm20 \
                ninja openssl opus pkgconf qt6-base qt6ct qt6-tools qt6-translations qt6-wayland sdl2 unzip vulkan-tools vulkan-loader wget zip zstd
    ;;
  Solaris)
    pkg install git cmake developer/gcc-14 developer/build/ninja runtime/clang-20
    pkg install qt6 libzip openssl zlib compress/zstd unzip pkg-config nasm autoconf mesa library/libdrm
    ;;
esac
