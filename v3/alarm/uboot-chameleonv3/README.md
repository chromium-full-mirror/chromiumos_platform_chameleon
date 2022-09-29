# uboot-chameleonv3

This PKGBUILD generates an Arch Linux ARM package for the custom u-boot
needed on chameleon v3.

See parent folder's README for general PKGBUILD instructions.

## FPGA_TYPE

The environmental variable `FPGA_TYPE` can be can be defined before makepkg in
order to steer which of the fpga types the u-boot will be built for.

```
FPGA_TYPE="270_3" CROSS_COMPILE='/usr/local/x-tools7h/arm-unknown-linux-gnueabihf/bin/' ARCH='arm' CARCH="armv7h" makepkg -s
```

If you're in the process of doing a new chameleon release you might need to do
build this package multiple times, one for each FPGA type.

The possible options can be found based on what device trees are available in
u-boot:

```
alarm/uboot-chameleonv3% ls src/arch/arm/dts/socfpga_arria10_chameleonv3_*.dts
src/arch/arm/dts/socfpga_arria10_chameleonv3_270_2.dts
src/arch/arm/dts/socfpga_arria10_chameleonv3_270_3.dts
src/arch/arm/dts/socfpga_arria10_chameleonv3_480_2.dts
```
