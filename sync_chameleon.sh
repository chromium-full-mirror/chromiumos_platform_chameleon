# Copyright 2026 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

#!/bin/bash

# Default Configuration
DEFAULT_LOCAL_CHAMELEON_DIR="$HOME/chromiumos/src/platform/chameleon"
LOCAL_CHAMELEON_DIR="$DEFAULT_LOCAL_CHAMELEON_DIR"
PI_HOST=""
PI_USER="root"
REMOTE_CHAMELEON_DIR="/etc/chromiumos/src/platform/chameleon"
SSH_KEY_PATH="/root/.ssh/testing_rsa"

usage() {
    echo "Usage: $0 [--chameleon_dir=<dir>] <PI_IP_ADDRESS>"
    echo ""
    echo "Arguments:"
    echo "  <PI_IP_ADDRESS>          The IP address of the target Raspberry Pi."
    echo "Options:"
    echo "  --chameleon_dir=<dir>    Path to your local chameleon directory."
    echo "                           (Default: $DEFAULT_LOCAL_CHAMELEON_DIR)"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --chameleon_dir=*)
            LOCAL_CHAMELEON_DIR="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$PI_HOST" ]; then
                PI_HOST="$1"
            else
                echo "Error: Unexpected argument '$1'"
                usage
            fi
            shift
            ;;
    esac
done

# Validate required inputs
if [ -z "$PI_HOST" ]; then
    echo "Error: Missing target Pi IP address."
    usage
fi

# Check if local directory exists
if [ ! -d "$LOCAL_CHAMELEON_DIR" ]; then
    echo "Error: Local directory '$LOCAL_CHAMELEON_DIR' not found."
    exit 1
fi

echo "Syncing Chameleon code to $PI_USER@$PI_HOST..."

# Sync files using rsync
# --delete: remove files on remote that are missing locally
# --exclude: skip .git, .pyc, etc.
rsync -avz \
    --exclude '.git' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '*.egg-info' \
    "$LOCAL_CHAMELEON_DIR/" \
    "$PI_USER@$PI_HOST:$REMOTE_CHAMELEON_DIR/"

if [ $? -eq 0 ]; then
    echo "Sync successful."
    echo "Restarting btpeerd, chameleond and bluetooth_grpc on Pi..."
    ssh "$PI_USER@$PI_HOST" \
	    "pkill -f btpeerd;"\
	    "service btpeerd restart;"\
	    "service chameleond restart;"\
	    "service bluetooth_grpc restart"
    echo "Services restarted."
else
    echo "Sync failed."
    exit 1
fi
