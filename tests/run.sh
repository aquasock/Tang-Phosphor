#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$test_dir")"
output_dir="$(mktemp -d)"
iosys_output_dir="$output_dir/iosys"
audio_output_dir="$output_dir/audio"
wav_output_dir="$output_dir/wav"
detector_output_dir="$output_dir/detector"
hdmi_audio_output_dir="$output_dir/hdmi_audio"
mkdir "$iosys_output_dir" "$audio_output_dir" "$wav_output_dir" "$detector_output_dir" "$hdmi_audio_output_dir"
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

verilator --binary --timing -Wno-fatal \
    --top-module hdmi_audio_rate_tb --Mdir "$hdmi_audio_output_dir" \
    "$test_dir/hdmi_audio_rate_tb.sv" \
    "$project_dir/src/audio_test_source.sv" \
    "$project_dir/src/hdmi/audio_clock_regeneration_packet.sv" \
    "$project_dir/src/hdmi/audio_sample_packet.sv" \
    "$project_dir/src/hdmi/packet_picker.sv" \
    "$project_dir/src/hdmi/audio_info_frame.sv" \
    "$project_dir/src/hdmi/auxiliary_video_information_info_frame.sv" \
    "$project_dir/src/hdmi/source_product_description_info_frame.sv"
"$hdmi_audio_output_dir/Vhdmi_audio_rate_tb"

verilator --binary --timing -Wno-fatal \
    --top-module stream_format_detector_tb --Mdir "$detector_output_dir" \
    "$test_dir/stream_format_detector_tb.sv" \
    "$project_dir/src/audio/stream_format_detector.sv"
"$detector_output_dir/Vstream_format_detector_tb"

verilator --binary --timing -Wno-fatal \
    --top-module wav_stream_player_tb --Mdir "$wav_output_dir" \
    "$test_dir/wav_stream_player_tb.sv" \
    "$project_dir/src/audio/wav_stream_player.sv" \
    "$project_dir/src/audio/stream_format_detector.sv" \
    "$project_dir/src/audio/wav_decoder.sv" \
    "$project_dir/src/audio/pcm_sample_fifo.sv"
"$wav_output_dir/Vwav_stream_player_tb"
