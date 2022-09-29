# linux-enclustra

This PKGBUILD generates an Arch Linux ARM package for the custom kernel
needed on chameleon v3.

See parent folder's README for general PKGBUILD instructions.

## Maintaining

Occasionally you might need to update the `config`. This can be done by
temporarily uncommenting `make menuconfig` from the PKGBUILD, doing changes,
and saving the resulting file as `../config`. At that point the
`config` file's entry in the `sha256sums=` array needs to be updated
(`makepkg -g` can help).
