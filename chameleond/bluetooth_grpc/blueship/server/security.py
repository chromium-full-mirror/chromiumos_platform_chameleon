# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Security grpc interface."""

import asyncio
import enum
import logging
import queue
from typing import AsyncGenerator, AsyncIterator

from blueship import security_grpc_aio
from blueship import security_pb2
from chameleond.bluetooth_grpc.blueship.server.utils import check_server_ready
from chameleond.bluetooth_grpc.pandora.server import utils
import dbus
import dbus.mainloop.glib
import dbus.service
from google.protobuf import empty_pb2
import grpc


BUS_NAME = "org.bluez"
AGENT_INTERFACE = "org.bluez.Agent1"
AGENT_MANAGER_INTERFACE = "org.bluez.AgentManager1"
DEVICE_INTERFACE = "org.bluez.Device1"
PROP_INTERFACE = "org.freedesktop.DBus.Properties"

BLUEZ_OBJECT_PATH = dbus.ObjectPath("/org/bluez")
AGENT_PATH = dbus.ObjectPath("/test/agent")


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


# Pandora pairing event types
class PairingEvent(enum.IntEnum):
    JUST_WORK = 0
    NUMERIC_COMPARISON = 1
    PASSKEY_ENTRY_REQUEST = 2
    PASSKEY_ENTRY_NOTIFICATION = 3
    PIN_CODE_REQUEST = 4
    PIN_CODE_NOTIFICATION = 5


class Agent(dbus.service.Object):
    """A Pairing Agent.
    Args:
        path: The dbus object path.
        loop: The current asyncio event loop.
        pairing_events: The queue to store pairing events.
        pairing_answers: The queue to store pairing answers.
    """

    def __init__(self, path, loop, pairing_events, pairing_answers):
        self.bus = dbus.SystemBus()
        super(Agent, self).__init__(self.bus, path)
        self.loop = loop
        self.pairing_events = pairing_events
        self.pairing_answers = pairing_answers

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Release(self):
        logging.info("Release")

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        logging.info("AuthorizeService (%s, %s)", device, uuid)

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        logging.info("RequestPinCode (%s)", device)

        event = (PairingEvent.PIN_CODE_REQUEST, device)
        asyncio.run_coroutine_threadsafe(
            self.pairing_events.put(event), self.loop
        )

        pairing_answer = None
        try:
            pairing_answer = self.pairing_answers.get(timeout=30)
        except queue.Empty:
            logging.info("Timeout for waiting pairing answer.")

        if pairing_answer and pairing_answer.WhichOneof("answer") == "pin":
            logging.info(
                "Got pin code %s entered by user",
                pairing_answer.pin.decode("utf-8"),
            )
            return pairing_answer.pin.decode("utf-8")
        raise Canceled(
            f"Unexpected answer received from client: {pairing_answer}"
        )

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        logging.info("RequestPasskey (%s)", device)

        event = (PairingEvent.PASSKEY_ENTRY_REQUEST, device)
        asyncio.run_coroutine_threadsafe(
            self.pairing_events.put(event), self.loop
        )

        pairing_answer = None
        try:
            pairing_answer = self.pairing_answers.get(timeout=30)
        except queue.Empty:
            logging.info("Timeout for waiting pairing answer.")

        if pairing_answer and pairing_answer.WhichOneof("answer") == "passkey":
            logging.info(
                "Got passkey %s entered by user", pairing_answer.passkey
            )
            return dbus.UInt32(pairing_answer.passkey)
        raise Canceled(
            f"Unexpected answer format received from client: {pairing_answer}"
        )

    @dbus.service.method(AGENT_INTERFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        logging.info(
            "DisplayPasskey (%s, %06u entered %u)", device, passkey, entered
        )

        event = (
            PairingEvent.PASSKEY_ENTRY_NOTIFICATION,
            device,
            passkey,
            entered,
        )
        asyncio.run_coroutine_threadsafe(
            self.pairing_events.put(event), self.loop
        )

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        logging.info("DisplayPinCode (%s, %s)", device, pincode)

        event = (PairingEvent.PIN_CODE_NOTIFICATION, device, pincode)
        asyncio.run_coroutine_threadsafe(
            self.pairing_events.put(event), self.loop
        )

    @dbus.service.method(AGENT_INTERFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        logging.info("RequestConfirmation (%s, %06d)", device, passkey)

        event = (PairingEvent.NUMERIC_COMPARISON, device, passkey)
        asyncio.run_coroutine_threadsafe(
            self.pairing_events.put(event), self.loop
        )

        pairing_answer = None
        try:
            pairing_answer = self.pairing_answers.get(timeout=30)
        except queue.Empty:
            logging.info("Timeout for waiting pairing answer.")

        if pairing_answer and pairing_answer.WhichOneof("answer") == "confirm":
            if pairing_answer.confirm:
                logging.info("RequestConfirmation: user confirmed.")
                return
            else:
                raise Rejected("RequestConfirmation: rejected by user.")
        raise Canceled(
            f"Unexpected answer format received from client: {pairing_answer}"
        )

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        logging.info("RequestAuthorization (%s) not implemented yet", device)

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Cancel(self):
        logging.info("Cancel not implemented yet")


class SecurityService(security_grpc_aio.SecurityServicer):
    """Service to trigger Chameleon Security procedures."""

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context
        self.pairing_events = None
        self.pairing_loop = None

    def PostInitialize(self):
        """Initializes the service after the Bluetooth stack is ready."""
        if self.ctx.btd is None:
            logging.error("self.ctx.btd is None in PostInitialize!")
            return

        self.ctx.btd.bluez_observer.RegisterDevicePairedCallback(
            self.on_device_paired
        )
        self.ctx.btd.bluez_observer.RegisterDeviceDisconnectedCallback(
            self.on_device_disconnected
        )

    @check_server_ready
    async def Pair(
        self,
        request: security_pb2.PairRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        address = utils.address_from(request.address)
        self.ctx.btd.SetRemoteAddress(address)
        self.ctx.btd.Pair()
        return empty_pb2.Empty()

    @check_server_ready
    async def StartPairingMode(
        self,
        request: AsyncIterator[security_pb2.PairingEventAnswer],
        context: grpc.ServicerContext,
    ) -> AsyncGenerator[security_pb2.PairingEvent, None]:
        logging.info("Pairing Mode: Starting")

        self.ctx.btd.SetDiscoverable(True)

        self.pairing_events = asyncio.Queue()
        self.pairing_loop = asyncio.get_running_loop()
        pairing_answers = queue.Queue()
        agent = None
        agent_manager = None
        streaming_answers_task = None
        try:
            agent = Agent(
                AGENT_PATH,
                self.pairing_loop,
                self.pairing_events,
                pairing_answers,
            )
            bluez_obj = dbus.SystemBus().get_object(BUS_NAME, BLUEZ_OBJECT_PATH)
            agent_manager = dbus.Interface(bluez_obj, AGENT_MANAGER_INTERFACE)

            agent_manager.RegisterAgent(
                AGENT_PATH, dbus.String(self.ctx.io_capability)
            )
            agent_manager.RequestDefaultAgent(AGENT_PATH)
            logging.info("Pairing Mode: pairing agent registered.")

            async def streaming_answers(remote_request, pairing_answers):
                logging.info("Pairing Mode: Wait for pairing answer...")
                while True:
                    pairing_answer = await utils.anext(remote_request)
                    logging.info(
                        "Pairing Mode: Pairing answer: %s", pairing_answer
                    )
                    pairing_answers.put(pairing_answer)

            streaming_answers_task = asyncio.create_task(
                streaming_answers(request, pairing_answers)
            )

            while True:
                logging.info("Pairing Mode: Wait for pairing events...")
                (
                    pairing_variant,
                    *pairing_context,
                ) = await self.pairing_events.get()
                logging.info(
                    "Pairing Mode: Pairing event: pairing_variant: %s, "
                    "pairing_context:%s",
                    pairing_variant,
                    pairing_context,
                )

                # None means we should stop pairing mode.
                if pairing_variant is None:
                    break

                event = security_pb2.PairingEvent()

                if pairing_variant == PairingEvent.JUST_WORK:
                    pass
                elif pairing_variant == PairingEvent.NUMERIC_COMPARISON:
                    device_path, passkey = pairing_context
                    event.address = utils.address_to(
                        utils.address_from_bluez_device_path(device_path)
                    )
                    event.numeric_comparison = passkey
                elif pairing_variant == PairingEvent.PASSKEY_ENTRY_REQUEST:
                    [device_path] = pairing_context
                    event.address = utils.address_to(
                        utils.address_from_bluez_device_path(device_path)
                    )
                    event.passkey_entry_request.CopyFrom(empty_pb2.Empty())
                elif pairing_variant == PairingEvent.PASSKEY_ENTRY_NOTIFICATION:
                    device_path, passkey, _ = pairing_context
                    event.address = utils.address_to(
                        utils.address_from_bluez_device_path(device_path)
                    )
                    event.passkey_entry_notification = passkey
                elif pairing_variant == PairingEvent.PIN_CODE_REQUEST:
                    [device_path] = pairing_context
                    event.address = utils.address_to(
                        utils.address_from_bluez_device_path(device_path)
                    )
                    event.pin_code_request.CopyFrom(empty_pb2.Empty())
                elif pairing_variant == PairingEvent.PIN_CODE_NOTIFICATION:
                    device_path, pincode = pairing_context
                    event.address = utils.address_to(
                        utils.address_from_bluez_device_path(device_path)
                    )
                    event.pin_code_notification = pincode.encode("utf-8")
                yield event
        finally:
            logging.info("Pairing Mode: Cleaning up in background...")
            if agent_manager is not None:
                agent_manager.UnregisterAgent(AGENT_PATH)
                agent_manager = None

            if agent is not None:
                agent.remove_from_connection()
                agent = None

            if streaming_answers_task is not None:
                streaming_answers_task.cancel()
                streaming_answers_task = None

            pairing_answers = None
            self.pairing_events = None
            self.pairing_loop = None
            if self.ctx.btd:
                self.ctx.btd.SetDiscoverable(False)

            logging.info("Pairing Mode: Stopped")

    def on_device_paired(self, address):
        logging.info("Setting device %s trusted", address)
        if self.ctx.btd:
            self.ctx.btd.SetTrustedByRemoteAddress(address)

        if self.pairing_events is not None and self.pairing_loop is not None:
            if self.ctx.btd:
                self.ctx.btd.SetRemoteAddress(address)

    def on_device_disconnected(self, address):
        if self.pairing_events is not None and self.pairing_loop is not None:
            # Verify the disconnected device is the one we paired with
            if self.ctx.btd and self.ctx.btd.remote_address == address:
                logging.info(
                    "Pairing Mode: Paired device %s disconnected. Stopping pairing mode",
                    address,
                )

                async def schedule_pairing_stop():
                    # Use |None| to indicate pairing is done.
                    await self.pairing_events.put((None, None))

                asyncio.run_coroutine_threadsafe(
                    schedule_pairing_stop(),
                    self.pairing_loop,
                )

    @check_server_ready
    async def GetRandomAddress(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> security_pb2.GetRandomAddressResponse:
        if not self.ctx.privacy:
            logging.warning("Privacy mode is not enabled.")
        address = self.ctx.btd.GetRandomAddress()
        if address == "00:00:00:00:00:00":
            logging.warning(
                "Device is not advertising or advertising without RPA."
            )
        return security_pb2.GetRandomAddressResponse(address=address)
