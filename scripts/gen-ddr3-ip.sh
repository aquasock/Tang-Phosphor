#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Generate the Gowin DDR3 controller and its PLL from the committed
# configuration in src/ddr3 (ported from Tang-PSX scripts/gen-ddr3-ip.sh).
# Gowin's generated, encrypted RTL is licensed with Gowin EDA and is never
# committed; it is produced from the local installation.
#
# Usage: scripts/gen-ddr3-ip.sh [IP_DIR]   (default build/ddr3-ip)

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="$project_dir/src/ddr3"
ip_dir="$(realpath -m "${1:-$project_dir/build/ddr3-ip}")"

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
gowin_bin="$(dirname -- "$gowin_sh_path")"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
system_freetype=/usr/lib/x86_64-linux-gnu/libfreetype.so.6
if [[ -f "$system_freetype" ]]; then
    export LD_PRELOAD="$system_freetype${LD_PRELOAD:+:$LD_PRELOAD}"
fi

rm -rf "$ip_dir"
mkdir -p "$ip_dir/project" "$ip_dir/gowin_pll"

# gw_sh's read_ipc crashes in batch mode, so the IP is created and configured
# through set_property instead; the emitted .ipc proves the configuration.
cat > "$ip_dir/gen.tcl" <<TCL
create_project -name ddr3_ip -dir {$ip_dir/project} -pn GW5AST-LV138PG484AC1/I0 -device_version C -force
create_ipc -name ddr3 -dir {$ip_dir} -module_name DDR3_Memory_Interface_Top -file_name ddr3_memory_interface -language Verilog
source {$config_dir/ddr3_ip.tcl}
generate_target [get_ips DDR3_Memory_Interface_Top]
TCL
(cd "$ip_dir" && "$gowin_sh_path" gen.tcl > gen.log 2>&1) || {
    tail -20 "$ip_dir/gen.log" >&2
    exit 1
}

ddr3_rtl="$ip_dir/ddr3_memory_interface/ddr3_memory_interface.v"
if [[ ! -s "$ddr3_rtl" ]]; then
    echo "DDR3 IP generation produced no RTL; see $ip_dir/gen.log" >&2
    exit 1
fi
if ! diff -u "$config_dir/ddr3_memory_interface.ipc" \
        "$ip_dir/ddr3_memory_interface/ddr3_memory_interface.ipc"; then
    echo "Generated DDR3 .ipc differs from the committed reference" >&2
    exit 1
fi

sed "s#@OUTPUT_DIR@#$ip_dir/gowin_pll#" "$config_dir/gowin_pll.mod" \
    > "$ip_dir/gowin_pll/gowin_pll.mod"
(cd "$ip_dir/gowin_pll" && "$gowin_bin/GowinModGen" -do gowin_pll.mod > gen.log 2>&1) || {
    cat "$ip_dir/gowin_pll/gen.log" >&2
    exit 1
}
if [[ ! -s "$ip_dir/gowin_pll/gowin_pll_mod.v" ]]; then
    echo "PLL generation produced no RTL; see $ip_dir/gowin_pll/gen.log" >&2
    exit 1
fi

# PLL_INIT is distributed with the Gowin PLL_ADV IP core.
install -m 0644 "$gowin_bin/../ipcore/PLL_ADV/data/PLL/pll_init.v" "$ip_dir/gowin_pll/pll_init.v"

echo "Generated Gowin DDR3 and PLL IP in $ip_dir"
