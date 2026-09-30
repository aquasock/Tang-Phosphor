# Tang-Phosphor AE350 + DDR3 image.  Run by scripts/build-ae350-ddr3.sh in an
# isolated copy of the repository that also holds the generated boot ROM
# (src/ae350/ae350_boot.hex) and Gowin DDR3 IP (ip/).
set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0

add_file -type verilog "src/ae350/ae350_ddr3_top.sv"
add_file -type verilog "src/ae350/ae350_soc.sv"
add_file -type verilog "src/ae350/ae350_pll.v"
add_file -type verilog "src/ae350/ae350_boot_rom.sv"
add_file -type verilog "src/ae350/ae350_ram_bridge.sv"
add_file -type verilog "src/ae350/ae350_exts_regs.sv"
add_file -type verilog "src/ae350/ae350_stream_loader.sv"
add_file -type verilog "src/ae350/async_fifo.sv"
add_file -type verilog "src/ae350/debug_read_cdc.sv"
add_file -type verilog "ip/ddr3_memory_interface/ddr3_memory_interface.v"
add_file -type verilog "ip/gowin_pll/gowin_pll_mod.v"
add_file -type verilog "ip/gowin_pll/pll_init.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type cst "src/boards/console138k_ae350_ddr3.cst"
add_file -type sdc "src/boards/console138k_ae350_ddr3.sdc"

set_option -output_base_name tang_phosphor_ae350_ddr3
set_option -synthesis_tool gowinsynthesis
set_option -top_module ae350_ddr3_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_cpu_as_gpio 0
set_option -multi_boot 1
set place_option 1
if {[info exists ::env(GOWIN_PLACE_OPTION)]} {
    set place_option $::env(GOWIN_PLACE_OPTION)
}
set_option -place_option $place_option

run all
