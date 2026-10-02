set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0

add_file -type verilog "src/pmod_mirror_top.sv"
add_file -type verilog "src/pmod/pmod_slot.sv"
add_file -type verilog "src/pmod/pmod_io_buf.sv"
add_file -type verilog "src/pmod/pmod_oledrgb.sv"
add_file -type verilog "src/oled/oled_panel.sv"
add_file -type verilog "src/oled/oled_spi.sv"
add_file -type verilog "src/ui/ui_frame_store.sv"
add_file -type verilog "src/ui/ui_pattern_demo.sv"
add_file -type verilog "src/ui/ui_scanout.sv"
add_file -type verilog "src/ui/ui_swap.sv"
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
