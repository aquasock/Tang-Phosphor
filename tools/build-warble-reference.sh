#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Build Rockbox's warble (x86-64) from third_party/rockbox as the reference
# decoder for tools/rbhost_profile.py.  warble is configured with Rockbox's
# own tools/configure (target sdlapp, type W).  It needs SDL2 headers; when
# they are not installed, libsdl2-dev is unpacked into the private sysroot
# used by tools/build-qemu-cache-model.sh and linked against the host's
# shared libSDL2.
#
# Usage: tools/build-warble-reference.sh [BUILD_DIR]
#   default BUILD_DIR: build/warble-x86; the binary is BUILD_DIR/warble.sdlapp

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=$(realpath -m "${1:-$PROJECT_ROOT/build/warble-x86}")
DEV_DIR=${TANG_PHOSPHOR_DEV:-$HOME/.cache/tang-phosphor-dev}
SYSROOT="$DEV_DIR/sysroot"

if ! command -v sdl2-config >/dev/null 2>&1; then
    if [[ ! -x "$SYSROOT/usr/bin/sdl2-config" ]]; then
        mkdir -p "$DEV_DIR/debs" "$SYSROOT"
        (cd "$DEV_DIR/debs" && apt-get download libsdl2-dev)
        dpkg -x "$DEV_DIR"/debs/libsdl2-dev_*.deb "$SYSROOT"
        sed -i "s#^prefix=/usr\$#prefix=$SYSROOT/usr#" \
            "$SYSROOT/usr/bin/sdl2-config" \
            "$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig/sdl2.pc"
        ln -sf /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 \
            "$SYSROOT/usr/lib/x86_64-linux-gnu/libSDL2.so"
    fi
    export PATH="$SYSROOT/usr/bin:$PATH"
    export CPATH="$SYSROOT/usr/include/x86_64-linux-gnu${CPATH:+:$CPATH}"
    export LIBRARY_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export PKG_CONFIG_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
"$PROJECT_ROOT/third_party/rockbox/tools/configure" --target=sdlapp --type=W \
    > configure.log
# configure selects SDL's static link line; only the shared library is
# needed, since warble writes files and never opens an audio device here.
sed -i 's#^export LDOPTS=.*#export LDOPTS= -lm -ldl -lSDL2 -lpthread#' Makefile
make -j"$(nproc)" > make.log
echo "warble: $BUILD_DIR/warble.sdlapp"
