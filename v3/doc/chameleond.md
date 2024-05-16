# Interact with chameleond directly

1. Navigate to `~/chromiumos/src/platform/chameleon` folder outside the chroot

2. `./v3/clients/screenshot --chameleon_host your_chameleon_ip --port_id 2`

    a) If your chameleon is in the office/lab, due to corporate firewall restrictions (see [go/corp-ssh-helper](http://go/corp-ssh-helper) and [go/chromeos-lab-duts-ssh](http://go/chromeos-lab-duts-ssh)), you need to use ssh tunneling

    b) In one terminal, `ssh -i ~/.ssh/testing_rsa cros@your_chameleon_ip -L 9992:localhost:9992`

    c) In a second terminal, `./v3/clients/screenshot --chameleon_host localhost --port_id 2`

# Manage chameleond daemon

Chameleond is managed by a systemd service.

Restart: `sudo systemctl restart chameleond`

Check logs: `journalctl -e -f -u chameleond`

# Run Autotest Tests in chroot

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
