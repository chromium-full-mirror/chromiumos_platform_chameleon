#!/bin/bash

# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Replaces the existing chameleond version on the btpeer(s) with the current
# local state of this repository to allow for quick testing of changes to
# chameleond.
#
# Note: This will only update the chameleond folder on the server and restart
# the service, it does not adjust packages. For testing it's recommend to do
# that type of thing manually.
#
# The btpeers' ImageUUID in its build info is updated with a `-needs-reinstall`
# suffix so that auto-repair re-images it, undoing these changes.
#
# For development purposes only. Normal deployments should still be bundled
# within images using pi-gen-btpeer.
#
# Specify a dut hostname to update all of its btpeers or btpeer hostname(s).
# Assumes anything ending in "-host\d+" to be a dut hostname, and its btpeers to
# be <dut_hostname>-btpeerN for N [1,4]. Attempts to ssh each host before
# any updates to validate access and hostname resolution, any hosts that failed
# are skipped. Fails if chameleond does not exist already on the host in the
# image-based install location.
#
# Usage:
# ./update_btpeers.sh <dut_or_btpeer_host1> [...<dut_or_btpeer_host1>]

set -e

SCRIPT_DIR="$(dirname "$(realpath -e "${BASH_SOURCE[0]}")")"
PROJECT_DIR="$(realpath -e "${SCRIPT_DIR}/..")"
BTPEER_PATH_TO_CHAMELEON_DIR="/etc/chromiumos/src/platform/chameleon/"
BTPEER_PATH_TO_BUILD_INFO_FILE="/etc/chromiumos/raspios_cros_btpeer_build_info.json"
DIRTY_IMAGE_UUID_SUFFIX="-needs-reinstall"
CHROOT_CHAMELEOND_DIR="/mnt/host/source/src/platform/chameleon"

# Collect hosts from script args.
HOSTS_TO_CHECK=()
for HOST in "$@"; do
  # Remove crossk prefix.
  HOST="${HOST#crossk-}"
  if [[ "${HOST}" =~ host[0-9]+$ ]]; then
    # Likely a DUT host, so add all btpeers.
    echo "Assuming host '${HOST}' is a dut hostname, will try to update its 4 btpeers"
    HOSTS_TO_CHECK+=(
      "${HOST}-btpeer1"
      "${HOST}-btpeer2"
      "${HOST}-btpeer3"
      "${HOST}-btpeer4"
    )
  else
    HOSTS_TO_CHECK+=("${HOST}")
  fi
done
if [ "${#HOSTS_TO_CHECK[@]}" -eq 0 ]; then
  echo "ERROR: At least one dut or btpeer hostname is required"
  exit 1
fi
echo "Got ${#HOSTS_TO_CHECK[@]} btpeer hostnames from CLI args"

# Validate hosts as btpeers.
BTPEER_HOSTS_TO_UPDATE=()
for HOST in "${HOSTS_TO_CHECK[@]}"; do
  echo "Checking if host '${HOST}' is a valid host to update"
  set +e
  ssh -q "${HOST}" "test -d ${BTPEER_PATH_TO_CHAMELEON_DIR}"
  SSH_RET_CODE=$?
  set -e
  if [ "${SSH_RET_CODE}" -eq 255 ]; then
    echo "WARNING: Failed to connect to host '${HOST}', assuming host does not exist and will not update it"
  elif [ "${SSH_RET_CODE}" -eq 1 ]; then
    echo "ERROR: Invalid host '${HOST}': missing chameleond install dir ${BTPEER_PATH_TO_CHAMELEON_DIR}"
    exit 1
  elif [ "${SSH_RET_CODE}" -ne 0 ]; then
    echo "ERROR: Failed to verify host '${HOST}' has chameleond install dir ${BTPEER_PATH_TO_CHAMELEON_DIR}"
    exit 2
  else
    echo "Successfully verified host '${HOST}' as a valid btpeer, will update it"
    BTPEER_HOSTS_TO_UPDATE+=("${HOST}")
  fi
done
if [ "${#BTPEER_HOSTS_TO_UPDATE[@]}" -eq 0 ]; then
  echo "ERROR: No valid btpeer hosts to update"
  exit 1
fi
echo "Successfully identified ${#BTPEER_HOSTS_TO_UPDATE[@]} btpeer hosts to update"

# Build chameleond bundle in chroot.
PACKAGE_CHAMELEOND="${PACKAGE_CHAMELEOND:-1}"
if [ "${PACKAGE_CHAMELEOND}" -eq 1 ]; then
  echo "Packaging chameleond in ChromeOS chroot (can be skipped with PACKAGE_CHAMELEOND=0)"
  cros_sdk --working-dir "${CHROOT_CHAMELEOND_DIR}" make
  echo "Successfully packaged chameleond in ChromeOS chroot at chameleon commit ${CHAMELEON_COMMIT}"
fi
CHAMELEOND_PROJECT_DIST_DIR="${PROJECT_DIR}/dist"
BUNDLE_EXTRACT_DIR="${CHAMELEOND_PROJECT_DIST_DIR}/extracted_bundle"
CHAMELEOND_BUNDLE_FILENAME=$(cd "${CHAMELEOND_PROJECT_DIST_DIR}" && find * -maxdepth 1 -type f -iname "chameleond-*.tar.gz")
CHAMELEOND_BUNDLE_PATH="${CHAMELEOND_PROJECT_DIST_DIR}/${CHAMELEOND_BUNDLE_FILENAME}"
if [ ! -f "${CHAMELEOND_BUNDLE_PATH}" ]; then
  echo "Error: No chameleond bundle found in '${CHAMELEOND_PROJECT_DIST_DIR}'"
  exit 1
fi
echo "Using chameleond bundle '${CHAMELEOND_BUNDLE_PATH}'"
if [ -d "${BUNDLE_EXTRACT_DIR}" ]; then
  echo "Removing previously extracted chameleond bundle at ${BUNDLE_EXTRACT_DIR}"
  rm -rf "${BUNDLE_EXTRACT_DIR}"
fi
echo "Extracting chameleond bundle locally into ${BUNDLE_EXTRACT_DIR}"
mkdir -p "${BUNDLE_EXTRACT_DIR}"
(cd "${BUNDLE_EXTRACT_DIR}" && \
tar -zxf "${CHAMELEOND_BUNDLE_PATH}" --strip-components=1)

# Update chameleond on btpeers.
LOG_DIVIDER="=============================================================================="
for HOST in "${BTPEER_HOSTS_TO_UPDATE[@]}"; do
  echo -e "\n${LOG_DIVIDER}"
  echo "Updating chameleond on host '${HOST}'"

  echo "Marking btpeer image as dirty"
  BUILD_INFO_JSON=$(ssh -q "${HOST}" "cat '${BTPEER_PATH_TO_BUILD_INFO_FILE}'")
  IMAGE_UUID=$(jq -r ."image_uuid" <<< "${BUILD_INFO_JSON}")
  if [ "${#IMAGE_UUID}" -ne 36 ]; then
    echo "Btpeer image already marked as dirty with image UUID '${IMAGE_UUID}', skipping step"
  else
    IMAGE_UUID="${IMAGE_UUID}${DIRTY_IMAGE_UUID_SUFFIX}"
    BUILD_INFO_JSON=$(jq '."image_uuid" = $val' --arg val "${IMAGE_UUID}" <<< "${BUILD_INFO_JSON}")
    echo "${BUILD_INFO_JSON}" | ssh -q "${HOST}" "cat - > '${BTPEER_PATH_TO_BUILD_INFO_FILE}'"
    echo "Successfully marked btpeer image as dirty with image UUID '${IMAGE_UUID}'"
  fi

  echo "Stopping chameleond service"
  ssh -q "${HOST}" "service chameleond stop"

  echo "Copying source files to btpeer"
  rsync -a "${BUNDLE_EXTRACT_DIR}"/* \
  "${HOST}:${CHROMIUMOS_CONFIG_SRC_BTPEER_DIR}"
  rsync -av "${BUNDLE_EXTRACT_DIR}/" "${HOST}:${BTPEER_PATH_TO_CHAMELEON_DIR}/"

  echo "Copying chameleond bundle config files to system locations on btpeer"
  ssh -q "${HOST}" "cp '${BTPEER_PATH_TO_CHAMELEON_DIR}/chameleond/utils/btservice.conf' '/etc/dbus-1/system.d/org.chromium.autotest.btservice.conf'"
  WIREPLUMBER_BTPEER_CONFIG_DIR="/home/pi/.config/bluetooth.lua.d"
  ssh -q "${HOST}" "cp '${BTPEER_PATH_TO_CHAMELEON_DIR}/updatable/wireplumber/bluetooth.lua.d/'* '${WIREPLUMBER_BTPEER_CONFIG_DIR}'"
  echo "Successfully copied chameleond bundle config files to system locations on btpeer"

  echo "Starting chameleond service"
  ssh -q "${HOST}" "service chameleond start"

  echo "Successfully updated chameleond on host '${HOST}'"
done

# Print summary.
echo -e "\n${LOG_DIVIDER}\n${LOG_DIVIDER}"
echo "Successfully updated chameleond on ${#BTPEER_HOSTS_TO_UPDATE[@]} hosts:"
for HOST in "${BTPEER_HOSTS_TO_UPDATE[@]}"; do
  echo "${HOST}"
done
