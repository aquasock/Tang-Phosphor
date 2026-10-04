-series GW5AST
-device GW5AST-138
-device_version C
-package PBGA484A
-part_number GW5AST-LV138PG484AC1/I0

# 48 MHz for the USB 1.1 SoftPHY input clock (full-speed 12 Mb/s oversampled 4x).
# Derived from the DDR3 PLL recipe (src/ddr3/gowin_pll.mod); the divider chain
# and the port set both differ. With fclkin 50, idiv_sel 1 and fbdiv_sel 1 the
# output is
#   f = fclkin * mdiv_sel * (fbdiv_sel + 1) / ((idiv_sel + 1) * odiv0_sel)
#     = 50 * 24 * 2 / (2 * 25) = 48.0 MHz
# which also puts the VCO at 1200 MHz, inside the range the existing PLLs use
# (pll_12 900, pll_27 1350, pll_74 1485, the DDR3 PLL 800).
#
# clock_en, rst, dyn_icp_sel and dyn_lpf_sel are all false so the generated
# wrapper has the same port set as src/pll/pll_12.v and pll_27.v and pll_74.v
# -- (lock, clkout0, clkin) -- rather than exposing reset, icpsel, lpfres,
# lpfcap and enclk0 as ports for the caller to drive.
-mod_name pll_48
-file_name pll_48
-path @OUTPUT_DIR@/
-type PLL_ADV
-file_type vlg
-ip_version 1.0
-ssc false
-clock_en false
-rst false
-rst_pwd false
-rst_i false
-rst_o false
-fclkin 50
-dyn_idiv_sel false
-idiv_sel 1
-clkfb_sel 0
-dyn_fbdiv_sel false
-fbdiv_sel 1
-dyn_icp_sel false
-dyn_lpf_sel false
-en_lock true
-dyn_dpa_en false
-clkout0_bypass false
-dyn_odiv0_sel false
-odiv0_sel 25
-odiv0_frac_sel 0
-dyn_dt0_sel false
-clkout0_dt_dir 1
-clkout0_dt_step 0
-dyn_pe0_sel false
-clkout0_pe_coarse 0
-clkout0_pe_fine 0
-de0_en false
-en_clkout1 false
-en_clkout2 false
-en_clkout3 false
-en_clkout4 false
-en_clkout5 false
-en_clkout6 false
-en_clkfbout false
-dyn_mdiv_sel false
-mdiv_sel 24
-mdiv_frac_sel 0
