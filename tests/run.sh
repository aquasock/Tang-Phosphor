#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$test_dir")"
output_dir="$(mktemp -d)"
iosys_output_dir="$output_dir/iosys"
audio_output_dir="$output_dir/audio"
audio_policy_output_dir="$output_dir/audio_policy"
wav_output_dir="$output_dir/wav"
detector_output_dir="$output_dir/detector"
flac_output_dir="$output_dir/flac"
flac_vector_dir="$output_dir/flac_vectors"
hdmi_audio_output_dir="$output_dir/hdmi_audio"
ui_control_output_dir="$output_dir/ui_control"
ui_time_output_dir="$output_dir/ui_time"
ui_album_output_dir="$output_dir/ui_album"
ae350_bridge_output_dir="$output_dir/ae350_bridge"
ae350_loader_output_dir="$output_dir/ae350_loader"
mkdir "$iosys_output_dir" "$audio_output_dir" "$audio_policy_output_dir" "$wav_output_dir" "$detector_output_dir" \
    "$flac_output_dir" "$flac_vector_dir" "$hdmi_audio_output_dir" "$ui_control_output_dir" "$ui_time_output_dir" \
    "$ui_album_output_dir" "$ae350_bridge_output_dir" "$ae350_loader_output_dir"
trap 'find "$output_dir" -depth -delete' EXIT

verilator --binary --timing -Wno-fatal -DSIM \
    --top-module iosys_debug_tb --Mdir "$iosys_output_dir" \
    "$test_dir/iosys_debug_tb.sv" \
    "$project_dir/src/iosys/iosys_bl616.v"
"$iosys_output_dir/Viosys_debug_tb"

verilator --binary --timing -Wno-fatal \
    --top-module phosphor_ui_control_tb --Mdir "$ui_control_output_dir" \
    "$test_dir/phosphor_ui_control_tb.sv" \
    "$project_dir/src/ui/phosphor_ui_control.sv"
"$ui_control_output_dir/Vphosphor_ui_control_tb"

verilator --binary --timing -Wno-fatal \
    --top-module phosphor_time_digits_tb --Mdir "$ui_time_output_dir" \
    "$test_dir/phosphor_time_digits_tb.sv" \
    "$project_dir/src/ui/phosphor_time_digits.sv"
"$ui_time_output_dir/Vphosphor_time_digits_tb"

verilator --binary --timing -Wno-fatal -DSIM \
    --top-module phosphor_album_ui_tb --Mdir "$ui_album_output_dir" \
    "$test_dir/phosphor_album_ui_tb.sv" \
    "$project_dir/src/ui/phosphor_album_ui.sv" \
    "$project_dir/src/ui/phosphor_time_digits.sv"
"$ui_album_output_dir/Vphosphor_album_ui_tb"

verilator --binary --timing -Wno-fatal \
    --top-module audio_test_source_tb --Mdir "$audio_output_dir" \
    "$test_dir/audio_test_source_tb.sv" \
    "$project_dir/src/audio_test_source.sv"
"$audio_output_dir/Vaudio_test_source_tb"

verilator --binary --timing -Wno-fatal \
    --top-module audio_output_policy_tb --Mdir "$audio_policy_output_dir" \
    "$test_dir/audio_output_policy_tb.sv" \
    "$project_dir/src/audio/audio_output_policy.sv"
"$audio_policy_output_dir/Vaudio_output_policy_tb"

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

python3 "$project_dir/tools/generate_flac_test_vectors.py" "$flac_vector_dir"

verilator --binary --timing -Wno-fatal \
    --top-module flac_decoder_tb --Mdir "$flac_output_dir" \
    "$test_dir/flac_decoder_tb.sv" \
    "$project_dir/src/audio/flac_decoder.sv" \
    "$project_dir/src/audio/flac_subframe_decoder.sv" \
    "$project_dir/src/audio/flac_frame_ram.sv"
"$flac_output_dir/Vflac_decoder_tb" +VECTOR_DIR="$flac_vector_dir"

verilator --binary --timing -Wno-fatal \
    --top-module wav_stream_player_tb --Mdir "$wav_output_dir" \
    "$test_dir/wav_stream_player_tb.sv" \
    "$project_dir/src/audio/wav_stream_player.sv" \
    "$project_dir/src/audio/stream_format_detector.sv" \
    "$project_dir/src/audio/wav_decoder.sv" \
    "$project_dir/src/audio/flac_decoder.sv" \
    "$project_dir/src/audio/flac_subframe_decoder.sv" \
    "$project_dir/src/audio/flac_frame_ram.sv" \
    "$project_dir/src/audio/pcm_sample_fifo.sv"
"$wav_output_dir/Vwav_stream_player_tb" +VECTOR_DIR="$flac_vector_dir"

verilator --binary --timing -Wno-fatal \
    --top-module ae350_ram_bridge_tb --Mdir "$ae350_bridge_output_dir" \
    "$test_dir/ae350_ram_bridge_tb.sv" \
    "$project_dir/src/ae350/ae350_ram_bridge.sv"
"$ae350_bridge_output_dir/Vae350_ram_bridge_tb"

verilator --binary --timing -Wno-fatal \
    --top-module ae350_loader_tb --Mdir "$ae350_loader_output_dir" \
    "$test_dir/ae350_loader_tb.sv" \
    "$project_dir/src/ae350/ae350_stream_loader.sv" \
    "$project_dir/src/ae350/async_fifo.sv" \
    "$project_dir/src/ae350/ae350_exts_regs.sv" \
    "$project_dir/src/ae350/debug_read_cdc.sv"
"$ae350_loader_output_dir/Vae350_loader_tb"
