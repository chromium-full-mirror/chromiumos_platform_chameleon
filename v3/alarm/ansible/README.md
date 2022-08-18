# Arch Linux ARM Ansible Scripts

Used to generate a whole sd card image (Arch Linux ARM based) for a chameleon v3.

The scripts can also be used to maintain/update current installs.

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
sudo apt-get install ansible qemu-user-static arch-install-scripts arch-install-scripts
```

## How to run

Define your inventory (at least for the machine settings), see
inventory_template.yml for more details on how or where to put them.

```bash
alarm/ansible% sudo ansible-playbook -i inventory.yml *.play*.yml -v
```

Make sure you have the prerequisite files in `intermediate/`, you might find
those in the Golden Images folder, here's an example of what I have in there:

* `2022-02-09-ec.bin`

It will also try looking for chameleon binary packages in each of the other
non-ansible folders in alarm/. Make sure they exist or ansible will
remind you pretty early.

Once you have an sd card image produced, dd it to an sd card, then boot it
on a real chameleon and adjust the end of `inventory.yml` with the new
"chameleon" host so you can finish the `ec` flashing tasks (see next
section on how to restrict the tasks to just that tag).

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
* `ec` - flashing ec

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
