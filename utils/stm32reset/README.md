# Controlling the STM32 bootloader mode

The STM32 microcontroller has a built-in bootloader that is capable of
updating the user flash over USART1. See [AN2606](https://www.st.com/resource/en/application_note/cd00167594-stm32-microcontroller-system-memory-boot-mode-stmicroelectronics.pdf)
for details.

On the Chameleon v3, the signals needed to enter and exit bootloader mode
can be controlled over a USB connection. This document describes a utility
that resets the STM32 into bootloader or user flash mode.

## Programming the FT232R CBUS pins

On the Chameleon v3, the BOOT[1:0] and RST_L signals are connected to the
CBUS[2:0] pins on the FT232R. These pins must be programmed as GPIO; see
[Chameleon V3 Proto0 Care and Feeding](https://docs.google.com/document/d/1FLbBYnFnyNMxrkfr4W5RuQYUmugeA8nSk9sLeJXvNMw/edit#heading=h.bxuvxk482kbe)
document.

## Building stm32reset

`stm32reset` uses `libgpiod` to access the FT232R CBUS pins as GPIO pins from
user space.

Install `gpiod` and the development libraries.
```
$ sudo apt-get install gpiod libgpiod-dev
```

Use `gpiodetect` to verify that the libraries correctly detect the FT232R.

```
$ sudo gpiodetect
gpiochip0 [ftdi-cbus] (4 lines)
$ sudo gpioinfo 0
gpiochip0 - 4 lines:
    line   0:      unnamed       unused   input  active-high
    line   1:      unnamed       unused   input  active-high
    line   2:      unnamed       unused   input  active-high
    line   3:      unnamed       unused   input  active-high
```

Build `stm32reset`:
```
~/chromiumos/src/platform/chameleon/utils/stm32reset$ make
gcc -Wall -Wextra -g -std=gnu89 -o stm32reset stm32reset.c -l gpiod
```

## Resetting into bootloader mode

To reset the STM32 into bootloader mode, run `stm32reset --bootloader`. The
STM32 will remain in bootloader mode until it is reset (or power cycled).

```
$ sudo ./stm32reset --bootloader
$ stm32flash /dev/ttyUSB0
stm32flash 0.5

http://stm32flash.sourceforge.net/

Interface serial_posix: 57600 8E1
Version      : 0x30
Option 1     : 0x00
Option 2     : 0x00
Device ID    : 0x0430 (STM32F10xxx XL-density)
- RAM        : 96KiB  (2048b reserved by bootloader)
- Flash      : 1024KiB (size first sector: 2x2048)
- Option RAM : 16b
- System RAM : 6KiB
```

## Resetting into user flash mode

`stm32flash` expects to communicate with the flash bootloader. When the program
in user flash is running, `stm32flash` will report a failure to initialize.

```
$ sudo ./stm32reset --user
$ stm32flash /dev/ttyUSB0
stm32flash 0.5

http://stm32flash.sourceforge.net/

Interface serial_posix: 57600 8E1
Failed to init device.
```

## Multiple FT232R devices

If you have more than one FT232R plugged into your computer, determine which
device is the Chameleon v3. It should have entries in `/dev` for `ttyUSB`**n**
and `gpiochip`**n**. The **n** is the device number to pass to `stm32reset`
with the `-d` or `--device` option.
