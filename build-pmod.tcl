set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0

add_file -type verilog "src/pmod_mirror_top.sv"
add_file -type verilog "src/pmod_mirror_core.sv"

# Socket layer and personalities.
add_file -type verilog "src/pmod/pmod_slot.sv"
add_file -type verilog "src/pmod/pmod_io_buf.sv"
add_file -type verilog "src/pmod/pmod_oledrgb.sv"
add_file -type verilog "src/pmod/pmod_vga.sv"

# Panel protocol.
add_file -type verilog "src/oled/oled_panel.sv"
add_file -type verilog "src/oled/oled_spi.sv"

# Renderer and presentation backends.
add_file -type verilog "src/ui/ui_frame_store.sv"
add_file -type verilog "src/ui/ui_pattern_demo.sv"
add_file -type verilog "src/ui/ui_scanout.sv"
add_file -type verilog "src/ui/ui_swap.sv"
add_file -type verilog "src/ui/ui_checksum.sv"
add_file -type verilog "src/video/ui_hdmi_scan.sv"
add_file -type verilog "src/video/ui_hdmi_backend.sv"
add_file -type verilog "src/video/ui_vga_backend.sv"

# HDMI transmitter and its packet machinery.
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

add_file -type verilog "src/audio_test_source.sv"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type verilog "src/debug/ui_debug_regs.sv"
add_file -type verilog "src/pll/pll_27.v"
add_file -type verilog "src/pll/pll_74.v"

add_file -type cst "src/boards/console138k_pmod.cst"
add_file -type sdc "src/boards/console138k_pmod.sdc"

set_option -output_base_name tang_phosphor_pmod
set_option -synthesis_tool gowinsynthesis
set_option -top_module pmod_mirror_top
set_option -verilog_std sysv2017
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 0
set_option -multi_boot 1
set_option -place_option 3

run all
