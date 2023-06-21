# Copyright 2021 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Script used to configure project with various TCL settings.

package require ::quartus::project
package require ::quartus::flow

# From https://www.enclustra.com/en/products/system-on-chip-modules/mercury-aa1/#:~:text=Product%20Selection,Matrix
# ME-AA1-270-3E4-D11E (MVP, can't do DP/HDMI decoding)
# set_global_assignment -name DEVICE 10AS027E4F29E3LG
# ME-AA1-270-2I2-D11E (PVT/MP, most of the devices)
# set_global_assignment -name DEVICE 10AS027E2F29I2SG
# ME-AA1-480-2I3-D12E (MVP/development)
# set_global_assignment -name DEVICE 10AS048E3F29I2SG
set SUPPORTED_DEVICES [dict create 480-2 10AS048E3F29I2SG 270-3 10AS027E4F29E3LG 270-2 10AS027E2F29I2SG]
set RTL_FILELIST rtl/filelist.f

proc usage { devices } {
  puts " Set project settings and create bitstream for Chameleon v3."
  puts ""
  puts " Usage:"
  puts " -d|--device       - (required) device for which bitstream will be build."
  puts "                     Devices are accepted in format <number-of-kLUTs>-<speed_grade>."
  puts "                     Supported devices are: [dict keys $devices]"
  puts " -n|--name <name>  - (required) project name."
  puts " -D|--debug <stp>  - Signal Tap Logic Analyzer file to be used for debug."
  puts " -s|--skip-compile - Create project only, do not build bitstream."
  puts " -e|--early        - Enable early i/o release."
  puts " -h|--help         - print this message."
}

proc parse_args { argv devices } {
  set id -1

  set PARAMETERS [dict create]

  while { $id < [expr [llength $argv] - 1]} {

    set arg [lindex $argv [incr id]]
    switch -exact $arg {

      -d - --device {
        set opts($arg) [lindex $argv [incr id]]

        if { ![expr {$opts($arg) in [dict keys $devices]}] } {
          puts "Invalid device $opts($arg)"
          usage $devices
          exit 1
        }

        dict set PARAMETERS device [dict get $devices $opts($arg)]
        dict set PARAMETERS short_devname $opts($arg)
      }

      -n - --name {
        set opts($arg) [lindex $argv [incr id]]
        dict set PARAMETERS name $opts($arg)
      }

      -D - --debug {
        set opts($arg) [lindex $argv [incr id]]

        dict set PARAMETERS stp_file $opts($arg)
      }

      -s - --skip-compile {
        dict set PARAMETERS skip_compile 1
      }

      -e - --early {
        dict set PARAMETERS early 1
      }

      -h - --help {
        usage $devices
        exit
      }

      default {
        usage $devices
        exit 1
      }
    }
  }

  return $PARAMETERS
}

proc gerrit_change_id {} {
  try {
    set gerrit_id [exec git show | grep "Change-Id: I" | head -n 1 | cut -c 17-24]
    set status 0
  } trap CHILDSTATUS {results options} {
    set status [lindex [dict get $options -errorcode] 2]
  }

  return $gerrit_id
}

proc set_device { device } {
  set_global_assignment -name DEVICE $device
}

# Device-specific input delay chains for critical timing path in FPGA
proc set_input_delay_it68051 { device } {
  set delay_chain_it68051 0
  set auto_delay_chains ON

  if { $device == "10AS048E3F29I2SG" } {
    set delay_chain_it68051 20
    set auto_delay_chains OFF

    set_instance_assignment -name FAST_INPUT_REGISTER ON -to \
      u_ddr|core|i_loop[*].altera_gpio_bit_i|input_path.in_path_fr.buffer_data_in_fr_ddio \
      -entity v3_top
    set_instance_assignment -name FAST_INPUT_REGISTER ON -to *fb_ddio_d*  -entity v3_top
  }

  set_instance_assignment -name INPUT_DELAY_CHAIN $delay_chain_it68051 \
    -to IT68051_QD_* -entity v3_top
  set_instance_assignment -name INPUT_DELAY_CHAIN $delay_chain_it68051 \
    -to IT68051_DE -entity v3_top
  set_instance_assignment -name INPUT_DELAY_CHAIN $delay_chain_it68051 \
    -to IT68051_VSYNC -entity v3_top
  set_instance_assignment -name INPUT_DELAY_CHAIN $delay_chain_it68051 \
    -to IT68051_HSYNC -entity v3_top
  set_instance_assignment -name INPUT_DELAY_CHAIN $delay_chain_it68051 \
    -to IT68051_SCDT -entity v3_top
  set_global_assignment -name AUTO_DELAY_CHAINS $auto_delay_chains
}

proc add_qsys { device base_dir } {
  set_global_assignment -name QSYS_FILE $base_dir/qsys/$device/ap.qsys
}

proc add_gxb_ips { device base_dir } {
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/gxb_dp_rx/gxb_dp_rx.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/gxb_dp_rx/gxb_dp_rx_reset.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/gxb_hdmi_rx/gxb_hdmi_rx.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/gxb_hdmi_rx/gxb_hdmi_rx_reset.ip
}

proc add_display_port_ips { device base_dir } {
  set dp_path "$base_dir/qsys/$device/ip/dp_rx"
  set dp_example_path $dp_path/dp_0_example_design
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/dp_mgmt_irq.ip
  set_global_assignment -name IP_FILE $dp_path/pll_aux.ip
  set_global_assignment -name IP_FILE $dp_path/dp_rx.ip
  set_global_assignment -name IP_FILE $dp_path/dp_rx_sst.ip
  qexec "qsys-generate $dp_path/dp_rx_example.ip --example-design=all \
         --output-directory=$dp_path --family=\"Arria 10\" --part=$device"
  file copy -force $dp_example_path/rtl/bitec_reconfig_alt_a10.v $base_dir/rtl/bitec_reconfig_alt_a10.v
  file delete -force $dp_example_path
}

proc add_hdmi_ips { device base_dir } {
  set hdmi_path "$base_dir/qsys/$device/ip/hdmi_rx"
  set hdmi_example_path $hdmi_path/hdmi_0_example_design
  set_global_assignment -name IP_FILE $hdmi_path/clock_control.ip
  set_global_assignment -name IP_FILE $hdmi_path/pll_hdmi_reconfig.ip
  set_global_assignment -name IP_FILE $hdmi_path/pll_hdmi.ip
  set_global_assignment -name IP_FILE $hdmi_path/hdmi_rx.ip
  qexec "qsys-generate $hdmi_path/hdmi_rx.ip --example-design=all \
         --output-directory=$hdmi_path --family=\"Arria 10\" --part=$device"
  foreach f [glob -directory $hdmi_example_path/rtl/reconfig_mgmt -nocomplain *] {
    file copy -force $f $base_dir/rtl
  }
  file copy -force $hdmi_example_path/rtl/common/clock_crosser.v $base_dir/rtl/clock_crosser.v
  file copy -force $hdmi_example_path/rtl/hdmi_rx/symbol_aligner.v $base_dir/rtl/symbol_aligner.v
  file delete -force $hdmi_example_path
}

proc add_ips { device base_dir } {
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_axi_bridge_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_clock_bridge_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_reset_controller_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_config.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_emif_a10_hps_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_fb0_csr.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/fb0_irq.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_gpio_iobuf_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_i2s_it68051_csr.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_i2s_it68051_dma.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_i2s_ssm2603_csr.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_jtag_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_mm_bridge_0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_reset_bridge_0.ip
 	set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/i2s_it_irq0.ip
	set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/i2s_ssm_irq0.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_clock_bridge_1.ip
  set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_fb_ddio.ip
  if { $device == "10AS048E3F29I2SG" || $device == "10AS027E2F29I2SG" } {
    # Interconnects for DisplayPort integration
    set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_multiplexer_2x1.ip
    set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_multiplexer_4x1.ip

    # Add CDC AP for access to DP reconfiguration module
    set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_mm_cdc.ip

    # Add transceivers, DP and HDMI
    add_gxb_ips $device $base_dir
    add_hdmi_ips $device $base_dir
    add_display_port_ips $device $base_dir
  }

  if { $device == "10AS027E4F29E3LG" } {
    # only to ease timing requirements on 270-3
    set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_f2h_brigde.ip
    set_global_assignment -name IP_FILE $base_dir/qsys/$device/ip/ap/ap_i2s_ssm2603_dma.ip
  }
}

proc add_init_settings { project_dir base_dir } {
  set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
  set_global_assignment -name PROJECT_OUTPUT_DIRECTORY build
  set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
  set_global_assignment -name MAX_CORE_JUNCTION_TEMP 100
  set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 2
  set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
  set_global_assignment -name SYSTEMVERILOG_FILE $base_dir/v3_top.sv
  set_global_assignment -name TOP_LEVEL_ENTITY v3_top
  # do not use the CLKUSR configuration pin for calibration
  # set_location_assignment PIN_Y15 -to IO_B2A_L18_Y15_N
  set_global_assignment -name AUTO_RESERVE_CLKUSR_FOR_CALIBRATION OFF
  set_global_assignment -name ALLOW_ANY_SHIFT_REGISTER_SIZE_FOR_RECOGNITION ON
  set_global_assignment -name VERILOG_ALLOW_RAM_INFERRED_IN_GENERATE_LOOP ON
  set_global_assignment -name PLACEMENT_EFFORT_MULTIPLIER 2.0
  set_global_assignment -name OPTIMIZE_POWER_DURING_FITTING OFF
  set_global_assignment -name FINAL_PLACEMENT_OPTIMIZATION ALWAYS
  set_global_assignment -name FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS
  set_global_assignment -name FITTER_EFFORT "STANDARD FIT"

  # DATA0 configuration pin - for passive serial scheme
  set_global_assignment -name RESERVE_DATA0_AFTER_CONFIGURATION "USE AS REGULAR IO"
  # set_location_assignment PIN_AE10 -to IO_B2A_L1_AE10_N

  set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT WITH MAXIMUM PLACEMENT EFFORT"
}

proc set_seed { seed } {
  set_global_assignment -name SEED $seed
}

proc set_early_io_release {} {
  set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "PASSIVE SERIAL"
  set_global_assignment -name ACTIVE_SERIAL_CLOCK FREQ_100MHZ
  set_global_assignment -name HPS_EARLY_IO_RELEASE ON
}

proc add_rtl_sources { filelist } {
  set file_data [read [open $filelist r]]

  foreach line [split $file_data "\n"] {
    if {[string length $line] &&
        ![expr {[string first "+incdir+" $line] == 0 ||
                [string first "#" $line] == 0 ||
                [string first "-F" $line] == 0}]} {
        set_global_assignment -name SYSTEMVERILOG_FILE [file dirname $filelist]/${line}
    }
  }
}

proc add_constraints { base_dir } {
  set_global_assignment -name SDC_FILE $base_dir/v3_clocks.sdc
}

# Method to set device-specific timing constraints.
# Any assignment that constrains timing shall be set in this function.
proc set_timing_constraints { device } {
  # Update input delays on it68051
  set_input_delay_it68051 $device
}

proc add_fitter_assignements { } {
  set_instance_assignment -name PLACE_REGION "X77 Y45 X83 Y82" -to ap0|arria10_hps_0|fpga_interfaces|f2sdram|f2s_rl_adp_inst_0*dataw*wireluta*
  set_instance_assignment -name RESERVE_PLACE_REGION OFF -to ap0|arria10_hps_0|fpga_interfaces|f2sdram|f2s_rl_adp_inst_0*dataw*wireluta*
  set_instance_assignment -name CORE_ONLY_PLACE_REGION ON -to ap0|arria10_hps_0|fpga_interfaces|f2sdram|f2s_rl_adp_inst_0*dataw*wireluta*
  set_instance_assignment -name REGION_NAME "dataw_wireluta_fsdram0" -to ap0|arria10_hps_0|fpga_interfaces|f2sdram|f2s_rl_adp_inst_0*dataw*wireluta*
}

# Add debug
proc add_debug { stp_file } {
  set_global_assignment -name ENABLE_SIGNALTAP ON
  set_global_assignment -name USE_SIGNALTAP_FILE $stp_file
  set_global_assignment -name SIGNALTAP_FILE $stp_file
}

proc run_compile { cmd_args devices rtl_sources } {
  # Parse command line arguments
  set params [parse_args $cmd_args $devices]

  # Initial settings
  set guid [gerrit_change_id]
  set base_dir [file dirname [file normalize [info script]]]

  # Get device
  try {
    set current_device [dict get $params device]
  } on error {} {
    puts "Device not set."
    usage $devices
    exit 1
  }

  # Get name
  try {
    set project_name [dict get $params name]
  } on error {} {
    puts "Name not set."
    usage $devices
    exit 1
  }

  # Create a build directory for project
  set project_dir "quartus_project_$guid\_$current_device"
  file mkdir $project_dir

  # Copy v3.srf file to project directory to suppress/promote proper warnings
  file copy -force v3.srf $project_dir/$project_name.srf

  # Create and open project
  project_new -overwrite -family "Arria 10" $project_dir/$project_name
  project_open $project_name

  # Cleanup all VERILOG_MACROs
  set_global_assignment -name VERILOG_MACRO -remove

  # Add overall settings
  add_init_settings $project_dir $base_dir

  if { [dict exists $params early] } {
    set_early_io_release
  }

  # Add Platform Designer top design (qsys)
  add_qsys $current_device $base_dir

  # Add constraints
  add_constraints $base_dir

  # Set device
  set_device $current_device

  # Setup pin assignments
  source $base_dir/pin_settings.tcl

  # Add IP cores
  add_ips $current_device $base_dir

  # Add RTL sources
  add_rtl_sources $base_dir/$rtl_sources

  # Set CFG_GUID
  set_global_assignment -name VERILOG_MACRO "CFG_GUID=32'h$guid"

  # Set CHIP_ID
  set chip_id [lindex [split [dict get $params short_devname] "-"] 0]
  set speed_grade [lindex [split [dict get $params short_devname] "-"] 1]
  set_global_assignment -name VERILOG_MACRO "CFG_CHIP_ID={8'h0, 8'd$speed_grade, 16'd$chip_id}"

  # Set option for DP in-FPGA processing
  if { $current_device == "10AS048E3F29I2SG" || $current_device == "10AS027E2F29I2SG" } {
    set_global_assignment -name VERILOG_MACRO "CFG_DP_ENABLED=1"
  }

  # Set seed for fitter
  # Value of seed was picked to meet timing requirements on QD lines
  if { $current_device == "10AS048E3F29I2SG" } {
    set_seed 1
  } elseif { $current_device == "10AS027E4F29E3LG" } {
    set_seed 3
  }

  # Set (additional to SDC) timing constraints
  set_timing_constraints $current_device

  # Add fitter assignments - specific for chip to meet timing constraints
  if { $current_device == "10AS027E2F29I2SG" } {
    source $base_dir/v3_270-2_ram_assignments.tcl
    add_fitter_assignements
  }

  # Add debug (if required)
  if { [dict exists $params stp_file] } {
    set stp [dict get $params stp_file]
    add_debug $base_dir/$stp
  }

  if { ![dict exists $params skip_compile] } {
    # Create bitstream
    # TODO: Treat timing violations as error
    execute_flow -compile

    # Copy artifacts
    file copy $base_dir/$project_dir/build/$project_name.sof $base_dir/$project_name.sof
    file copy $base_dir/$project_dir/hps_isw_handoff/hps.xml $base_dir/${project_name}_hps.xml
  }

  # Close project - without it, QSF file won't be updated
  project_close
}

run_compile $argv $SUPPORTED_DEVICES $RTL_FILELIST

