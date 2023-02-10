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

# Get the git tags for the public and private code
pushd ~/"${CHROOT:-chromiumos}"/src/platform/chameleon/v3/ec
PUBLIC=$(git describe --tags)
popd
pushd ~/"${CHROOT:-chromiumos}"/src/platform/chameleon/v3/ec/private/ite
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

# Copy the EC binary to ~/Downloads/${PUBLIC}.bin
cp ~/zephyrproject/build/zephyr/zephyr.bin ~/Downloads/"${PUBLIC}".bin

# Create the manifest
cat <<EOF >~/Downloads/"${PUBLIC}".txt
v3/ec build ${PUBLIC}
private/ite build ${PRIVATE}
zephyr ${ZEPHYR}
modules/hal/stm32 ${HAL}
pigweed ${PIGWEED}
EOF

pushd ~/Downloads
ls -1 "${PUBLIC}".*
