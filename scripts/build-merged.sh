#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Build the merged image: the FPGA player plus the AE350 + DDR3 subsystem in
# one bitstream.  Generates the boot ROM (software/ae350), the Gowin DDR3 IP
# (scripts/gen-ddr3-ip.sh), and one Gowin build per placement option in
# parallel, each in an isolated copy of the repository.  Bitstreams and
# reports go to build/merged/place<N>/.
#
#   MERGED_PLACE_OPTIONS   placement options (default "4"; Gowin accepts
#                           only 0-4 for GW5A devices, SUG100 8.3)
#   RISCV_TOOLCHAIN_BIN    riscv64-unknown-elf toolchain directory

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$project_dir/build/merged"
place_options=${MERGED_PLACE_OPTIONS:-"4"}

# Each Gowin build of this design peaks at several GB; five in parallel
# exhausted the 15 GB build host.  Run larger option sets in batches.
read -r -a place_option_list <<< "$place_options"
if (( ${#place_option_list[@]} > 4 )); then
    echo "At most 4 parallel builds; MERGED_PLACE_OPTIONS lists ${#place_option_list[@]}." >&2
    exit 1
fi
toolchain_bin=${RISCV_TOOLCHAIN_BIN:-/home/vash/.cache/tangcore-dev/toolchain/bin}
export PATH="$toolchain_bin:$PATH"

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

make -C "$project_dir/software/ae350" BUILD="$out_dir/software" > /dev/null
"$project_dir/scripts/gen-ddr3-ip.sh" "$out_dir/ip" > /dev/null

work_root="$(mktemp -d /tmp/tang-phosphor-merged.XXXXXX)"
trap 'find "$work_root" -depth -delete' EXIT

pids=()
for option in $place_options; do
    work="$work_root/place$option"
    mkdir -p "$work"
    rsync -a --exclude=.git --exclude=impl --exclude=build --exclude=third_party \
        "$project_dir/" "$work/"
    cp "$out_dir/software/boot/ae350_boot.hex" "$work/src/ae350/ae350_boot.hex"
    cp -r "$out_dir/ip" "$work/ip"
    (cd "$work" && GOWIN_PLACE_OPTION=$option "$gowin_sh_path" build-merged.tcl \
        > build.log 2>&1) &
    pids+=("$!")
done

status=0
for pid in "${pids[@]}"; do
    wait "$pid" || status=1
done

builds=()
for option in $place_options; do
    work="$work_root/place$option"
    dest="$out_dir/place$option"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp "$work/build.log" "$dest/"
    cp "$work"/impl/pnr/tang_phosphor_merged.{bin,fs,rpt.txt} \
       "$work"/impl/pnr/tang_phosphor_merged_tr_content.html \
       "$work"/impl/pnr/tang_phosphor_merged.timing_paths "$dest/" 2>/dev/null || true
    if [[ -s "$dest/tang_phosphor_merged.bin" ]]; then
        mkdir -p "$dest/impl/pnr"
        ln -sf ../../tang_phosphor_merged_tr_content.html "$dest/impl/pnr/"
        builds+=("$dest")
    else
        echo "placement option $option produced no bitstream; see $dest/build.log" >&2
        status=1
    fi
done

if (( ${#builds[@]} )); then
    python3 "$project_dir/tools/gowin_timing_summary.py" "${builds[@]}" || true
    (cd "$out_dir" && sha256sum place*/tang_phosphor_merged.bin)
fi
exit $status
