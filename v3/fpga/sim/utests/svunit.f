# SVUnit framework uses this file to get all sources required for simulation.
# See http://agilesoc.com/open-source-projects/svunit/svunit-user-guide/#AddingFiles_For_Simulation
# for more information.

-mfcu
-sv
-timescale 1ns/1ps
-svinputport=var
-suppress vlog-2643
-suppress vlog-2583

-F $CHAMELEON_DIR/rtl/filelist.f

$CHAMELEON_VIPS_DIR/common/gclk_if.sv
$CHAMELEON_VIPS_DIR/common/greporter_pkg.sv

-F $CHAMELEON_DIR/sim/vips/i2s_vip/sv/filelist.f
-F $CHAMELEON_VIPS_DIR/filelist.f
$CHAMELEON_VIPS_DIR/common/svunit_greporter_pkg.sv

$CHAMELEON_DIR/sim/utests/gvip_reg_pkg.sv
$CHAMELEON_DIR/sim/utests/frame_pkg.sv
$CHAMELEON_DIR/sim/utests/pixel_vip.sv
