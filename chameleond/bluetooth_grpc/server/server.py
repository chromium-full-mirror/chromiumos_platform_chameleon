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

    def __init__(self, chameleon, bluetooth_device, config):
        self.chameleon = chameleon
        self.btd = bluetooth_device
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


async def start_bluetooth_test_server(port, device_id):
    """Start serving the bluetooth test server."""

    try:
        server = None
        chameleon = None
        while True:
            chameleon = fpga_tio.ChameleondDriver()
            chameleon_devices = {
                ids.BLUETOOTH_AUDIO: "bluetooth_audio",
                ids.BLUETOOTH_HID_KEYBOARD: "bluetooth_keyboard",
                ids.BLUETOOTH_HID_MOUSE: "bluetooth_mouse",
                ids.BLUETOOTH_HID_GAMEPAD: "bluetooth_gamepad",
                ids.BLUETOOTH_BASE: "bluetooth_base",
                ids.BLUETOOTH_TESTER: "bluetooth_tester",
                ids.BLE_KEYBOARD: "ble_keyboard",
                ids.BLE_MOUSE: "ble_mouse",
                ids.BLE_PHONE: "ble_phone",
                ids.BLE_FAST_PAIR: "ble_fast_pair",
            }

            if device_id in chameleon_devices:
                logging.info("Using device: %s!", chameleon_devices[device_id])
            else:
                logging.error(
                    "Device id %s is not supported! The server has stopped.",
                    device_id,
                )
                break

            bluetooth = getattr(chameleon, chameleon_devices[device_id])
            shared_context = TestServerContext(
                chameleon, bluetooth, DEFAULT_CHAMELEON_CONFIG
            )

            if device_id == ids.BLUETOOTH_AUDIO:
                # Use the specialized audio server to enable WBS.
                # The specialized version was claimed that it suffered from
                # stability issues so it was not a default option, but at least
                # from the dashboard, the test
                # `au_hfp_wbs_to_a2dp_dut_as_source_test` is quite stable,
                # therefore, we use the specialized audio server as default here
                bluetooth.StartAudioServer("hfp_wbs")

            server = grpc.aio.server()
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

            del chameleon
            chameleon = None
    finally:
        if server is not None:
            await server.stop(None)

        del chameleon
        chameleon = None


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

    # from chameleond/utils/ids.py
    device_map = {
        "BLUETOOTH_HID_KEYBOARD": 12,
        "BLUETOOTH_HID_GAMEPAD": 13,
        "BLUETOOTH_HID_MOUSE": 14,
        "BLUETOOTH_HID_COMBO": 15,
        "BLUETOOTH_HID_JOYSTICK": 16,
        "AVSYNC_PROBE": 17,
        "AUDIO_BOARD": 18,
        "MOTOR_BOARD": 19,
        "BLUETOOTH_HOG_KEYBOARD": 20,
        "BLUETOOTH_HOG_GAMEPAD": 21,
        "BLUETOOTH_HOG_MOUSE": 22,
        "BLUETOOTH_HOG_COMBO": 23,
        "BLUETOOTH_HOG_JOYSTICK": 24,
        "USB_PRINTER": 25,
        "BLUETOOTH_A2DP_SINK": 26,
        "BLE_MOUSE": 27,
        "BLE_KEYBOARD": 28,
        "BLUETOOTH_BASE": 29,
        "BLUETOOTH_TESTER": 30,
        "BLE_PHONE": 31,
        "BLUETOOTH_AUDIO": 32,
        "BLE_FAST_PAIR": 33,
    }

    parser = argparse.ArgumentParser(
        description="Launch a Bluetooth test server daemon.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--device_type",
        choices=list(device_map.keys()),
        type=str,
        default="BLUETOOTH_AUDIO",
        help="bluetooth device to create",
    )

    options = parser.parse_args()

    asyncio.run(
        start_bluetooth_test_server(8999, device_map.get(options.device_type))
    )
