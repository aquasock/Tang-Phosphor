#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Build the PMOD socket bring-up core.
#
#   scripts/build-pmod.sh [oled|vga]
#
#   oled  the panel on PMOD0, no second PMOD personality   (default)
#   vga   the PmodVGA occupying both sockets
#
# The two variants exist because the socket personalities are compile-time
# parameters until the debug transport lands.  They matter for more than
# testing: with no socket selecting the VGA backend, the whole backend is dead
# logic and the synthesiser removes it, so an OLED-only build says nothing
# about whether a third backend fits.
#
# Deliberately separate from the player: one placement option, its own
# constraint and SDC files, and its own top level, so experimenting with PMOD
# hardware cannot disturb the deployed player's timing or audio path.
#
#   GOWIN_SH   full path to Gowin's gw_sh (otherwise PATH, then the usual
#              install locations are probed)
set -euo pipefail

variant="${1:-oled}"
case "$variant" in
    oled)
        tcl_name="build-pmod.tcl"
        base="tang_phosphor_pmod"
        out_name="pmod"
        ;;
    vga)
        tcl_name="build-pmod-vga.tcl"
        base="tang_phosphor_vga"
        out_name="vga"
        ;;
    *)
        echo "unknown variant '$variant'; expected 'oled' or 'vga'" >&2
        exit 1
        ;;
esac

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$project_dir/build/$out_name"
work_dir="$(mktemp -d "/tmp/tang-phosphor-$out_name.XXXXXX")"

cleanup() { find "$work_dir" -depth -delete; }
trap cleanup EXIT

gowin_sh_path="${GOWIN_SH:-$(command -v gw_sh || true)}"
if [[ -z "$gowin_sh_path" ]]; then
    for candidate in \
        /home/vash/tools/gowin-1.9.11.03/IDE/bin/gw_sh \
        /opt/Gowin/Gowin_V1.9.11.03/IDE/bin/gw_sh
    do
        if [[ -x "$candidate" ]]; then
            gowin_sh_path="$candidate"
            break
        fi
    done
fi
if [[ -z "$gowin_sh_path" || ! -x "$gowin_sh_path" ]]; then
    echo "Gowin gw_sh not found; set GOWIN_SH to its full path." >&2
    exit 1
fi
export GOWIN_SH="$gowin_sh_path"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
system_freetype=/usr/lib/x86_64-linux-gnu/libfreetype.so.6
if [[ -f "$system_freetype" ]]; then
    export LD_PRELOAD="$system_freetype${LD_PRELOAD:+:$LD_PRELOAD}"
fi

rsync -a --exclude=.git --exclude=impl --exclude=build --exclude=third_party \
    "$project_dir/" "$work_dir/"

if ! (cd "$work_dir" && "$gowin_sh_path" "$tcl_name" > build.log 2>&1); then
    tail -30 "$work_dir/build.log" >&2
    exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir/impl/pnr"
cp "$work_dir/build.log" "$out_dir/"
cp "$work_dir"/impl/pnr/"$base".{bin,fs,rpt.txt} "$out_dir/" 2>/dev/null || true
cp "$work_dir"/impl/pnr/"$base"_tr_content.html "$out_dir/" 2>/dev/null || true
ln -sf ../../"$base"_tr_content.html "$out_dir/impl/pnr/"

echo "$variant variant:"
python3 "$project_dir/tools/gowin_timing_summary.py" "$out_dir" || true
sha256sum "$out_dir/$base.bin" 2>/dev/null || true
