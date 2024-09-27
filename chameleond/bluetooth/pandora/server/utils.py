# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez utils functions."""


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


# anext build-in is new in python3.10. Deprecate this function
# when we are able to use it.
async def anext(ait):
    return await ait.__anext__()
