set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0

add_file -type verilog "src/ae350/ae350_smoke_top.sv"
add_file -type verilog "src/ae350/ae350_soc_smoke.sv"
add_file -type verilog "src/ae350/ae350_pll.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type cst "src/boards/console138k_ae350_smoke.cst"
add_file -type sdc "src/boards/console138k_ae350_smoke.sdc"

set_option -output_base_name tang_phosphor_ae350_smoke
set_option -synthesis_tool gowinsynthesis
set_option -top_module ae350_smoke_top
set_option -verilog_std sysv2017
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 0
set_option -multi_boot 1
set_option -place_option 3

run all
