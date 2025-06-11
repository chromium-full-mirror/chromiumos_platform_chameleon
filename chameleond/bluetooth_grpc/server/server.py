# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluetooth test server."""

import os


os.environ["PLATFORM"] = "RASPI"

import asyncio
import atexit
import logging
import signal
import subprocess
import time

from blueship import audio_grpc_aio
from blueship import hid_grpc_aio
from blueship import manager_grpc_aio
from blueship import manager_pb2
from blueship import power_grpc_aio
from blueship import security_grpc_aio as blueship_security_grpc_aio
from chameleond.bluetooth_grpc.blueship.server import (
    security as blueship_security,
)
from chameleond.bluetooth_grpc.blueship.server import audio
from chameleond.bluetooth_grpc.blueship.server import hid
from chameleond.bluetooth_grpc.blueship.server import manager
from chameleond.bluetooth_grpc.blueship.server import power
from chameleond.bluetooth_grpc.pandora.server import host
from chameleond.bluetooth_grpc.pandora.server import security
from chameleond.bluetooth_grpc.pandora.server import utils
from chameleond.bluetooth_grpc.server.btmon_manager import BtmonManager
from chameleond.bluetooth_grpc.server.device_config import (
    DEFAULT_CHAMELEON_CONFIG,
)
from chameleond.drivers import fpga_tio
from chameleond.utils import common
from chameleond.utils import ids
import grpc
from pandora import host_grpc_aio
from pandora import security_grpc_aio


CHAMELEON_CLEANUP_TIME = 1
BLUEZ_RESTART_TIME = 3

RSYS_LOG_CONFIG = "/etc/logrotate.d/rsyslog"
BLUETOOTH_GRPC_LOG_CONFIG = "/etc/logrotate.d/bluetooth_grpc"


class TestServerContext:
    """The context of the test server."""

    def __init__(self, config):
        self.chameleon = fpga_tio.ChameleondDriver()
        self.config = config
        self.default_config = manager_pb2.Configuration()
        self.default_config.CopyFrom(config)
        self.is_server_ready = False
        self.signal_handlers = {}
        self.subprocess_sigterm_handler_name = None
        self.subprocess_sigint_handler_name = None
        self.signal_handler_count = 0

    @property
    def support_classic(self):
        """Helper function to convert support Classic from proto to bool"""
        return self.config.controller.support_classic.bool_value

    @property
    def support_le(self):
        """Helper function to convert support LE from proto to bool"""
        return self.config.controller.support_le.bool_value

    @property
    def io_capability(self):
        """Helper function to convert IO Capability from proto to String"""
        io_cap = self.config.device.io_capability.io_capability
        if io_cap == manager_pb2.IO_CAPABILITY_DISPLAY_ONLY:
            return "DisplayOnly"
        elif io_cap == manager_pb2.IO_CAPABILITY_DISPLAY_YES_NO:
            return "DisplayYesNo"
        elif io_cap == manager_pb2.IO_CAPABILITY_KEYBOARD_ONLY:
            return "KeyboardOnly"
        elif io_cap == manager_pb2.IO_CAPABILITY_NO_INPUT_NO_OUTPUT:
            return "NoInputNoOutput"
        elif io_cap == manager_pb2.IO_CAPABILITY_KEYBOARD_DISPLAY:
            return "KeyboardDisplay"
        return None

    @property
    def secure_connections(self):
        """Helper function to convert SecureConnections from proto to String"""
        sc = self.config.security.secure_connections.secure_connections
        if sc == manager_pb2.SECURE_CONNECTIONS_OFF:
            return "off"
        elif sc == manager_pb2.SECURE_CONNECTIONS_ON:
            return "on"
        elif sc == manager_pb2.SECURE_CONNECTIONS_ONLY:
            return "only"
        return None

    @property
    def device_type(self):
        """Helper function to convert Device Category from proto to String"""
        device_type = self.config.device.category.device_category

        if device_type == manager_pb2.DEVICE_CATEGORY_AUDIO:
            if self.support_classic:
                return "BLUETOOTH_AUDIO"
            # LE Audio is not implemented yet
        elif device_type == manager_pb2.DEVICE_CATEGORY_KEYBOARD:
            if self.support_le:
                return "BLE_KEYBOARD"
            elif self.support_classic:
                return "KEYBOARD"
        elif device_type == manager_pb2.DEVICE_CATEGORY_MOUSE:
            if self.support_le:
                return "BLE_MOUSE"
            elif self.support_classic:
                return "MOUSE"
        elif device_type == manager_pb2.DEVICE_CATEGORY_PHONE:
            if self.support_le:
                return "BLE_PHONE"
            # Classic phone is not implemented
        elif device_type == manager_pb2.DEVICE_CATEGORY_DEV_KIT:
            return "DEV_KIT"
        elif device_type == manager_pb2.DEVICE_CATEGORY_NOT_CONFIGURED:
            return "NOT_CONFIGURED"
        return None

    @property
    def hfp_codec(self):
        """Helper function to get the default HFP codec"""
        codec_list = self.config.audio.supported_codecs.codec_list.codec_list
        if manager_pb2.CODEC_CVSD in codec_list:
            return "CVSD"
        elif manager_pb2.CODEC_MSBC in codec_list:
            return "mSBC"
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
        elif self.device_type == "DEV_KIT":
            return self.chameleon.bluetooth_dev_kit

    def reset_bluetooth_device(self):
        logging.info("reset_bluetooth_device")

        # The correct sequence of resetting a Chameleond-based Bluetooth device:
        # 1. Clean up Chameleond.
        # 2. Reset Bluetooth stack (BlueZ).
        # 3. Reset Chameleond.
        self.chameleon.cleanup()
        time.sleep(CHAMELEON_CLEANUP_TIME)

        # Restart the Bluetooth stack (BlueZ). Wait a while to ensure it is
        # restarted.
        self.btd.ResetStack(
            next_device_type=self.device_type, restart_chameleond=False
        )
        time.sleep(BLUEZ_RESTART_TIME)

        # Restart Chameleond
        self.chameleon = fpga_tio.ChameleondDriver()

        if self.device_type == "BLUETOOTH_AUDIO":
            # Use the specialized audio server to enable WBS.
            # The specialized version was claimed that it suffered from
            # stability issues so it was not a default option, but at least
            # from the dashboard, the test
            # `au_hfp_wbs_to_a2dp_dut_as_source_test` is quite stable,
            # therefore, we use the specialized audio server as default here
            self.btd.StartAudioServer("hfp_wbs")
            self.btd.StartOfono()
            if not self.btd.ExportMediaPlayer():
                logging.info("Failed to export media player")

        self.btd.SpecifyDeviceType(self.device_type)

        # Set the link mode to prefer peripheral role.
        self.btd.SetLinkMode("ACCEPT")

        self.btd.SetIOCapability(self.io_capability)
        self.btd.SetSecureConnections(self.secure_connections)
        self.btd.SetSecureSimplePairing(
            self.config.security.secure_simple_pairing.bool_value
        )

    def unregister_signal_handler(self, signum, name):
        """Unregisters a specific signal handler.

        Removes the signal handler identified by the given `name` for the
        specified signal `signum`. If a handler with that name exists for the
        signal, it will be removed from the internal registry.

        Args:
            signum: The signal number (e.g., signal.SIGTERM, signal.SIGINT).
            name: The unique name associated with the signal handler
                  when it was registered.
        """
        if signum in self.signal_handlers:
            if name in self.signal_handlers[signum]:
                self.signal_handlers[signum].pop(name)

    def register_signal_handler(self, signum, handler):
        """Registers a handler function for a specific signal.

        Registers a custom handler function for the specified signal. It
        allows multiple handlers to be registered for the same signal. The
        registered handlers are stored internally, and when the signal is
        received, all registered handlers for that signal are executed in the
        reversed order they were registered.

        Args:
            signum: The signal number (e.g., signal.SIGTERM, signal.SIGINT).
            handler: The function to be called when the signal is received.
                     The handler function should accept two arguments: the
                     signal number and the current frame.

        Returns:
            name: A unique name assigned to the registered handler. This name
                  can be used later to unregister the handler using
                 `unregister_signal_handler`.
        """
        if handler is None:
            logging.error("Handler is None, return.")

        if signum not in self.signal_handlers:
            self.signal_handlers[signum] = {}

            def _dispatch_handlers(signum, frame):
                if signum in self.signal_handlers:
                    for name in reversed(
                        list(self.signal_handlers[signum].keys())
                    ):
                        self.signal_handlers[signum][name](signum, frame)

            signal.signal(signum, _dispatch_handlers)

        self.signal_handler_count += 1
        name = str(self.signal_handler_count)
        self.signal_handlers[signum][name] = handler
        return name

    def register_subprocess_cleanup(self, process):
        """Registers cleanup actions for a subprocess on exit and signals.

        Ensures that a given subprocess.Popen object is properly terminated
        and cleaned up when the main program exits normally or receives a
        SIGTERM or SIGINT signal.

        Args:
            process: The subprocess.Popen object to be cleaned up.
        """
        if process is None:
            logging.error("Process is None, return.")
            return

        atexit.register(common.cleanup_subprocess, process, None, None)
        self.subprocess_sigterm_handler_name = self.register_signal_handler(
            signal.SIGTERM,
            lambda signum, frame: common.cleanup_subprocess(
                process, signum, frame
            ),
        )
        self.subprocess_sigint_handler_name = self.register_signal_handler(
            signal.SIGINT,
            lambda signum, frame: common.cleanup_subprocess(
                process, signum, frame
            ),
        )

    def unregister_subprocess_cleanup(self):
        """Unregisters the cleanup functions for subprocesses."""
        atexit.unregister(common.cleanup_subprocess)
        self.unregister_signal_handler(
            signal.SIGTERM, self.subprocess_sigterm_handler_name
        )
        self.unregister_signal_handler(
            signal.SIGINT, self.subprocess_sigint_handler_name
        )


def trigger_log_rotate(services_to_rotate):
    """Triggers logrotate for a list of specified logrotate configuration files.

    Args:
        services_to_rotate (list): A list of strings, where each string is the
                                    absolute path to a logrotate configuration
                                    file (e.g., '/etc/logrotate.d/rsyslog',
                                    '/etc/logrotate.d/my_custom_app').
    """
    for config in services_to_rotate:
        try:
            logging.info(
                f"Attempting to trigger logrotate for config: {config}..."
            )
            # Using -f to force rotation
            command = ["sudo", "logrotate", "-vf", config]

            process = subprocess.Popen(
                command, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            stdout, stderr = process.communicate()

            if process.returncode == 0:
                logging.info(f"Successfully triggered logrotate for {config}.")
            else:
                logging.error(f"Error triggering logrotate for {config}")
                if stdout:
                    logging.error(f"Stdout:\n{stdout.decode()}\n")
                if stderr:
                    logging.error(f"Stderr:\n{stderr.decode()}")
        except Exception as e:
            logging.error(f"Failed to log rotate {config}")


async def start_bluetooth_test_server(port):
    """Start serving the bluetooth test server."""

    try:
        server = None
        shared_context = TestServerContext(DEFAULT_CHAMELEON_CONFIG)
        btmon_manager = BtmonManager(output_directory="/var/log/btmon")

        while True:
            trigger_log_rotate([RSYS_LOG_CONFIG, BLUETOOTH_GRPC_LOG_CONFIG])
            server = grpc.aio.server()

            if shared_context.device_type == "NOT_CONFIGURED":
                logging.info("@@ Skip resetting Bluetooth")
            else:
                btmon_manager.start()
                shared_context.reset_bluetooth_device()
                shared_context.register_subprocess_cleanup(
                    btmon_manager.btmon_process
                )

                # Pandora services
                security_service = security.SecurityService(
                    shared_context,
                )
                security_grpc_aio.add_SecurityServicer_to_server(
                    security_service, server
                )

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

                # BlueShip services
                blueship_security_service = blueship_security.SecurityService(
                    shared_context,
                )
                blueship_security_grpc_aio.add_SecurityServicer_to_server(
                    blueship_security_service, server
                )

                audio_service = audio.AudioService(shared_context)
                audio_grpc_aio.add_AudioServicer_to_server(
                    audio_service, server
                )

                hid_service = hid.HIDService(shared_context)
                hid_grpc_aio.add_HIDServicer_to_server(hid_service, server)

                power_service = power.PowerService(
                    shared_context,
                )
                power_grpc_aio.add_PowerServicer_to_server(
                    power_service, server
                )

            manager_service = manager.ManagerService(shared_context, server)
            manager_grpc_aio.add_ManagerServicer_to_server(
                manager_service, server
            )

            server.add_insecure_port(f"[::]:{port}")

            logging.info("Starting Bluetooth test server.")
            await server.start()
            logging.info("Bluetooth test server started.")
            shared_context.is_server_ready = True

            await server.wait_for_termination()
            if shared_context.device_type != "NOT_CONFIGURED":
                btmon_manager.stop()
                shared_context.unregister_subprocess_cleanup()
            logging.info("Bluetooth test server stopped, restarting...")
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
