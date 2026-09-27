#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$test_dir")"
output_dir="$(mktemp -d)"
trap 'find "$output_dir" -type f -delete; rmdir "$output_dir"' EXIT

verilator --binary --timing -Wno-fatal -DSIM \
    --top-module iosys_debug_tb --Mdir "$output_dir" \
    "$test_dir/iosys_debug_tb.sv" \
    "$project_dir/src/iosys/iosys_bl616.v"
"$output_dir/Viosys_debug_tb"
