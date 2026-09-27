#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$test_dir")"
output_dir="$(mktemp -d)"
iosys_output_dir="$output_dir/iosys"
audio_output_dir="$output_dir/audio"
mkdir "$iosys_output_dir" "$audio_output_dir"
trap 'find "$output_dir" -depth -delete' EXIT

verilator --binary --timing -Wno-fatal -DSIM \
    --top-module iosys_debug_tb --Mdir "$iosys_output_dir" \
    "$test_dir/iosys_debug_tb.sv" \
    "$project_dir/src/iosys/iosys_bl616.v"
"$iosys_output_dir/Viosys_debug_tb"

verilator --binary --timing -Wno-fatal \
    --top-module audio_test_source_tb --Mdir "$audio_output_dir" \
    "$test_dir/audio_test_source_tb.sv" \
    "$project_dir/src/audio_test_source.sv"
"$audio_output_dir/Vaudio_test_source_tb"
