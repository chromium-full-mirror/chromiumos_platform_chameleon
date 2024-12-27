# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez utils functions."""

import enum

from google.protobuf import any_pb2
from pandora import host_pb2
from pandora_experimental import os_pb2


class BtTransport(enum.IntEnum):
    """Bluetooth transport type."""

    AUTO = 0
    BREDR = 1
    LE = 2


class Connection:
    """A Bluetooth connection."""

    def __init__(self, address: str, transport: BtTransport):
        self.address = address
        self.transport = transport


def connection_to(connection: Connection):
    """Converts Connection from Bluetooth test server format to gRPC format."""
    internal_connection_ref = os_pb2.InternalConnectionRef(
        address=address_to(connection.address), transport=connection.transport
    )
    cookie = any_pb2.Any(value=internal_connection_ref.SerializeToString())
    return host_pb2.Connection(cookie=cookie)


def connection_from(connection: host_pb2.Connection):
    """Converts Connection from gRPC format to Bluetooth test server format."""
    internal_connection_ref = os_pb2.InternalConnectionRef()
    internal_connection_ref.ParseFromString(connection.cookie.value)
    return Connection(
        address=address_from(internal_connection_ref.address),
        transport=internal_connection_ref.transport,
    )


def address_from(request_address: bytes):
    """Converts Bluetooth MAC address from bytes to string.

    The colon is added. For example:
    b"\x00\x11"3\xff\xee" to "00:11:22:33:FF:EE".
    """
    address = request_address.hex()
    address = (
        f"{address[:2]}:{address[2:4]}:{address[4:6]}:{address[6:8]}:"
        f"{address[8:10]}:{address[10:12]}"
    )
    return address.upper()


def address_to(address: str):
    """Converts address from string to bytes.

    The colon is stripped. For example:
    "00:11:22:33:FF:EE" to b"\x00\x11"3\xff\xee"
    """
    request_address = bytes.fromhex(address.replace(":", ""))
    return request_address


def address_from_bluez_device_path(device_path: str):
    """Converts Bluez device D-Bus object path to Bluetooth MAC address.

    For example:
    "/org/bluez/dev_00_11_22_33_FF_EE" to "00:11:22:33:FF:EE".
    """
    return device_path.split("/")[-1].replace("_", ":")[4:]


def service_data_to(service_data):
    """Converts service data from dict[str,list[int]] to dict[str,bytes]."""

    return {uuid: bytes(data) for uuid, data in service_data.items()}


def service_data_from(service_data):
    """Converts service data from dict[str,bytes] to dict[str,list[int]]."""

    return {
        uuid: [val for val in data_bytes]
        for uuid, data_bytes in service_data.items()
    }


# anext build-in is new in python3.10. Deprecate this function
# when we are able to use it.
async def anext(ait):
    return await ait.__anext__()
