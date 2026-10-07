# I2S2 native-rate clock, generated for revision C by Gowin EDA 1.9.11.03.
# PLL formulas: UG306 5.1. New VCOs: 1200 MHz and 768 MHz, respectively.
# Reference: 50 * 24 / 50 = 24 MHz.
# Audio: 24 * 32 / 62.5 = 12.288 MHz (256 * 48000 Hz).
# 44.1 kHz: 24 * 36.75 / 78.125 = 11.2896 MHz, VCO 882 MHz.
# Dynamic selectors use 128 minus the integer and 7 minus the eighth fraction.
# Update selectors only while RESET is asserted.
-series GW5AST
-device GW5AST-138
-device_version C
-package PBGA484A
-part_number GW5AST-LV138PG484AC1/I0

-mod_name pll_i2s2_audio
-file_name pll_i2s2_audio
-path @OUTPUT_DIR@/
-type PLL_ADV
-file_type vlg
-ip_version 1.0
-ssc false
-clock_en false
-rst true
-rst_pwd false
-rst_i false
-rst_o false
-fclkin 24
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
-dyn_odiv0_sel true
-odiv0_sel 62
-odiv0_frac_sel 4
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
-dyn_mdiv_sel true
-mdiv_sel 32
-mdiv_frac_sel 0
