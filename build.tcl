set_device GW5AST-LV138PG484AC1/I0 -device_version B

add_file -type verilog "src/tang_phosphor_top.sv"
add_file -type verilog "src/phosphor_video.sv"
add_file -type verilog "src/audio_test_source.sv"
add_file -type verilog "src/audio/audio_output_policy.sv"
add_file -type verilog "src/audio/pcm_sample_fifo.sv"
add_file -type verilog "src/audio/stream_format_detector.sv"
add_file -type verilog "src/audio/wav_decoder.sv"
add_file -type verilog "src/audio/flac_subframe_decoder.sv"
add_file -type verilog "src/audio/flac_frame_ram.sv"
add_file -type verilog "src/audio/flac_decoder.sv"
add_file -type verilog "src/audio/wav_stream_player.sv"
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
add_file -type cst "src/boards/console138k.cst"
add_file -type sdc "src/boards/console138k.sdc"

set_option -output_base_name tang_phosphor_console138k
set_option -synthesis_tool gowinsynthesis
set_option -top_module tang_phosphor_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -multi_boot 1
set place_option 2
if {[info exists ::env(GOWIN_PLACE_OPTION)]} {
    set place_option $::env(GOWIN_PLACE_OPTION)
}
set_option -place_option $place_option

run all
