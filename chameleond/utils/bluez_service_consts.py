# -*- coding: utf-8 -*-

# Copyright 2019 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Constants for Bluez services on Raspberry Pi."""

from __future__ import print_function

import os

from chameleond.utils.bluetooth_peripheral_kit import PeripheralKit

BLUEZ_SERVICE_NAME = 'org.chromium.autotest.btkbservice'
BLUEZ_SERVICE_PATH = '/org/chromium/autotest/btkbservice'
BLUEZ_PROFILE_PATH = '/org/chromium/autotest/btkbprofile'

CLASS_OF_SERVICE_MASK = 0xFFE000
CLASS_OF_DEVICE_MASK = 0x001FFF

BTD_CONF_FILE = '/lib/systemd/system/bluetooth.service'

# https://www.bluetooth.com/specifications/assigned-numbers/baseband/
PERIPHERAL_DEVICE_CLASS = {
    PeripheralKit.KEYBOARD: 0x002540,
    PeripheralKit.MOUSE:    0x002580,
    PeripheralKit.PHONE:    0x7A020C,

    # Service Class: Limited Discoverable Mode,
    #                Audio (Speaker, Microphone, Headset service)
    # Major Device Class: Audio / Video
    # Minor Device Class: Headphones
    PeripheralKit.BLUETOOTH_AUDIO:    0x202418,
    PeripheralKit.FAST_PAIR: 0x002540,
}

PERIPHERAL_DEVICE_NAME = {
    PeripheralKit.KEYBOARD: 'KEYBD_REF',
    PeripheralKit.MOUSE:    'MOUSE_REF',
    PeripheralKit.PHONE:    'PHONE_REF',
    PeripheralKit.BLUETOOTH_AUDIO:    'RASPI_AUDIO',
    PeripheralKit.FAST_PAIR: 'FAST_PAIR_REF',
}

# https://www.bluetooth.com/wp-content/uploads/Sitecore-Media-Library/Gatt/Xml/Characteristics/org.bluetooth.characteristic.gap.appearance.xml
PERIPHERAL_DEVICE_APPEARANCE = {
    PeripheralKit.KEYBOARD: [0xc1, 0x03],
    PeripheralKit.MOUSE:    [0xc2, 0x03],
    PeripheralKit.PHONE:    [0x40, 0x00],
    PeripheralKit.BLUETOOTH_AUDIO:    [0x80, 0x02],   # Generic Media Player
    PeripheralKit.FAST_PAIR: [0x00, 0x00], # Unknown
}

SERVICE_PROFILE_SDP_PATH = {
    PeripheralKit.KEYBOARD: (os.path.dirname(os.path.abspath(__file__)) +
                             '/keyboard_sdp_record.xml'),
    PeripheralKit.MOUSE:    (os.path.dirname(os.path.abspath(__file__)) +
                             '/mouse_sdp_record.xml'),

    # TODO: find a suitable xml for Bluetooth audio device.
    PeripheralKit.BLUETOOTH_AUDIO: (os.path.dirname(os.path.abspath(__file__)) +
                                    '/keyboard_sdp_record.xml'),
}

"""
Both AVRCP and A2DP profiles will try to role switch into central role on any
L2CAP connection, which causes unexpected behavior when emulating a HID device.
Here, we remove the bluetoothd avrcp and a2dp modules if we aren't emulating an
audio device.

The uppercased '-P' flag disables the comma-separated plugins that follow it
"""
AUDIO_BTD_FLAGS = '-d -P input'
NON_AUDIO_BTD_FLAGS = '-d -P input,avrcp,a2dp'

PERIPHERAL_BTD_FLAGS = {
    PeripheralKit.KEYBOARD: NON_AUDIO_BTD_FLAGS,
    PeripheralKit.MOUSE: NON_AUDIO_BTD_FLAGS,
    PeripheralKit.PHONE: NON_AUDIO_BTD_FLAGS,
    PeripheralKit.BLUETOOTH_AUDIO: AUDIO_BTD_FLAGS,
    PeripheralKit.FAST_PAIR: NON_AUDIO_BTD_FLAGS,
}

HID_SERVICE_UUID = '00001124-0000-1000-8000-00805f9b34fb'

PERIPHERAL_PROFILE_UUID = {
    PeripheralKit.KEYBOARD: HID_SERVICE_UUID,
    PeripheralKit.MOUSE:    HID_SERVICE_UUID,
}


keymap = {
    'KEY_RESERVED' : 0,
    'KEY_ESC' : 41,
    'KEY_1' : 30,
    'KEY_2' : 31,
    'KEY_3' : 32,
    'KEY_4' : 33,
    'KEY_5' : 34,
    'KEY_6' : 35,
    'KEY_7' : 36,
    'KEY_8' : 37,
    'KEY_9' : 38,
    'KEY_0' : 39,
    'KEY_MINUS' : 45,
    'KEY_EQUAL' : 46,
    'KEY_BACKSPACE' : 42,
    'KEY_TAB' : 43,
    'KEY_Q' : 20,
    'KEY_W' : 26,
    'KEY_E' : 8,
    'KEY_R' : 21,
    'KEY_T' : 23,
    'KEY_Y' : 28,
    'KEY_U' : 24,
    'KEY_I' : 12,
    'KEY_O' : 18,
    'KEY_P' : 19,
    'KEY_LEFTBRACE' : 47,
    'KEY_RIGHTBRACE' : 48,
    'KEY_ENTER' : 40,
    'KEY_LEFTCTRL' : 224,
    'KEY_A' : 4,
    'KEY_S' : 22,
    'KEY_D' : 7,
    'KEY_F' : 9,
    'KEY_G' : 10,
    'KEY_H' : 11,
    'KEY_J' : 13,
    'KEY_K' : 14,
    'KEY_L' : 15,
    'KEY_SEMICOLON' : 51,
    'KEY_APOSTROPHE' : 52,
    'KEY_GRAVE' : 53,
    'KEY_LEFTSHIFT' : 225,
    'KEY_BACKSLASH' : 50,
    'KEY_Z' : 29,
    'KEY_X' : 27,
    'KEY_C' : 6,
    'KEY_V' : 25,
    'KEY_B' : 5,
    'KEY_N' : 17,
    'KEY_M' : 16,
    'KEY_COMMA' : 54,
    'KEY_PERIOD' : 55,
    'KEY_SLASH' : 56,
    'KEY_RIGHTSHIFT' : 229,
    'KEY_KPASTERISK' : 85,
    'KEY_LEFTALT' : 226,
    'KEY_SPACE' : 44,
    'KEY_CAPSLOCK' : 57,
    'KEY_F1' : 58,
    'KEY_F2' : 59,
    'KEY_F3' : 60,
    'KEY_F4' : 61,
    'KEY_F5' : 62,
    'KEY_F6' : 63,
    'KEY_F7' : 64,
    'KEY_F8' : 65,
    'KEY_F9' : 66,
    'KEY_F10' : 67,
    'KEY_NUMLOCK' : 83,
    'KEY_SCROLLLOCK' : 71,
    'KEY_KP7' : 95,
    'KEY_KP8' : 96,
    'KEY_KP9' : 97,
    'KEY_KPMINUS' : 86,
    'KEY_KP4' : 92,
    'KEY_KP5' : 93,
    'KEY_KP6' : 94,
    'KEY_KPPLUS' : 87,
    'KEY_KP1' : 89,
    'KEY_KP2' : 90,
    'KEY_KP3' : 91,
    'KEY_KP0' : 98,
    'KEY_KPDOT' : 99,
    'KEY_ZENKAKUHANKAKU' : 148,
    'KEY_102ND' : 100,
    'KEY_F11' : 68,
    'KEY_F12' : 69,
    'KEY_RO' : 135,
    'KEY_KATAKANA' : 146,
    'KEY_HIRAGANA' : 147,
    'KEY_HENKAN' : 138,
    'KEY_KATAKANAHIRAGANA' : 136,
    'KEY_MUHENKAN' : 139,
    'KEY_KPJPCOMMA' : 140,
    'KEY_KPENTER' : 88,
    'KEY_RIGHTCTRL' : 228,
    'KEY_KPSLASH' : 84,
    'KEY_SYSRQ' : 70,
    'KEY_RIGHTALT' : 230,
    'KEY_HOME' : 74,
    'KEY_UP' : 82,
    'KEY_PAGEUP' : 75,
    'KEY_LEFT' : 80,
    'KEY_RIGHT' : 79,
    'KEY_END' : 77,
    'KEY_DOWN' : 81,
    'KEY_PAGEDOWN' : 78,
    'KEY_INSERT' : 73,
    'KEY_DELETE' : 76,
    'KEY_MUTE' : 239,
    'KEY_VOLUMEDOWN' : 238,
    'KEY_VOLUMEUP' : 237,
    'KEY_POWER' : 102,
    'KEY_KPEQUAL' : 103,
    'KEY_PAUSE' : 72,
    'KEY_KPCOMMA' : 133,
    'KEY_HANGEUL' : 144,
    'KEY_HANJA' : 145,
    'KEY_YEN' : 137,
    'KEY_LEFTMETA' : 227,
    'KEY_RIGHTMETA' : 231,
    'KEY_COMPOSE' : 101,
    'KEY_STOP' : 243,
    'KEY_AGAIN' : 121,
    'KEY_PROPS' : 118,
    'KEY_UNDO' : 122,
    'KEY_FRONT' : 119,
    'KEY_COPY' : 124,
    'KEY_OPEN' : 116,
    'KEY_PASTE' : 125,
    'KEY_FIND' : 244,
    'KEY_CUT' : 123,
    'KEY_HELP' : 117,
    'KEY_CALC' : 251,
    'KEY_SLEEP' : 248,
    'KEY_WWW' : 240,
    'KEY_COFFEE' : 249,
    'KEY_BACK' : 241,
    'KEY_FORWARD' : 242,
    'KEY_EJECTCD' : 236,
    'KEY_NEXTSONG' : 235,
    'KEY_PLAYPAUSE' : 232,
    'KEY_PREVIOUSSONG' : 234,
    'KEY_STOPCD' : 233,
    'KEY_REFRESH' : 250,
    'KEY_EDIT' : 247,
    'KEY_SCROLLUP' : 245,
    'KEY_SCROLLDOWN' : 246,
    'KEY_F13' : 104,
    'KEY_F14' : 105,
    'KEY_F15' : 106,
    'KEY_F16' : 107,
    'KEY_F17' : 108,
    'KEY_F18' : 109,
    'KEY_F19' : 110,
    'KEY_F20' : 111,
    'KEY_F21' : 112,
    'KEY_F22' : 113,
    'KEY_F23' : 114,
    'KEY_F24' : 115
}

modmap = {
    'MOD_NONE'       : 0,
    'MOD_CTRL_LEFT'  : (1<<0),
    'MOD_SHIFT_LEFT' : (1<<1),
    'MOD_ALT_LEFT'   : (1<<2),
    'MOD_GUI_LEFT'   : (1<<3),
    'MOD_CTRL_RIGHT' : (1<<4),
    'MOD_SHIFT_RIGHT': (1<<5),
    'MOD_ALT_RIGHT'  : (1<<6),
    'MOD_GUI_RIGHT'  : (1<<7),
}
