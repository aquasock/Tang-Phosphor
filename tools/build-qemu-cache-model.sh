#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Build a plugin-enabled qemu-riscv32 (linux-user) and QEMU's contrib cache
# model plugin, used to estimate AE350 cache misses for RV32 codec builds.
#
# Distribution QEMU packages are built without TCG plugin support, so QEMU
# 10.2.1 is built from its signed release tarball.  When the glib development
# headers are not installed, the Ubuntu packages are unpacked into a private
# sysroot instead of requiring root.  Everything is placed under
# $TANG_PHOSPHOR_DEV (default ~/.cache/tang-phosphor-dev):
#
#   qemu-10.2.1/build/qemu-riscv32
#   qemu-10.2.1/build/contrib/plugins/libcache.so

set -euo pipefail

QEMU_VERSION=10.2.1
QEMU_SHA256=a3717477d8e2c84d630bfffbc20f6cd3293eb45aa1e6dac6d0cc27689991c9e1
DEV_DIR=${TANG_PHOSPHOR_DEV:-$HOME/.cache/tang-phosphor-dev}
SYSROOT="$DEV_DIR/sysroot"
QEMU_DIR="$DEV_DIR/qemu-$QEMU_VERSION"
TARBALL="$DEV_DIR/qemu-$QEMU_VERSION.tar.xz"

mkdir -p "$DEV_DIR"

if ! pkg-config --exists glib-2.0 2>/dev/null; then
    if [[ ! -f "$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig/glib-2.0.pc" ]]; then
        mkdir -p "$DEV_DIR/debs" "$SYSROOT"
        (
            cd "$DEV_DIR/debs"
            apt-get download libglib2.0-dev libglib2.0-dev-bin libgio-2.0-dev \
                libsysprof-capture-4-dev libpcre2-dev libffi-dev zlib1g-dev \
                libmount-dev libselinux-dev libblkid-dev libsepol-dev
            for package in *.deb; do
                dpkg -x "$package" "$SYSROOT"
            done
        )
    fi
    # The unpacked .pc files name /usr; point them at the private sysroot.
    # Runtime libraries come from the host, which already has them.
    for pc in "$SYSROOT"/usr/lib/x86_64-linux-gnu/pkgconfig/*.pc \
              "$SYSROOT"/usr/share/pkgconfig/*.pc; do
        [[ -f "$pc" ]] && sed -i "s#^prefix=/usr\$#prefix=$SYSROOT/usr#" "$pc"
    done
    for library in "$SYSROOT"/usr/lib/x86_64-linux-gnu/lib*.so; do
        target=$(readlink "$library" || true)
        if [[ -n "$target" && ! -e "$library" && -e "/usr/lib/x86_64-linux-gnu/$target" ]]; then
            ln -sf "/usr/lib/x86_64-linux-gnu/$target" "$library"
        fi
    done
    export PKG_CONFIG_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

if [[ ! -f "$TARBALL" ]]; then
    curl -sSfL "https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz" -o "$TARBALL"
fi
echo "$QEMU_SHA256  $TARBALL" | sha256sum -c -

if [[ ! -d "$QEMU_DIR" ]]; then
    tar -C "$DEV_DIR" -xf "$TARBALL"
fi

cd "$QEMU_DIR"
if [[ ! -f build/build.ninja ]]; then
    ./configure --target-list=riscv32-linux-user --enable-plugins \
        --disable-docs --disable-werror --without-default-features
fi
ninja -C build qemu-riscv32 contrib/plugins/libcache.so

echo "qemu-riscv32: $QEMU_DIR/build/qemu-riscv32"
echo "cache plugin: $QEMU_DIR/build/contrib/plugins/libcache.so"
