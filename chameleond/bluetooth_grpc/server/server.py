# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluetooth test server."""

import os


os.environ["PLATFORM"] = "RASPI"
os.environ["DISABLE_AUTO_ADVERTISE_ON_DISCONNECT"] = "true"

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
from chameleond.utils.bluez_service_consts import PERIPHERAL_DEVICE_CLASS
import grpc
from pandora import host_grpc_aio
from pandora import security_grpc_aio


CHAMELEON_CLEANUP_TIME = 1
BLUEZ_RESTART_TIME = 3

RSYS_LOG_CONFIG = "/etc/logrotate.d/rsyslog"
BLUETOOTH_GRPC_LOG_CONFIG = "/etc/logrotate.d/bluetooth_grpc"

# Page timeout: 10.24 seconds
HCI_PAGE_TIMEOUT_SLOTS = 0x4000
# Inquiry Activity Window: 45 ms
HCI_INQ_WINDOW_SLOTS = 72
# Inquiry Activity Interval: 1280 ms
HCI_INQ_INTERVAL_SLOTS = 2048


class TestServerContext:
    """The context of the test server."""

    def __init__(self, config):
        self.chameleon = fpga_tio.ChameleondDriver()
        self.config = config
        self.default_config = manager_pb2.Configuration()
        self.default_config.CopyFrom(config)
        self.is_server_ready = True
        self.is_configured = False
        self.btmon_manager = None
        self.initialize_device_task = None
        self.services = []
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
    def link_mode(self):
        """Helper function to convert LinkMode from proto to String"""
        lm = self.config.security.link_mode.link_mode
        if lm == manager_pb2.LINK_MODE_NONE:
            return "NONE"
        elif lm == manager_pb2.LINK_MODE_ACCEPT:
            return "ACCEPT"
        elif lm == manager_pb2.LINK_MODE_MASTER:
            return "MASTER"
        elif lm == manager_pb2.LINK_MODE_AUTH:
            return "AUTH"
        elif lm == manager_pb2.LINK_MODE_ENCRYPT:
            return "ENCRYPT"
        elif lm == manager_pb2.LINK_MODE_TRUSTED:
            return "TRUSTED"
        elif lm == manager_pb2.LINK_MODE_RELIABLE:
            return "RELIABLE"
        elif lm == manager_pb2.LINK_MODE_SECURE:
            return "SECURE"
        return None

    @property
    def privacy(self):
        """Helper function to convert Privacy from proto to bool"""
        return self.config.security.privacy.bool_value

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
        if manager_pb2.CODEC_MSBC in codec_list:
            return "mSBC"
        elif manager_pb2.CODEC_CVSD in codec_list:
            return "CVSD"
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
        return None

    @property
    def device_name(self):
        return self.config.device.name.string_value


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

        self.btd.SpecifyDeviceType(
            self.device_type,
            self.config.devkit.rfcomm_services.service_list.service_list,
            self.device_name
        )

        # Delay 1 second to wait for power on.
        time.sleep(1)

        self.apply_btmgmt_capabilities()
        self.apply_hciconfig()

    def apply_btmgmt_capabilities(self):
        logging.info("apply btmgmt capabilities")
        # Set secure connection. This should be done before configuring link
        # mode, fast-connectable and the Class of Service, as powering off
        # BREDR resets these configurations.
        cmds = [
            "sudo btmgmt power off",
            "sudo btmgmt le on",
            "sudo btmgmt bredr off",
            f"sudo btmgmt sc {self.secure_connections}",
        ]
        if self.support_classic:
            cmds.extend(
                [
                    "sudo btmgmt bredr on",
                    "sudo btmgmt le off",
                ]
            )

        logging.info(
            "Configure BT adapter settings before powering on. SC: %s",
            self.secure_connections,
        )
        for cmd in cmds:
            os.system(cmd)
            time.sleep(0.1)

        self.btd.SetLinkMode(self.link_mode, power_cycle=False)

        self.btd.SetPrivacy(self.privacy, power_cycle=False)

        if self.support_classic:
            self.btd.SetSecureSimplePairing(
                self.config.security.secure_simple_pairing.bool_value
            )
            # Enable fast connectable to reduce the chance of page timeout in test.
            self.btd.SetFastConnectable(True)

        self.btd.SetIOCapability(self.io_capability)

        if self.device_type and "BLE" not in self.device_type:
            major = (PERIPHERAL_DEVICE_CLASS[self.device_type] & 0x001F00) >> 8
            minor = PERIPHERAL_DEVICE_CLASS[self.device_type] & 0x0000FC
            self.btd.SetDeviceClass(major, minor)

        cmds = ["sudo btmgmt power on"]
        for cmd in cmds:
            os.system(cmd)
            time.sleep(0.1)
        # Wait for the adapter to power on forever.
        # Test will restart this grpc server after its custom timeout.
        self._wait_for_adapter_power_on("hci0", timeout=float('inf'))

    def _is_adapter_powered(self, adapter="hci0"):
        """Checks if the specified bluetooth adapter is powered on via hciconfig."""
        try:
            output = subprocess.check_output(["hciconfig", adapter]).decode("utf-8")
            lines = output.splitlines()
            for line in lines:
                # Example output of `hciconfig hci0`:
                # hci0:   Type: Primary  Bus: UART
                #         BD Address: DC:A6:32:D3:53:FD  ACL MTU: 1021:8  SCO MTU: 64:1
                #         UP RUNNING
                #         RX bytes:2301 acl:0 sco:0 events:138 errors:0
                #         X bytes:3516 acl:0 sco:0 commands:138 errors:0

                # Find line with "UP"
                if line.strip().startswith("UP"):
                    return True
        except Exception as e:
            logging.error("Failed to check power status for %s: %s", adapter, e)
        return False

    def _wait_for_adapter_power_on(self, adapter="hci0", timeout=5.0, interval=0.5):
        """Waits for the specified adapter to be powered on.

        Args:
            timeout: seconds to wait before giving up.
            interval: seconds to wait between each query.

        Return:
            Whether the bluetooth adapter powered on successfully before timeout.
        """
        try:
            common.PollForCondition(
                condition=lambda: self._is_adapter_powered(adapter),
                timeout=timeout,
                sleep_interval=interval,
                desc=f"bluetooth adapter {adapter} to power on ({timeout:.1f} s)",
            )
            logging.info("Bluetooth adapter %s powered on successfully", adapter)
            return True
        except common.TimeoutError as e:
            logging.error("Bluetooth adatper error: %s", e)
            return False

    def apply_hciconfig(self):
        logging.info("apply hciconfig capabilities")
        if self.support_classic:
            self.btd.SetPageTimeout(HCI_PAGE_TIMEOUT_SLOTS)
            self.btd.SetInquiryParameters(
                HCI_INQ_WINDOW_SLOTS, HCI_INQ_INTERVAL_SLOTS
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

    async def initialize_device(self):
        """Initializes the bluetooth device in background."""
        if (
            self.initialize_device_task
            and not self.initialize_device_task.done()
        ):
            logging.info("initialize_device: Task already running, waiting...")
            await self.initialize_device_task

        async def _initialize():
            if self.device_type != "NOT_CONFIGURED":
                self.is_server_ready = False
                if self.btmon_manager:
                    self.btmon_manager.start()
                    self.register_subprocess_cleanup(
                        self.btmon_manager.btmon_process
                    )
                loop = asyncio.get_running_loop()
                await loop.run_in_executor(None, self.reset_bluetooth_device)

                # Post-initialize all services
                for service in self.services:
                    if hasattr(service, "PostInitialize"):
                        service.PostInitialize()

                self.is_server_ready = True
                self.is_configured = True
            else:
                logging.info("Skip resetting Bluetooth, device not configured")
                self.is_server_ready = True

        self.initialize_device_task = asyncio.create_task(_initialize())
        await self.initialize_device_task


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
        shared_context = TestServerContext(DEFAULT_CHAMELEON_CONFIG)
        btmon_manager = BtmonManager(output_directory="/var/log/btmon")
        shared_context.btmon_manager = btmon_manager

        trigger_log_rotate([RSYS_LOG_CONFIG, BLUETOOTH_GRPC_LOG_CONFIG])
        server = grpc.aio.server()

        # Pandora services
        security_service = security.SecurityService(
            shared_context,
        )
        security_grpc_aio.add_SecurityServicer_to_server(
            security_service, server
        )
        shared_context.services.append(security_service)

        host_service = host.HostService(
            server, shared_context, security_service
        )
        host_grpc_aio.add_HostServicer_to_server(host_service, server)
        shared_context.services.append(host_service)

        security_storage_service = security.SecurityStorageService(
            shared_context
        )
        security_grpc_aio.add_SecurityStorageServicer_to_server(
            security_storage_service, server
        )
        shared_context.services.append(security_storage_service)

        # BlueShip services
        blueship_security_service = blueship_security.SecurityService(
            shared_context,
        )
        blueship_security_grpc_aio.add_SecurityServicer_to_server(
            blueship_security_service, server
        )
        shared_context.services.append(blueship_security_service)

        audio_service = audio.AudioService(shared_context)
        audio_grpc_aio.add_AudioServicer_to_server(audio_service, server)
        shared_context.services.append(audio_service)

        hid_service = hid.HIDService(shared_context)
        hid_grpc_aio.add_HIDServicer_to_server(hid_service, server)
        shared_context.services.append(hid_service)

        power_service = power.PowerService(
            shared_context,
        )
        power_grpc_aio.add_PowerServicer_to_server(power_service, server)
        shared_context.services.append(power_service)

        manager_service = manager.ManagerService(shared_context, server)
        manager_grpc_aio.add_ManagerServicer_to_server(manager_service, server)
        shared_context.services.append(manager_service)

        server.add_insecure_port(f"[::]:{port}")

        logging.info("Starting Bluetooth test server.")
        await server.start()
        logging.info("Bluetooth test server started.")

        await server.wait_for_termination()

        if btmon_manager.btmon_process:
            btmon_manager.stop()
            shared_context.unregister_subprocess_cleanup()

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
