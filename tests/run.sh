#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname -- "$test_dir")"
output_dir="$(mktemp -d)"
iosys_output_dir="$output_dir/iosys"
audio_output_dir="$output_dir/audio"
audio_policy_output_dir="$output_dir/audio_policy"
hdmi_audio_output_dir="$output_dir/hdmi_audio"
ui_control_output_dir="$output_dir/ui_control"
ui_time_output_dir="$output_dir/ui_time"
ui_album_output_dir="$output_dir/ui_album"
ui_menu_output_dir="$output_dir/ui_menu"
ae350_bridge_output_dir="$output_dir/ae350_bridge"
ae350_loader_output_dir="$output_dir/ae350_loader"
keylink_output_dir="$output_dir/keylink_rx"
desk_layer_output_dir="$output_dir/ui_desk_layer"
mkdir "$iosys_output_dir" "$audio_output_dir" "$audio_policy_output_dir" \
    "$hdmi_audio_output_dir" "$ui_control_output_dir" "$ui_time_output_dir" \
    "$ui_album_output_dir" "$ui_menu_output_dir" \
    "$ae350_bridge_output_dir" "$ae350_loader_output_dir" \
    "$keylink_output_dir" "$desk_layer_output_dir"
trap 'find "$output_dir" -depth -delete' EXIT

verilator --binary --timing -Wno-fatal \
    --top-module i2s_tx_tb --Mdir "$output_dir/i2s_tx" \
    "$test_dir/i2s_tx_tb.sv" \
    "$project_dir/src/audio/i2s_tx.sv" \
    "$project_dir/src/audio/i2s_clock_probe.sv" \
    "$project_dir/src/pmod/pmod_i2s2_tone.sv" \
    "$project_dir/src/pmod/pmod_slot.sv" \
    "$project_dir/src/pmod/pmod_io_buf.sv"
"$output_dir/i2s_tx/Vi2s_tx_tb"

verilator --binary --timing -Wno-fatal -DSIM \
    --top-module iosys_debug_tb --Mdir "$iosys_output_dir" \
    "$test_dir/iosys_debug_tb.sv" \
    "$project_dir/src/iosys/iosys_bl616.v"
"$iosys_output_dir/Viosys_debug_tb"

verilator --binary --timing -Wno-fatal \
    -I"$project_dir/src/assets" -I"$project_dir/src/iosys" \
    --top-module ui_desk_layer_tb --Mdir "$desk_layer_output_dir" \
    "$test_dir/ui_desk_layer_tb.sv" \
    "$project_dir/src/video/ui_desk_layer.sv" \
    "$project_dir/src/iosys/textdisp_wide.sv"
"$desk_layer_output_dir/Vui_desk_layer_tb"

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
    --top-module ui_menu_renderer_tb --Mdir "$ui_menu_output_dir" \
    "$test_dir/ui_menu_renderer_tb.sv" \
    "$project_dir/src/ui/ui_menu_renderer.sv" \
    "$project_dir/src/ui/ui_swap.sv"
"$ui_menu_output_dir/Vui_menu_renderer_tb"

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
    --top-module pcm_sink_tb --Mdir "$output_dir/pcm_sink" \
    "$test_dir/pcm_sink_tb.sv" \
    "$project_dir/src/audio/pcm_sink.sv" \
    "$project_dir/src/audio/pcm_sample_fifo.sv"
"$output_dir/pcm_sink/Vpcm_sink_tb"

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


# The bridge with its dual-clock link at two forward-FIFO depths.  Both
# clocks and both FIFOs (command and response) are exercised, including the
# reset that clears them.
for fifo_depth in 3 2; do
    verilator --binary --timing -Wno-fatal \
        --top-module ae350_ram_bridge_tb -GDEPTH_BITS=$fifo_depth \
        --Mdir "$ae350_bridge_output_dir/depth$fifo_depth" \
        "$test_dir/ae350_ram_bridge_tb.sv" \
        "$project_dir/src/ae350/ae350_ram_bridge.sv" \
        "$project_dir/src/ae350/ae350_ram_link.sv" \
        "$project_dir/src/ae350/async_fifo_rst.sv"
    "$ae350_bridge_output_dir/depth$fifo_depth/Vae350_ram_bridge_tb"
done

verilator --binary --timing -Wno-fatal \
    --top-module ae350_play_stream_tb --Mdir "$output_dir/ae350_play_stream" \
    "$test_dir/ae350_play_stream_tb.sv" \
    "$project_dir/src/ae350/ae350_play_stream.sv" \
    "$project_dir/src/ae350/async_fifo.sv"
"$output_dir/ae350_play_stream/Vae350_play_stream_tb"

verilator --binary --timing -Wno-fatal \
    --top-module ae350_loader_tb --Mdir "$ae350_loader_output_dir" \
    "$test_dir/ae350_loader_tb.sv" \
    "$project_dir/src/ae350/ae350_stream_loader.sv" \
    "$project_dir/src/ae350/async_fifo.sv" \
    "$project_dir/src/ae350/ae350_exts_regs.sv" \
    "$project_dir/src/ae350/debug_read_cdc.sv"
"$ae350_loader_output_dir/Vae350_loader_tb"

verilator --binary --timing -Wno-fatal \
    --top-module oled_pmod_tb --Mdir "$output_dir/oled_pmod" \
    "$test_dir/oled_pmod_tb.sv" \
    "$project_dir/src/oled/oled_pmod_top.sv" \
    "$project_dir/src/oled/oled_panel.sv" \
    "$project_dir/src/oled/oled_spi.sv"
"$output_dir/oled_pmod/Voled_pmod_tb"

verilator --binary --timing -Wno-fatal \
    --top-module ui_mirror_tb --Mdir "$output_dir/ui_mirror" \
    "$test_dir/ui_mirror_tb.sv" \
    "$project_dir/src/pmod_mirror_core.sv" \
    "$project_dir/src/audio_test_source.sv" \
    "$project_dir/src/debug/ui_debug_regs.sv" \
    "$project_dir/src/pmod/pmod_slot.sv" \
    "$project_dir/src/pmod/pmod_io_buf.sv" \
    "$project_dir/src/pmod/pmod_oledrgb.sv" \
    "$project_dir/src/pmod/pmod_vga.sv" \
    "$project_dir/src/pmod/pmod_enc.sv" \
    "$project_dir/src/pmod/pmod_i2s2_tone.sv" \
    "$project_dir/src/audio/i2s_tx.sv" \
    "$project_dir/src/video/ui_vga_backend.sv" \
    "$project_dir/src/oled/oled_panel.sv" \
    "$project_dir/src/oled/oled_spi.sv" \
    "$project_dir/src/ui/ui_frame_store.sv" \
    "$project_dir/src/ui/ui_frame_bank.sv" \
    "$project_dir/src/ui/ui_menu_renderer.sv" \
    "$project_dir/src/ui/ui_scanout.sv" \
    "$project_dir/src/ui/ui_swap.sv" \
    "$project_dir/src/ui/ui_checksum.sv"
"$output_dir/ui_mirror/Vui_mirror_tb"

verilator --binary --timing -Wno-fatal \
    --top-module ui_hdmi_scan_tb --Mdir "$output_dir/ui_hdmi_scan" \
    "$test_dir/ui_hdmi_scan_tb.sv" \
    "$project_dir/src/video/ui_hdmi_scan.sv" \
    "$project_dir/src/ui/ui_scanout.sv"
"$output_dir/ui_hdmi_scan/Vui_hdmi_scan_tb"

verilator --binary --timing -Wno-fatal \
    --top-module keylink_rx_tb --Mdir "$output_dir/keylink_rx" \
    "$test_dir/keylink_rx_tb.sv" \
    "$project_dir/src/input/keylink_rx.sv"
"$output_dir/keylink_rx/Vkeylink_rx_tb"

verilator --binary --timing -Wno-fatal \
    --top-module debug_regs_tb --Mdir "$output_dir/debug_regs" \
    "$test_dir/debug_regs_tb.sv" \
    "$project_dir/src/debug/debug_regs.sv"
"$output_dir/debug_regs/Vdebug_regs_tb"
