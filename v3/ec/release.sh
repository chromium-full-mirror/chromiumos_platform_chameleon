#!/bin/bash
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This script simplifies the process of naming the Chameleon v3 EC binary
# and creating a manifest of the git hashes that were part of that build.
# The script gathers the git tags and hashes for repos that are part of
# the Chameleon EC build, copies the binary to a name based on the public
# EC version tag, and creates a manifest text file with the tags/hashes.
# The new binary and the manifest are placed in ~/Downloads.
#
# The script does not run inside the chroot, because it needs to access
# directories both inside and outside the chroot, so it needs to know
# where you checked out the chroot filesystem. The script uses
# ~/chromiumos as the location of chroot by default, but you can override
# by setting the CHROOT environment variable, e.g. CHROOT=cros ./release.sh

set -e

# Detect if chroot and exit
if [[ -e /etc/cros_chroot_version ]]; then
  echo "Do not run this script inside the chroot."
  exit 1
fi

# Base directory for Chameleon v3
CHAMELEON=~/"${CHROOT:-chromiumos}"/src/platform/chameleon/v3
# Directory for the EC PKGBUILD
PKG="${CHAMELEON}"/alarm/ec-firmware-chameleonv3-bin

# Get the git tags for the public and private code
pushd "${CHAMELEON}"/ec
PUBLIC=$(git describe --tags)
popd
pushd "${CHAMELEON}"/ec/private/ite
PRIVATE=$(git describe --tags)
popd

# Get the hash for HEAD for Zephyr and the STM32 HAL
pushd ~/zephyrproject/zephyr
ZEPHYR=$(git log --oneline -n 1)
popd
pushd ~/zephyrproject/modules/hal/stm32
HAL=$(git log --oneline -n 1)
popd

# Get the hash for HEAD of Pigweed
pushd ~/chromiumos/src/third_party/pigweed
PIGWEED=$(git log --oneline -n 1)
popd

# Copy the EC binary to the package directory
cp ~/zephyrproject/build/zephyr/zephyr.bin "${PKG}"/"${PUBLIC}".bin

# Create the manifest
cat <<EOF >"${PKG}"/"${PUBLIC}".txt
v3/ec build ${PUBLIC}
private/ite build ${PRIVATE}
zephyr ${ZEPHYR}
modules/hal/stm32 ${HAL}
pigweed ${PIGWEED}
EOF

pushd "${PKG}"

# Update the PKGBUILD
sed -i "s/_version=.*/_version=${PUBLIC}/g" PKGBUILD
sed -i "s/pkgrel=.*/pkgrel=1/g" PKGBUILD

SHA256SUM=$(sha256sum "${PUBLIC}".bin | awk '{print $1}')
sed -i "s/sha256sums=('.*/sha256sums=('${SHA256SUM}'/" PKGBUILD

git add PKGBUILD
pkgver="${PUBLIC//-/_}"
manifest=$(cat "${PUBLIC}".txt)
git commit -F- <<END_COMMIT_MSG
v3: alarm: ec: ${pkgver}-1

Uprev EC binary:
${manifest}

TEST=\`pacman -U\` resulting package
TEST=do a full boot, see no fresh errors
BUG=None
END_COMMIT_MSG
