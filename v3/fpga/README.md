# V3 Chameleon FPGA code

## Introduction

In this folder you'll find hardware code required for the fpga on chameleon.

## FPGA's job
The FPGA circuitry's job is to move large amount of video signals around.
* Input HDMI or DP via MGT-RX
* Input HDMI via parallel bits (a little easier) from the IT68051 (+free HDCP)
* Put it in ram for the embedded linux to grab it
* Output on usb gadget (Cypress FX3) (though we might delegate the whole
  FX3 to Linux instead)
* Expose SOM_AUD_* (the 3 analog audio ports) as an I2S controller to Linux
* Expose IT68051_I2S* as another I2S controller for audio coming from IT68051

See <http://go/chameleon-fpga-architecture> for more details.

## Files found here

* SystemVerilog RTL sources (.sv) to be found in rtl/
* SystemVerilog testbenches (.sv) to be found in sim/utests/
* `v3*.sv` describes the whole board
    * According to <http://go/verilog-style#standard-files>

### History

If you are a googler, you can access historical commits by accessing the
[internal repo](https://chrome-internal.googlesource.com/chromeos/platform/video-chameleon/+/main/v3/fpga).

### Register map

Register map is available at: [doc/register_map.md](doc/register_map.md)

## Building

Build system generates three different types of bitstream:
* `*.sof` - main bitstream with header
* `*.rbf` - bitstream stripped from Quartus header, ready to flash directly to SD/EMMC
* `*.itb` - U-Boot-friendly file format that U-Boot utilizes to program the FPGA.

Most of the time one will only need `*.itb` file.

### Prerequisites

Download and install Quartus Prime Pro 22.4 from
<https://www.intel.com/content/www/us/en/software-kit/764010/intel-quartus-prime-pro-edition-design-software-version-22-4-for-linux.html?>
To run Quartus, one will need a proper license - contact Chameleon team for access.

Make sure `quartus_sh` was added to the `PATH`. If not:
```
export PATH=${PATH}:<quartus_installation_dir>/quartus/bin
```

Install U-Boot utilities:
```
sudo apt install u-boot-tools
```

### Supported FPGAs

* Arria10 family
  * 10AS048E3F29I2SG - code name 480-2
  * 10AS027E2F29I2SG - code name 270-2
  * 10AS027E4F29E3LG - code name 270-3

### Build

To build bitstream for given chip, use `make bitstream FPGA_CHIP=<code name>`
Type `make help` for more information.

## Testing

`make tests` will run the tests for all SVUnit testbenches
defined in `sim/utests`.
Refer to [installation instruction](https://github.com/svunit/svunit#step-by-step-instructions-to-get-a-first-unit-test-going)
for run tests inside `sim/utests` directory.
Essentially, one need to run:

```
export SVUNIT_INSTALL=~/chromiumos/src/third_party/svunit
export PATH=${PATH}:${SVUNIT_INSTALL}/bin
```

Google's mirror of SVUnit repository can be found at `src/third_party/svunit`.
