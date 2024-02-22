# Chameleon v3 Setup, Deployment, and Testing

## Introduction

This document describes how to setup and deploy a Chameleon v3 board and run
tests using the Chameleon's functionality.

## Assembly

The chameleon you’ll receive will already be fully assembled and tested from the
factory. If you want to know more how it was done please see these documents:

* [Chameleon v3 MP assembly procedures](https://docs.google.com/document/d/1GVIqZ973fyB0hlUPlIMU3fyiEt8tiz9F5t0-aJ8f2SU/edit?resourcekey=0-U4SWy_EIamq99Z8LoEbF9g#)
* [Chameleon MP Factory Testing/QC](https://docs.google.com/document/d/1JdqHpLidfScXoSIuA8tCYHAM1mrGhk99B0y4CfXG2ao/edit#)

### Install the FPGA module

You’ll probably skip this if you have an MP chameleon.

**Power off the Chameleon v3 before installing the FPGA module.**

Line up the FPGA module's connectors with the connectors on the Chameleon v3.
Press down firmly and evenly.
Connect the fan power cable to the 3-pin connector near the power jack.

![Assembled Chameleon with module on it](doc/images/chameleon-assembled.jpg)

## How to tell what FPGA module you have

Look for a sticker on the heatsink or on the underside of the module, either
something about {270k, 480k} or a longer number starting with `EN`.

| Product number | Type    | Frequently found on | Chameleon/Uboot filenames |
| -------------- | ------- | ------------------- | ------------------------- |
| EN101917       | 480-2I3 | Proto 2             | 480_2                     |
| EN104218       | 480-2I3 | Proto 2             | 480_2                     |
| EN104216       | 270-3E4 | Proto 2 - late      | 270_3                     |
| EN104217       | 270-2I2 | PVT/MP              | 270_2                     |

## How to tell what chameleon version you have
<span style="color:red">**Proto 2(red)**</span> vs
<span style="color:#FB1">**PVT(yellow)**</span> vs
<span style="color:#FB1">**PVT-2/MP(yellow)**</span>.

Board color is an obvious way, but there’s also the full name on the board.

All boards PVT and onwards are interchangeable, so if you have a
<span style="color:#FB1">**yellow**</span> board you’re good.

![Chameleon Proto 2](doc/images/chameleon-proto2.jpg)

![Chameleon PVT](doc/images/chameleon-pvt.jpg)

**MP boards are labeled as PVT-2:**

![Chameleon PVT2/MP](doc/images/chameleon-pvt2.jpg)

## MAC Address / Serial Number

Each MP board should have the unique FPGA module serial number and MAC address
(also encoded as a QR code) on a sticker on the ethernet port:

![Chameleon Ethernet Port showing MAC sticker](doc/images/chameleon-mac.jpg)

## Prepare the SD Card

1. Download the latest SD card image (`.img.tar.zst`) from the
[cloud bucket img/ folder](https://console.cloud.google.com/storage/browser/chromeos-hardware-tools-chameleon-v3/img);
select `270_2`, `270_3` or `480_2`, depending on
which FPGA module you have ([see above](#how-to-tell-what-fpga-module-you-have))

2. Untar the file with `tar xf`

3. Insert the microSD card into your computer

    a) Take note of the device name: `/dev/sda` or `/dev/mmcblk0` or something
    else (use `lsblk` to figure out which one)

4. Write the image to the card

    ```bash
    sudo dd if=chameleon_480_2.img of=/dev/mmcblk0 bs=1M status=progress oflag=direct conv=fsync
    ```

5. Eject the microSD card

## Using Chameleon v3 as an SD card adapter

If your computer does not have an SD card adapter, you can use the the
Chameleon v3 as an SD card adapter:

1. Power on the Chameleon board
2. Start a serial terminal for the EC console, e.g.
`pyserial-miniterm /dev/ttyUSB0 115200 --raw`
3. Turn off fpga with `fpga off`
4. Disconnect the SD card from the FPGA with `sd off`
5. Connect the SD card to the PC with `sd usb`
6. Proceed as [above to prepare the sd card](#prepare-the-sd-card)
7. Disconnect the SD card from the PC with `sd off`
8. Connect the SD card to the FPGA with `sd fpga`
9. Turn on fpga with `fpga on`

## SSH using ChromeOS Public Test Keys

To access Chameleon, you need to have the ChromeOS SSH test keys installed
on your local machine.

1. Download the keys from [the chromite repository](https://chromium.googlesource.com/chromiumos/chromite/+/HEAD/ssh_keys)
into your `~/.ssh`

2. Change the file permissions: `chmod 600 ~/.ssh/testing_rsa`

3. Connect to the Chameleon by running (create one if the `cros` user is not existed yet)

    ```bash
    ssh -i ~/.ssh/testing_rsa cros@${CHAMELEON_IP}
    ```

Note: root account is not reachable directly via ssh for security reasons.
ssh as the normal user first then use `su` or `sudo`.

## Boot the Linux System

1. Insert the microSD card into the slot on the Chameleon board

2. Plug in ethernet cable

3. Apply 12V power

4. Start a serial terminal for the FPGA console,
e.g. `pyserial-miniterm /dev/ttyUSB1 115200 --raw`

5. As Chameleon reaches the login prompt, it will display its IP address(es);
make note of these. Alternative is to set a static dhcp lease in your router
based on chameleon’s [mac address](#mac-address-serial-number).

6. After Chameleon reaches the login prompt, exit the console (`Ctrl`+`]`
in `pyserial-miniterm`)

7. SSH in with the instructions above.

8. Follow steps 1-3 of the next [Update](#Update) section to complete the
install. **This is important** as there are stateful components of chameleon
that do not reside of the SD card (ex: EC firmware), only this step
will handle those.

9. In rare cases, one can login over serial into the device using username:
`root` password: `root` if ssh/networking does not work.

## Update

1. For the steps here you’ll need ansible to be installed (Probably a
`sudo apt-get install ansible` away)

2. Navigate to `~/chromiumos/src/platform/chameleon` folder outside the chroot

3. If you just dd’d a new sd card image, run:

    ```bash
    v3/alarm/ansible/update.py --oobe_only your_chameleon_ip
    ```

4. If you don’t have the latest chameleon install

    a) download a fresh update payload (`*.btrfs.zst`) from the
    [cloud bucket updates/ folder](https://console.cloud.google.com/storage/browser/chromeos-hardware-tools-chameleon-v3/updates)

    b) run:

        ```
        v3/alarm/ansible/update.py --payload new_update.btrfs.zst your_chameleon_ip
        ```

## Interact with chameleond directly

1. Navigate to `~/chromiumos/src/platform/chameleon` folder outside the chroot

2. `./v3/clients/screenshot --chameleon_host your_chameleon_ip --port_id 2`

    a) If your chameleon is in the office/lab, due to corporate firewall restrictions (see [go/corp-ssh-helper](http://go/corp-ssh-helper) and [go/chromeos-lab-duts-ssh](http://go/chromeos-lab-duts-ssh)), you need to use ssh tunneling

    b) In one terminal, `ssh -i ~/.ssh/testing_rsa cros@your_chameleon_ip -L 9992:localhost:9992`

    c) In a second terminal, `./v3/clients/screenshot --chameleon_host localhost --port_id 2`

### Manage chameleond daemon

Chameleond is managed by a systemd service.

Restart: `sudo systemctl restart chameleond`

Check logs: `journalctl -e -f -u chameleond`

### Run Autotest Tests in chroot

1. Use `ping`, `ssh`, or another method to ensure that the host, the DUT, and
the Chameleon can communicate with each other over the network
2. Connect the HDMI or DisplayPort cable(s) between the DUT and the Chameleon
3. Ensure you have ToT checked out and that DUT test image is also the same
version
4. Define the following environment variables:

    * `BOARD`
    * `DUT_IP`
    * `CHAMELEON_IP`
    * `TEST_NAME`

5. `TEST_NAME` can be one of the following:

    * `display_Resolution.extended`
    * `display_Resolution.mirrored`
    * `display_Resolution.suspend_resume`
    * `display_Resolution.reboot`
    * `display_HotPlugAtBoot.extended`
    * `display_HotPlugAtBoot.mirrored`
    * `display_HotPlugAtSuspend.extended`
    * `display_HotPlugAtSuspend.mirrored`
    * `display_ResolutionList.extended`

6. Run the test:
`test_that --board=$BOARD --args "chameleon_host=$CHAMELEON_IP" $DUT_IP $TEST_NAME`
