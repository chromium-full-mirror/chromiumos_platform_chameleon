# Update

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

    **NOTE:**
    Make sure that your filename starts with `chameleon`. If it start with
    `updates_`, remove this prefix. Otherwise, the update process can fail.

    b) run:
    ```
    v3/alarm/ansible/update.py --payload new_update.btrfs.zst your_chameleon_ip
    ```

    **NOTE**

    If your update process is stuck on the `Rebooting to new subvolume`,
    you may need to remove the cached SSH keys for the chameleon board in
    the `~/.ssh/known_hosts` file.
    This can be done using the command:

    `ssh-keygen -R your_chameleon_ip`

    You should execute this in a separate shell without stopping the update process.
    After removing the entries, the updater will ask if you want to
    continue connecting to the new host.
    You have to write “yes” and press enter to continue.
