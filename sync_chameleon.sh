# Copyright 2026 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

#!/bin/bash

# Configuration
if [ -z "$1" ]; then
    echo "Please specify address of Pi."
    exit 1
else
    PI_HOST="$1"
fi

PI_USER="root"
LOCAL_CHAMELEON_DIR="$HOME/chromiumos/src/platform/chameleon"
REMOTE_CHAMELEON_DIR="/etc/chromiumos/src/platform/chameleon"
SSH_KEY_PATH="/root/.ssh/testing_rsa"

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
