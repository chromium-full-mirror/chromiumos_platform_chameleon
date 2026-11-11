# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""HID grpc interface."""

import time

from blueship import hid_grpc_aio
from blueship import hid_pb2
from chameleond.bluetooth_grpc.blueship.server.utils import check_server_ready
from google.protobuf import empty_pb2
import grpc


class HIDService(hid_grpc_aio.HIDServicer):
    """Service to trigger Chameleon HID procedures."""

    # Delay after each keyboard traffic in seconds
    KEYBOARD_DELAY = 0.01

    # Delay after each mouse traffic in seconds
    MOUSE_DELAY = 0.01

    # Delay after each gamepad traffic in seconds
    GAMEPAD_DELAY = 0.01

    GAMEPAD_BUTTON_MAP = {
        hid_pb2.GAMEPAD_BUTTON_A: "GAMEPAD_BUTTON_A",
        hid_pb2.GAMEPAD_BUTTON_B: "GAMEPAD_BUTTON_B",
        hid_pb2.GAMEPAD_BUTTON_X: "GAMEPAD_BUTTON_X",
        hid_pb2.GAMEPAD_BUTTON_Y: "GAMEPAD_BUTTON_Y",
        hid_pb2.GAMEPAD_BUTTON_DPAD_UP: "GAMEPAD_BUTTON_UP",
        hid_pb2.GAMEPAD_BUTTON_DPAD_DOWN: "GAMEPAD_BUTTON_DOWN",
        hid_pb2.GAMEPAD_BUTTON_DPAD_LEFT: "GAMEPAD_BUTTON_LEFT",
        hid_pb2.GAMEPAD_BUTTON_DPAD_RIGHT: "GAMEPAD_BUTTON_RIGHT",
        hid_pb2.GAMEPAD_BUTTON_LEFT_BUMPER: "GAMEPAD_BUTTON_LEFT_BUMPER",
        hid_pb2.GAMEPAD_BUTTON_RIGHT_BUMPER: "GAMEPAD_BUTTON_RIGHT_BUMPER",
        hid_pb2.GAMEPAD_BUTTON_LEFT_THUMBSTICK: "GAMEPAD_LEFT_THUMBSTICK",
        hid_pb2.GAMEPAD_BUTTON_RIGHT_THUMBSTICK: "GAMEPAD_RIGHT_THUMBSTICK",
        hid_pb2.GAMEPAD_BUTTON_START: "GAMEPAD_BUTTON_START",
    }

    GAMEPAD_STICK_MAP = {
        hid_pb2.GAMEPAD_THUMBSTICK_LEFT: "GAMEPAD_LEFT_THUMBSTICK",
        hid_pb2.GAMEPAD_THUMBSTICK_RIGHT: "GAMEPAD_RIGHT_THUMBSTICK",
    }

    GAMEPAD_TRIGGER_MAP = {
        hid_pb2.GAMEPAD_TRIGGER_LEFT: "GAMEPAD_BUTTON_LEFT_TRIGGER",
        hid_pb2.GAMEPAD_TRIGGER_RIGHT: "GAMEPAD_BUTTON_RIGHT_TRIGGER",
    }

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context

    @check_server_ready
    async def PressKey(
        self,
        request: hid_pb2.KeyPressRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.KeyboardPressSingleKey(request.key)
        # A shortcut solution to ensure the event is sent
        time.sleep(self.KEYBOARD_DELAY)
        return empty_pb2.Empty()

    @check_server_ready
    async def ReleaseKey(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.KeyboardReleaseAllKey()
        # A shortcut solution to ensure the event is sent
        time.sleep(self.KEYBOARD_DELAY)
        return empty_pb2.Empty()

    @check_server_ready
    async def MouseMove(
        self,
        request: hid_pb2.MouseMoveRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.Move(
            request.delta_x, request.delta_y, delay=self.MOUSE_DELAY
        )
        return empty_pb2.Empty()

    @check_server_ready
    async def MouseScroll(
        self,
        request: hid_pb2.MouseScrollRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.Scroll(
            request.steps
        )
        return empty_pb2.Empty()

    @check_server_ready
    async def GamepadButtonPress(
        self,
        request: hid_pb2.GamepadButtonPressRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        button = self.GAMEPAD_BUTTON_MAP.get(request.button)
        if not button:
            context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                f"Unsupported or unspecified gamepad button: {request.button}",
            )
        self.ctx.btd.GamepadPressButtons(button)
        if request.auto_release:
            time.sleep(self.GAMEPAD_DELAY)
            self.ctx.btd.GamepadReleaseAllButtons()
        return empty_pb2.Empty()

    @check_server_ready
    async def GamepadThumbstickMove(
        self,
        request: hid_pb2.GamepadThumbstickMoveRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        stick = self.GAMEPAD_STICK_MAP.get(request.stick)
        if not stick:
            context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                f"Unsupported or unspecified gamepad thumbstick: {request.stick}",
            )
        self.ctx.btd.GamepadThumbstickMove(
            stick, request.delta_x, request.delta_y
        )
        if request.auto_release:
            time.sleep(self.GAMEPAD_DELAY)
            self.ctx.btd.GamepadReleaseAllButtons()
        return empty_pb2.Empty()

    @check_server_ready
    async def GamepadTriggerPress(
        self,
        request: hid_pb2.GamepadTriggerPressRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        trigger = self.GAMEPAD_TRIGGER_MAP.get(request.trigger)
        if not trigger:
            context.abort(
                grpc.StatusCode.INVALID_ARGUMENT,
                f"Unsupported or unspecified gamepad trigger: {request.trigger}",
            )
        self.ctx.btd.GamepadTriggerButtonsPress(trigger, request.value)
        if request.auto_release:
            time.sleep(self.GAMEPAD_DELAY)
            self.ctx.btd.GamepadReleaseAllButtons()
        return empty_pb2.Empty()

    @check_server_ready
    async def ReleaseGamepad(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.GamepadReleaseAllButtons()
        time.sleep(self.GAMEPAD_DELAY)
        return empty_pb2.Empty()

    @check_server_ready
    async def ExecuteGamepadBulkActions(
        self,
        request: hid_pb2.GamepadBulkActionsRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        interval = (
            request.interval_seconds
            if request.interval_seconds > 0
            else self.GAMEPAD_DELAY
        )
        for item in request.actions:
            action_type = item.WhichOneof("action")
            if action_type == "button_press":
                button = self.GAMEPAD_BUTTON_MAP.get(item.button_press)
                if button:
                    self.ctx.btd.GamepadPressButtons(button)
            elif action_type == "thumbstick_move":
                stick = self.GAMEPAD_STICK_MAP.get(item.thumbstick_move.stick)
                if stick:
                    self.ctx.btd.GamepadThumbstickMove(
                        stick,
                        item.thumbstick_move.delta_x,
                        item.thumbstick_move.delta_y,
                    )
            elif action_type == "trigger_press":
                trigger = self.GAMEPAD_TRIGGER_MAP.get(
                    item.trigger_press.trigger
                )
                if trigger:
                    self.ctx.btd.GamepadTriggerButtonsPress(
                        trigger, item.trigger_press.value
                    )
            elif action_type == "release_all":
                self.ctx.btd.GamepadReleaseAllButtons()
            time.sleep(interval)
        return empty_pb2.Empty()

