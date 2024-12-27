# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import asyncio

from chameleond.bluetooth_grpc.pandora.server import utils
import grpc
from pandora import host_grpc_aio


PANDORA_SERVER_PORT = 8999

proxy = grpc.insecure_channel(f"localhost:{PANDORA_SERVER_PORT}")
host_proxy = host_grpc_aio.Host(proxy)

rsp = host_proxy.Scan(timeout=30)
for r in rsp:
    address = utils.address_from(r.address)
    service_data = utils.service_data_from(r.data.service_data_uuid128)
    print(f"{address}: {service_data}")
