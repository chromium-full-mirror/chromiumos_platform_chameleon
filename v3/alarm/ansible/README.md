# Chameleon v3 Ansible Scripts

The automation scripts in this folder have multiple purposes:
1. create an SD card image
2. atomically update a chameleon the officially supported way
3. modify/update running chameleons for experiments

The major use of these scripts is to generate a whole sd card image (Arch
Linux ARM based) from scratch. This is done by grabbing a generic arch linux
arm gzip, applying transforms (updating installing packages), then copying to a
partitioned image.

The above transforms can also be applied directly to an already setup chameleon.
This is desired in quick and dirty setups, but might yield an unstable system as
the updates are not stable (eg: you'll get an instantaneous snapshot of the all
packages, therefore they might not be tested to work for chameleon purposes,
unlike the regular official chameleon image releases. This might be handy if
one doesn't want to wait for an official chameleon release just to fix/try
fixing a tiny bug.

For the more scalable updates you'll want to use some of the latter playbooks
which update the whole chameleon in an atomic matter using a whole btrfs
snapshot payload (which is similar to dding a fresh sd card every time,
without needing to manually handle SD cards). The `update.py` script wraps
those paybooks into something that's easy to invoke. **If you're a user just
wondering how to update your chameleon, you're probably looking for this**:

```
./update.py --payload /tmp/chameleon_270_2_2023-01-18T04:36:00Z-v3-77-g7dee263.btrfs.zst chromeos8-row16-rack10-host9003-chameleon
```

The "upstream" of some of these files is https://github.com/amstan/alarm-ansible,
they might eventually diverge though.

## Dependencies

* [Ansible](https://docs.ansible.com/ansible/latest/)
* qemu-user-static in order to
  [chroot from x86 into an arm system](https://wiki.archlinux.org/title/QEMU#Chrooting_into_arm/arm64_environment_from_x86_64).
* [arch-chroot](https://man.archlinux.org/man/arch-chroot.8) in $PATH from
  package [arch-install-scripts](https://archlinux.org/packages/extra/any/arch-install-scripts/).

### Arch Linux

```bash
pikaur -S ansible qemu-user-static binfmt-qemu-static arch-install-scripts
```

### Debian / glinux

```bash
sudo apt-get install ansible qemu-user-static arch-install-scripts
```

## How to run

Define your inventory (at least for the machine settings), see
inventory_template.yml for more details on how or where to put them.

```bash
alarm/ansible% sudo ansible-playbook -i inventory.yml *.play*.yml -v
```

This will create an operating system image containing the *latest*
[Arch Linux ARM packages](https://archlinuxarm.org/packages),
our *latest* [chameleon package binaries](https://console.cloud.google.com/storage/browser/chromeos-hardware-tools-chameleon-v3/pkg)
and tip of tree [chameleon git repo](https://chromium.googlesource.com/chromiumos/platform/chameleon/)
(containing `v3/chameleond/`). It is impossible to be able to pick and choose
component versions, you only get the latest (which we may or may not have direct
control of) at that snapshot in time, please make sure you test the result.

Once you have an sd card image produced, dd it to an sd card, then boot it
on a real chameleon and adjust the end of `inventory.yml` with the new
"chameleon" host.

### Tags

After the first successful run, you can probably narrow the `--tags` you're
running, some might be desired to be ran standalone. You can also `--skip-tags`.
`--list-tags` will give you a complete list of how plays are tagged.
Some tags of interest:

* `check_intermediate` - gets a list of intermediate/ prebuilt files that are
  required for other tasks
* `chroot_aquire` - creates chroot. It won't clobber it if already there,
  but should be skipped in order to save time if it is.
* `chroot_inventory` - if you already have a chroot setup, this is required
  (add as the first task in the arguments) to add the "chroot" host to the ram
  based inventory so other tasks can operate on it.
* `update` - various updates: arch packages, kernel, fpga binaries,
  chameleond git repo, ec
* `chameleon` - anything tagged with this is our application specific stuff
  that's extra from "upstream"
* `chameleon_sd` - creates sd card image from chroot
* `chameleon_device` - tasks that can be ran on any chameleon installation
  (either a chroot or a real device)
* `ec` - installing and flashing ec

## GPG Checking

These `chroot_aquire` tasks will check validity of the archlinuxarm archive
(that it can only download over http) using GPG. The signature accepted is
stored, checked in this folder, as `archlinuxarm.gpg`.

To verify it, compare `gpg archlinuxarm.gpg` output with
https://archlinuxarm.org/about/package-signing:

	% gpg archlinuxarm.gpg
	gpg: WARNING: no command supplied.  Trying to guess what you mean ...
	pub   rsa4096 2014-01-18 [SC]
	68B3537F39A313B3E574D06777193F152BDBE6A6
	uid           Arch Linux ARM Build System <builder@archlinuxarm.org>
	sub   rsa4096 2014-01-18 [E]
