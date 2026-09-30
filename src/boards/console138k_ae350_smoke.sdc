create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]

# The 50 MHz reference count enters the AE350 bus domain in Gray code. Only
# the first synchronizer stage is unconstrained.
set_false_path -to [get_regs {ref_gray_meta*}]
