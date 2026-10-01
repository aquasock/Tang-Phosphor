# Tang-Phosphor merged image: FPGA player + AE350 + DDR3 in one bitstream.
# Run by scripts/build-merged.sh in an isolated copy of the repository that
# also holds the generated boot ROM (src/ae350/ae350_boot.hex) and Gowin
# DDR3 IP (ip/).
set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0

# FPGA player.
add_file -type verilog "src/tang_phosphor_top.sv"
add_file -type verilog "src/phosphor_video.sv"
add_file -type verilog "src/audio_test_source.sv"
add_file -type verilog "src/audio/audio_output_policy.sv"
add_file -type verilog "src/audio/pcm_sample_fifo.sv"
add_file -type verilog "src/audio/pcm_sink.sv"
add_file -type verilog "src/debug/debug_regs.sv"
add_file -type verilog "src/stream/stream_debug_sink.sv"
add_file -type verilog "src/ui/phosphor_ui_control.sv"
add_file -type verilog "src/ui/phosphor_album_ui.sv"
add_file -type verilog "src/ui/phosphor_time_digits.sv"
add_file -type verilog "src/usb_hid_host.v"

add_file -type verilog "src/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi/audio_info_frame.sv"
add_file -type verilog "src/hdmi/audio_sample_packet.sv"
add_file -type verilog "src/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi/hdmi.sv"
add_file -type verilog "src/hdmi/packet_assembler.sv"
add_file -type verilog "src/hdmi/packet_picker.sv"
add_file -type verilog "src/hdmi/serializer.sv"
add_file -type verilog "src/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi/tmds_channel.sv"

add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"

add_file -type verilog "src/pll/pll_27.v"
add_file -type verilog "src/pll/pll_74.v"
add_file -type verilog "src/pll/pll_12.v"

# AE350 + DDR3 subsystem.
add_file -type verilog "src/ae350/ae350_subsystem.sv"
add_file -type verilog "src/ae350/ae350_soc.sv"
add_file -type verilog "src/ae350/ae350_pll.v"
add_file -type verilog "src/ae350/ae350_boot_rom.sv"
add_file -type verilog "src/ae350/ae350_ram_bridge.sv"
add_file -type verilog "src/ae350/ae350_ram_link.sv"
add_file -type verilog "src/ae350/ae350_play_stream.sv"
add_file -type verilog "src/ae350/ae350_exts_regs.sv"
add_file -type verilog "src/ae350/ae350_stream_loader.sv"
add_file -type verilog "src/ae350/async_fifo.sv"
add_file -type verilog "src/ae350/async_fifo_rst.sv"
add_file -type verilog "src/ae350/debug_read_cdc.sv"

add_file -type verilog "ip/ddr3_memory_interface/ddr3_memory_interface.v"
add_file -type verilog "ip/gowin_pll/gowin_pll_mod.v"
add_file -type verilog "ip/gowin_pll/pll_init.v"

add_file -type cst "src/boards/console138k_merged.cst"
add_file -type sdc "src/boards/console138k_merged.sdc"

set_option -output_base_name tang_phosphor_merged
set_option -synthesis_tool gowinsynthesis
set_option -top_module tang_phosphor_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_cpu_as_gpio 0
set_option -multi_boot 1
set place_option 4
if {[info exists ::env(GOWIN_PLACE_OPTION)]} {
    set place_option $::env(GOWIN_PLACE_OPTION)
}
set_option -place_option $place_option
# GW5A only (SUG100 8.3): let place and route replicate high-fanout drivers.
# The merged image spreads the player and the AE350 interface across the
# die, which turns fanout into long routes.
set_option -replicate_resources 1

run all
