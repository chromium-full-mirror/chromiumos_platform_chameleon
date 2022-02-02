# linux-enclustra

This PKGBUILD (similar to an ebuild on gentoo) generated an Arch Linux ARM
package for the kernel needed on chameleon v3.

## Maintaining

Edit PKGBUILD's `_commit` variable to point at a new commit in the chromeos
kernel repo (though it can probably be set to a branch name once stuff
stabilizes).

Make sure you increment `pkgrel` every time the files produced are different
(either due to the source changing or due to the PKGBUILD/config being updated).

Occasionally you might need to update the `config`. This can be done by
temporarily uncommenting `make menuconfig`, doing changes, and saving the
resulting file as ../config. At that point the `config` file's md5sums
needs to be updated.

md5sums for the whole package can be regenerated using `makepkg -g`. Warning:
set the one for the .tar.gz from chromium.googlesource.com to `'SKIP'` since
the file downloaded never sums to the same thing repeatedly. `--skipinteg` as a
makepkg flag can be used during development so the checksum generation doesn't
get annoying.

## Compiling

You will need an Arch Linux system to run `makepkg`. Chameleon itself counts,
but could take forever (at least without distcc delegation to an x86 compiler).

```
makepkg -s
```

If you do not have an Arch Linux instance anywhere, https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#From_a_host_running_another_Linux_distribution
might be handy. In the future this part might be eased by more ansible scripts.

If you're on an x86 system you need to use a cross-compiler and will need to
provide more flags in front of makepkg:

```
CROSS_COMPILE='/usr/local/x-tools7h/arm-unknown-linux-gnueabihf/bin/' ARCH='arm' CARCH="armv7h" makepkg -s
```

A known working crosscompiler can be aquired the [archlinuxarm way](https://archlinuxarm.org/wiki/Distcc_Cross-Compiling)
(click on [ARMv7l hard-float](https://archlinuxarm.org/builder/xtools/x-tools7h.tar.xz)).
In theory the Chrome OS cross compiler can work too (since we use this all day
for the same stuff), but is untested.

## Installing

The makepkg invocation will result in a few packages (`*.pkg*`) in the current
folder, install them with `pacman -U` on a chameleon (or use the ansible
scripts).

Warning: linux-enclustra-mercury_aa1 will conflict linux-enclustra-chameleonv3,
only install one of them depending on what you want to use your AA1 module for
(vanilla or with chameleon things). Only difference between them is the dts
loaded.
