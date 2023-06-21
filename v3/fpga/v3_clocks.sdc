# Copyright 2021 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# NOTE: This file does not containall timing constraints that are used in the project.
# Timing constraints are applied via set_instance_assignment method.
#
# See 'set_timing_constraints' in create_bitstream.tcl file
# for all timing constraints applied in the project.

create_clock -period "150 MHz" -name IT68051_PCLK [get_ports IT68051_PCLK] -waveform { 1.667 5 }
create_clock -period "150 MHz" -name IT68051_PCLK_VIRT

create_clock -period "135MHz" -name xcvr_ref_clk_dp   [get_ports DP_REFCLK_P]
create_clock -period "100MHz" -name xcvr_ref_clk_hdmi [get_ports PCIE_HDMI_REFCLKB_P]

derive_clock_uncertainty

# Create generated clocks for Display Port                                                               
create_generated_clock -name clk_cal -source {*u_dp_rx*|clk_cal|clk} -divide_by 2 {*u_dp_rx*|clk_cal|q}
                                                                                                         
# Get the clocks from the different PLLs                                                                 
derive_pll_clocks -create_base_clocks

# RX Aux Out and RX Aux OE                                                                               
set_false_path -to [get_ports DP213_SOMP1_AUX_OUT]                                                       
set_false_path -to [get_ports DP213_SOMP1_AUX_OE]                                                        
# RX HPD                                                                                                 
set_false_path -to [get_ports DP213_SOMP1_HPD]                                                           
                                                                                                         
# constraints for DCFIFO's in whole project                                                              
# write to read                                                                                          
set_false_path -from [get_registers {*dcfifo*delayed_wrptr_g[*]}] -to [get_registers {*dcfifo*rs_dgwp*}] 
# read to write                                                                                          
set_false_path -from [get_registers {*dcfifo*rdptr_g[*]}] -to [get_registers {*dcfifo*ws_dgrp*}] 
# avalon_clk is 250MHz
set avalon_clk [get_clocks -nocase *s2f_user0_clk*]
# config clk is 100MHz
set config_clk [get_clocks -nocase *s2f_user1_clk*]
# dp_aux_clk is 16MHz
set dp_aux_clk [get_clocks -nocase *u_pll_aux*aux_clk*]

# constraints for DCFIFO's in whole project
# write to read
set_false_path -from [get_registers {*dcfifo*delayed_wrptr_g[*]}] -to [get_registers {*dcfifo*rs_dgwp*}]
# read to write
set_false_path -from [get_registers {*dcfifo*rdptr_g[*]}] -to [get_registers {*dcfifo*ws_dgrp*}]

set ports [get_ports {IT68051_DE IT68051_HSYNC IT68051_QD* IT68051_SCDT IT68051_VSYNC}]

# Below values are based on IT68051 spec (table under figure 7.2) and path lenghts
# on Chameleon v3 proto2.
# Equation used to calculate values was taken from AN433 Altera doc (page 46, equations 25 and 26)
# Example (for max delay on rising edge:
# Data: unit interval = 6.667/2 = 3.333, Tsu = 1.22, path delay = +/- 0.070:
# input_delay = 3.334 - 1.22 + 0.07 = 2.184
set_input_delay -clock [get_clocks IT68051_PCLK_VIRT] -max 2.184 [get_ports {IT68051_DE IT68051_HSYNC IT68051_QD* IT68051_SCDT IT68051_VSYNC}]
set_input_delay -clock [get_clocks IT68051_PCLK_VIRT] -max 1.986 -clock_fall -add_delay [get_ports {IT68051_DE IT68051_HSYNC IT68051_QD* IT68051_SCDT IT68051_VSYNC}]
set_input_delay -clock [get_clocks IT68051_PCLK_VIRT] -min 0.93 -add_delay [get_ports {IT68051_DE IT68051_HSYNC IT68051_QD* IT68051_SCDT IT68051_VSYNC}]
set_input_delay -clock [get_clocks IT68051_PCLK_VIRT] -min 0.77 -clock_fall -add_delay [get_ports {IT68051_DE IT68051_HSYNC IT68051_QD* IT68051_SCDT IT68051_VSYNC}]

set_false_path -fall_from IT68051_PCLK_VIRT -rise_to IT68051_PCLK
set_false_path -rise_from IT68051_PCLK_VIRT -fall_to IT68051_PCLK

# Set clock groups of PCLK and main system clock to asynchronous
set_clock_groups -asynchronous -group { IT68051_PCLK } -group ${avalon_clk}
set_clock_groups -asynchronous -group ${avalon_clk} -group ${config_clk}
set_clock_groups -asynchronous -group ${avalon_clk} -group ${dp_aux_clk}

# HDMI
## *********************************************************************************
## I2C
## *********************************************************************************
create_clock -name {rx_i2c_clk_p1} -period "400Khz" [get_ports SOMP1_IN_DDC_SCL]
set_input_delay -clock [get_clocks rx_i2c_clk_p1] 100.000 [get_ports SOMP1_IN_DDC_SDA]
set_output_delay -clock [get_clocks rx_i2c_clk_p1] 100 [get_ports SOMP1_IN_DDC_SDA]

create_clock -name {rx_i2c_clk_p2} -period "400Khz" [get_ports SOMP2_IN_DDC_SCL]
set_input_delay -clock [get_clocks rx_i2c_clk_p2] 100.000 [get_ports SOMP2_IN_DDC_SDA]
set_output_delay -clock [get_clocks rx_i2c_clk_p2] 100 [get_ports SOMP2_IN_DDC_SDA]
## *********************************************************************************
## False paths
## *********************************************************************************
# I2C serial clocks are asynchronous to other domains
set_clock_groups -exclusive -group [get_clocks rx_i2c_clk_p1]
set_clock_groups -exclusive -group [get_clocks rx_i2c_clk_p2]

# No timing requirement to the hpd pins and +5V pin.
set_false_path -to {get_ports DP213_SOMP2_HPD}

set_false_path -from [get_keepers {*u_state_machine|set_locktoref*}]
# bitec rx locked signal
set_false_path -from [get_keepers {*u_state_machine*enable_measure}]
set_false_path -from [get_keepers {*u_rate_detect*count_refclock[*]}] -to [get_keepers {*u_rate_detect*refclock_measure_min2[*]}]
set_false_path -from [get_keepers {*u_rate_detect*gate}] -to [get_keepers {*u_rate_detect*gate_min2}]
set_false_path -from [get_keepers {*u_rate_detect*capture}] -to [get_keepers {*u_rate_detect*capture_d}]
set_false_path -from [get_keepers {*u_rate_detect*sig_o_reg}] -to [get_keepers {*u_rate_detect*sig_o_d}]
