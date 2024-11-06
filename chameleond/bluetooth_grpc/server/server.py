# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluetooth test server."""

import os


os.environ["PLATFORM"] = "RASPI"

import argparse
import asyncio
import logging

from blueship import audio_grpc_aio
from blueship import config_grpc_aio
from blueship import config_pb2
from chameleond.bluetooth_grpc.blueship.server import audio
from chameleond.bluetooth_grpc.blueship.server import config
from chameleond.bluetooth_grpc.pandora.server import host
from chameleond.bluetooth_grpc.pandora.server import security
from chameleond.bluetooth_grpc.server.device_config import (
    DEFAULT_CHAMELEON_CONFIG,
)
from chameleond.drivers import fpga_tio
from chameleond.utils import ids
import grpc
from pandora import host_grpc_aio
from pandora import security_grpc_aio


class TestServerContext:
    """The context of the test server."""

    def __init__(self, config):
        self.chameleon = fpga_tio.ChameleondDriver()
        self.config = config
        self.default_config = config_pb2.Configuration()
        self.default_config.CopyFrom(config)

    @property
    def io_capability(self):
        """Helper function to convert IO Capability from proto to String"""
        io_cap = self.config.device.io_capability.io_capability
        if io_cap == config_pb2.IO_CAPABILITY_DISPLAY_ONLY:
            return "DisplayOnly"
        elif io_cap == config_pb2.IO_CAPABILITY_DISPLAY_YES_NO:
            return "DisplayYesNo"
        elif io_cap == config_pb2.IO_CAPABILITY_KEYBOARD_ONLY:
            return "KeyboardOnly"
        elif io_cap == config_pb2.IO_CAPABILITY_NO_INPUT_NO_OUTPUT:
            return "NoInputNoOutput"
        elif io_cap == config_pb2.IO_CAPABILITY_KEYBOARD_DISPLAY:
            return "KeyboardDisplay"
        return None

    @property
    def device_type(self):
        """Helper function to convert Device Category from proto to String"""
        device_type = self.config.device.category.device_category
        support_le = False
        if device_type == config_pb2.DEVICE_CATEGORY_AUDIO:
            return "BLUETOOTH_AUDIO"
        elif device_type == config_pb2.DEVICE_CATEGORY_KEYBOARD:
            if support_le:
                return "BLE_KEYBOARD"
            else:
                return "KEYBOARD"
        elif device_type == config_pb2.DEVICE_CATEGORY_MOUSE:
            if support_le:
                return "BLE_MOUSE"
            else:
                return "MOUSE"
        elif device_type == config_pb2.DEVICE_CATEGORY_PHONE:
            if support_le:
                return "BLE_PHONE"
        return None

    @property
    def btd(self):
        if self.device_type == "BLUETOOTH_AUDIO":
            return self.chameleon.bluetooth_audio
        elif self.device_type == "BLE_KEYBOARD":
            return self.chameleon.ble_keyboard
        elif self.device_type == "KEYBOARD":
            return self.chameleon.bluetooth_keyboard
        elif self.device_type == "BLE_MOUSE":
            return self.chameleon.ble_mouse
        elif self.device_type == "MOUSE":
            return self.chameleon.bluetooth_mouse
        elif self.device_type == "BLE_PHONE":
            return self.chameleon.ble_phone

    def reset_bluetooth_device(self):
        logging.info("reset_bluetooth_device")
        self.chameleon.cleanup()
        self.chameleon = fpga_tio.ChameleondDriver()

        self.btd.ResetStack(next_device_type=self.device_type)

        if self.device_type == "BLUETOOTH_AUDIO":
            # Use the specialized audio server to enable WBS.
            # The specialized version was claimed that it suffered from
            # stability issues so it was not a default option, but at least
            # from the dashboard, the test
            # `au_hfp_wbs_to_a2dp_dut_as_source_test` is quite stable,
            # therefore, we use the specialized audio server as default here
            self.btd.StartAudioServer("hfp_wbs")

        self.btd.SpecifyDeviceType(self.device_type)
        self.btd.SetIOCapability(self.io_capability)


async def start_bluetooth_test_server(port):
    """Start serving the bluetooth test server."""

    try:
        server = None
        shared_context = TestServerContext(DEFAULT_CHAMELEON_CONFIG)

        while True:
            server = grpc.aio.server()

            shared_context.reset_bluetooth_device()

            security_service = security.SecurityService(
                shared_context,
            )
            security_grpc_aio.add_SecurityServicer_to_server(
                security_service, server
            )

            audio_service = audio.AudioService(shared_context)
            audio_grpc_aio.add_AudioServicer_to_server(audio_service, server)

            host_service = host.HostService(
                server, shared_context, security_service
            )
            host_grpc_aio.add_HostServicer_to_server(host_service, server)

            security_storage_service = security.SecurityStorageService(
                shared_context
            )
            security_grpc_aio.add_SecurityStorageServicer_to_server(
                security_storage_service, server
            )

            config_service = config.ConfigService(shared_context)
            config_grpc_aio.add_ConfigServicer_to_server(config_service, server)

            server.add_insecure_port(f"[::]:{port}")

            logging.info("Starting Bluetooth test server.")
            await server.start()
            logging.info("Bluetooth test server started.")

            await server.wait_for_termination()
    finally:
        if server is not None:
            await server.stop(None)


if __name__ == "__main__":
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)

    logging.basicConfig(
        filename="/var/log/bluetooth_test_server.log",
        filemode="a",
        level=logging.DEBUG,
        format="%(asctime)s %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    asyncio.run(start_bluetooth_test_server(8999))
