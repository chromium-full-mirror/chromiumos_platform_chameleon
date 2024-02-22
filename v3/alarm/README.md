# Chameleon v3 Arch Linux ARM OS

In this folder you will find all that's necessary to build an OS for
Chameleon v3. This OS is based on Arch Linux ARM.

## Components

The **ansible/** folder contains higher level build automation on how to put
everything together and create an image. This is similar to `build_image`
from ChromeOS.

The other folders represent individual custom **packages** that Chameleon uses.
Each of those packages contain a [PKGBUILD](https://wiki.archlinux.org/title/PKGBUILD)
file, containing instructions on how to build a package, similar to Gentoo's
ebuild files.

Finally, chameleond (sourced via the grandparent folder) is available to
chameleon devices as a git cloned folder in `~cros/chameleon/` on each
chameleon device. This allows quick iteraction on the high level code
without needing to manually deploy each update.

## Ansible

The ansible automation playbooks are used to create, maintain and update
any kind of Chameleon v3 OS deployment. See [ansible/README.md](ansible/README.md)
for more details.

## PKGBUILDs

### Maintaining

Edit PKGBUILD's `_commit` variable to point at a new commit from gerrit,
preferably something that's already landed via the CQ as opposed to a WIP patch.

If this is a binary package, you probably need to adjust its `_version` or
`pkgver` directly.

Make sure you [increment](https://wiki.archlinux.org/title/PKGBUILD#Version)
the (`pkgver`-`pkgrel`) tuple every time the resulting output files are
different (probably when anything in the package folder is
touched) as this will be able to let users know they should update. You don't
want to have the 2 packages with the same version number that have different
behavior.

sha256sums for the whole package can be regenerated using `makepkg -g`. Warning:
set the ones for the .tar.gz from chromium.googlesource.com to `'SKIP'` since
the file downloaded never sums to the same thing repeatedly. `--skipinteg` as a
makepkg flag can be used during development so the checksum generation doesn't
get annoying.

### Compiling

You will need an Arch Linux system to run [makepkg](https://wiki.archlinux.org/title/Makepkg).
Chameleon itself counts, but could take **a long time** for packages that are
more compile heavy (at least without [distcc](https://archlinuxarm.org/wiki/Distcc_Cross-Compiling)
delegation to a compiler running on a beefy x86 workstation).

```
makepkg -s
```

If you do not have an Arch Linux instance, https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#From_a_host_running_another_Linux_distribution
might be handy. In the future this part might be eased by more ansible scripts.

If you're on an x86 system you need to use a cross-compiler and will need to
provide more flags in front of makepkg:

```
CROSS_COMPILE='/usr/local/x-tools7h/arm-unknown-linux-gnueabihf/bin/' ARCH='arm' CARCH="armv7h" makepkg -s
```

A known working crosscompiler can be aquired the [archlinuxarm way](https://archlinuxarm.org/wiki/Distcc_Cross-Compiling)
(click on [ARMv7l hard-float](https://archlinuxarm.org/builder/xtools/x-tools7h.tar.xz)).
In theory the Chrome OS cross compiler can work too, but is untested.

### Installing

The makepkg invocation will result in a few packages (`*.pkg*`) in the package
folder, upload them then install with `pacman -U` on a chameleon
(or use the ansible scripts)

### Publishing

The resulting packages `*.pkg*` files should be uploaded to our [storage bucket](https://console.cloud.google.com/storage/browser/chromeos-hardware-tools-chameleon-v3/pkg) where pacman will grab them
when creating an sd card image or when doing a hacky update
(eg `pikaur -Syu`) from a development chameleon.

Arch's [repo add](https://archlinux.org/pacman/repo-add.8.html) utility needs to
be rerun (`repo-add chameleon.db.tar.gz *.pkg*`) every time a new package is
added so the [database (aka package index)](https://storage.googleapis.com/chromeos-hardware-tools-chameleon-v3/pkg/chameleon.db.tar.gz)
gets updated. Additionally, due to the fact that google cloud console does not
support symlinks, the symlinks have to be emulated by making another copy of
the database files:

```
for f in $(find -type l); do cp --remove-destination $(readlink $f) $f; done
```
