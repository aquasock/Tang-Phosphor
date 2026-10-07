#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Verify the behavioral RAM and the installed Gowin primitive model agree.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
sim_lib="${GOWIN_SIM_LIB:-/home/vash/tools/gowin-1.9.11.03/IDE/simlib/gw5a/prim_sim.v}"
out_dir="${1:-$project_dir/build/oscope-ram-tests}"
mkdir -p "$out_dir"
iverilog -g2012 -DSCOPE_RAM_BEHAVIORAL -s scope_ram_tb -o "$out_dir/behavioral" \
    "$project_dir/tests/scope_ram_tb.sv" "$project_dir/src/visualizers/scope_phosphor_ram.sv"
vvp "$out_dir/behavioral"
if [[ ! -f "$sim_lib" ]]; then
    echo "Gowin primitive model missing; set GOWIN_SIM_LIB" >&2
    exit 1
fi
iverilog -g2012 -s scope_ram_tb -o "$out_dir/vendor" \
    "$project_dir/tests/scope_ram_tb.sv" \
    "$project_dir/src/visualizers/scope_phosphor_ram.sv" "$sim_lib"
vvp "$out_dir/vendor"
