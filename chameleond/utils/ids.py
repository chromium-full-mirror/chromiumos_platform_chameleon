# -*- coding: utf-8 -*-
# Copyright 2014 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""IDs shared with Chameleond drivers."""

# IDs of ports or devices
DP1 = 1
DP2 = 2
HDMI = 3
VGA = 4
MIC = 5
LINEIN = 6
LINEOUT = 7
USB_AUDIO_IN = 8
USB_AUDIO_OUT = 9
USB_KEYBOARD = 10
USB_TOUCH = 11
BLUETOOTH_HID_KEYBOARD = 12
BLUETOOTH_HID_GAMEPAD = 13
BLUETOOTH_HID_MOUSE = 14
BLUETOOTH_HID_COMBO = 15
BLUETOOTH_HID_JOYSTICK = 16
AVSYNC_PROBE = 17
AUDIO_BOARD = 18
MOTOR_BOARD = 19
BLUETOOTH_HOG_KEYBOARD = 20
BLUETOOTH_HOG_GAMEPAD = 21
BLUETOOTH_HOG_MOUSE = 22
BLUETOOTH_HOG_COMBO = 23
BLUETOOTH_HOG_JOYSTICK = 24
USB_PRINTER = 25
BLUETOOTH_A2DP_SINK = 26
BLE_MOUSE = 27
BLE_KEYBOARD = 28
BLUETOOTH_BASE = 29
BLUETOOTH_TESTER = 30
BLE_PHONE = 31
BLUETOOTH_AUDIO = 32
BLE_FAST_PAIR = 33

# device names
DEVICE_NAMES = {
    DP1: 'dp1',
    DP2: 'dp2',
    HDMI: 'hdmi',
    VGA: 'vga',
    MIC: 'mic',
    LINEIN: 'linein',
    LINEOUT: 'lineout',
    USB_AUDIO_IN: 'usb_audio_in',
    USB_AUDIO_OUT: 'usb_audio_out',
    USB_KEYBOARD: 'usb_keyboard',
    USB_TOUCH: 'usb_touch',
    BLUETOOTH_HID_KEYBOARD: 'bluetooth_hid_keyboard',
    BLUETOOTH_HID_GAMEPAD: 'bluetooth_hid_gamepad',
    BLUETOOTH_HID_MOUSE: 'bluetooth_hid_mouse',
    BLUETOOTH_HID_COMBO: 'bluetooth_hid_combo',
    BLUETOOTH_HID_JOYSTICK: 'bluetooth_hid_joystick',
    AVSYNC_PROBE: 'avsync_probe',
    AUDIO_BOARD: 'audio_board',
    MOTOR_BOARD: 'motor_board',
    BLUETOOTH_HOG_KEYBOARD: 'bluetooth_hog_keyboard',
    BLUETOOTH_HOG_GAMEPAD: 'bluetooth_hog_gamepad',
    BLUETOOTH_HOG_MOUSE: 'bluetooth_hog_mouse',
    BLUETOOTH_HOG_COMBO: 'bluetooth_hog_combo',
    BLUETOOTH_HOG_JOYSTICK: 'bluetooth_hog_joystick',
    USB_PRINTER: 'usb_printer',
    BLUETOOTH_A2DP_SINK: 'bluetooth_a2dp_sink',
    BLE_MOUSE: 'ble_mouse',
    BLE_KEYBOARD: 'ble_keyboard',
    BLUETOOTH_BASE: 'bluetooth_base',
    # Bluetooth tester allows us to query DUT state from the
    # chameleon peer
    BLUETOOTH_TESTER: 'bluetooth_tester',
    # A phone device that supports Bluetooth
    BLE_PHONE: 'ble_phone',
    BLUETOOTH_AUDIO: 'bluetooth_audio',
    # A Bluetooth peripheral which implements the Fast Pair protocol
    BLE_FAST_PAIR: 'ble_fast_pair',
}


# Input/output ports
INPUT_PORTS = [DP1, DP2, HDMI, VGA, MIC, LINEIN, USB_AUDIO_IN]
OUTPUT_PORTS = [LINEOUT, USB_AUDIO_OUT]

# Ports that support audio/video
AUDIO_PORTS = [DP1, DP2, HDMI, MIC, LINEIN, LINEOUT, USB_AUDIO_IN,
               USB_AUDIO_OUT]
VIDEO_PORTS = [DP1, DP2, HDMI, VGA]

# Ports that support USB audio
USB_AUDIO_PORTS = [USB_AUDIO_IN, USB_AUDIO_OUT]

# Ports that support USB HID
USB_HID_PORTS = [USB_KEYBOARD, USB_TOUCH]

# Ports that support BLUETOOTH HID
BLUETOOTH_HID_PORTS = [BLUETOOTH_HID_KEYBOARD,
                       BLUETOOTH_HID_GAMEPAD,
                       BLUETOOTH_HID_MOUSE,
                       BLUETOOTH_HID_COMBO,
                       BLUETOOTH_HID_JOYSTICK]

# Ports that support BLUETOOTH HID over GATT (LE)
BLUETOOTH_HOG_PORTS = [BLUETOOTH_HOG_KEYBOARD,
                       BLUETOOTH_HOG_GAMEPAD,
                       BLUETOOTH_HOG_MOUSE,
                       BLUETOOTH_HOG_COMBO,
                       BLUETOOTH_HOG_JOYSTICK,
                       BLE_MOUSE]

# Convenience methods
IsInputPort = lambda port_id: port_id in INPUT_PORTS
IsOutputPort = lambda port_id: port_id in OUTPUT_PORTS
IsAudioPort = lambda port_id: port_id in AUDIO_PORTS
IsVideoPort = lambda port_id: port_id in VIDEO_PORTS
IsUSBAudioPort = lambda port_id: port_id in USB_AUDIO_PORTS
IsUSBHIDPort = lambda port_id: port_id in USB_HID_PORTS
IsBluetoothHIDPort = lambda port_id: port_id in BLUETOOTH_HID_PORTS
IsBluetoothHOGPort = lambda port_id: port_id in BLUETOOTH_HOG_PORTS

# IDs of EDIDs
EDID_ID_DEFAULT = 0
EDID_ID_DISABLE = -1

# List of known RN42 serial numbers
RN42_SET = frozenset([
    'A9054Z4Q',
    'AK05MK4Q', # vaandres@ located at desk
    'AK05ML26', # ibezmenov@'s desk
    'A600YVZB', # shijinabraham@'s desk
    'A600CXAC', # chromeos1-dev-host1-chameleon
    'AK05MKYX', # chromeos1-dev-host2-chameleon
    'AK05MKZ6', # chromeos1-dev-host3-chameleon
    'A600YVW9', # chromeos1-dev-host5-chameleon
    'AK05MKZ8', # chromeos1-dev-host6-chameleon
    'AK05ML0K', # chromeos1-dev-host7-chameleon
    'AK05MKYF', # chromeos1-dev-host8-chameleon
    'AK05ML12', # chromeos1-dev-host9-chameleon
    'AK05MKZD', # chromeos1-dev-host10-chameleon
    'AK05ML11', # chromeos1-dev-host11-chameleon
    'AK05MKZ5', # chromeos1-dev-host12-chameleon
    'AK05MK6Z', # chromeos1-dev-host13-chameleon
    'AK05ML2S', # chromeos1-dev-host14-chameleon
    'AK05MKYW', # chromeos15-row1-rack1-host6-chameleon
    'AK05MKYV', # chromeos15-row1-rack3-host2-chameleon
    'AK05MKYS', # chromeos15-row1-rack3-host3-chameleon
    'A600YVS7', # chromeos15-row1-rack4-host1-chameleon
    'A600YVWY', # chromeos15-row1-rack4-host5-chameleon
    'A503SAS5', # chromeos15-row1-rack5-host1-chameleon
    'A503SATF', # chromeos15-row1-rack5-host2-chameleon
    'A503SAP9', # chromeos15-row1-rack5-host3-chameleon
    'A503SAON', # chromeos15-row1-rack5-host4-chameleon
    'A503SAQO', # chromeos15-row1-rack5-host5-chameleon
    'A600YW2F', # chromeos15-row1-rack5-host6-chameleon
    'A503SANM', # chromeos15-row1-rack5-host7-chameleon
    'AK05MKZ9', # chromeos15-row2-rack9-host5-chameleon
    'AK05MKYL', # chromeos15-row2-rack9-host2-chameleon
    'AK05ML0H', # chromeos15-row2-rack9-host3-chameleon
    'AK05MKZN', # chromeos15-row2-rack11-host3-chameleon
    'AK05MKYI', # chromeos15-row4-rack10-host1-chameleon
    'A600YVUV', # chromeos15-row2-rack6-host3-chameleon
    'A903FGC4', # tp101-chamber-top
    'AK04P335', # tp101-chamber-bot
    'AK05MKZ4', # chromeos15-row2-rack6-host1-chameleon
    'AK05MKYR', # chromeos15-row4-rack9-host3-chameleon
    'A600YVSQ', # chromeos15-row2-rack5-host2-chameleon
    'AK05MKYP', # chromeos15-row2-rack5-host5-chameleon
    'AK05MKYJ', # chromeos15-row2-rack10-host1-chameleon
    'AK05MKYD', # chromeos15-row2-rack11-host2-chameleon
    'AK05MKYK', # chromeos15-row4-rack9-host1-chameleon
    'AK05ML08', # chromeos15-row4-rack9-host2-chameleon
    'AL05BW7Z', # chromeos15-row5-rack1-host1-chameleon
    'AL05BWDF', # chromeos15-row5-rack1-host2-chameleon
    'AL05BW70', # chromeos15-row5-rack1-host3-chameleon
    'AL05BW93', # chromeos15-row5-rack1-host4-chameleon
    'AL05BWF8', # chromeos15-row5-rack1-host5-chameleon
    'AL05BW8E', # chromeos15-row5-rack1-host6-chameleon
    'AL05BW88', # chromeos15-row5-rack1-host7-chameleon
    'AK05ML16', # chromeos15-row5-rack3-host1-chameleon
    'AK05MKYB', # chromeos15-row5-rack3-host2-chameleon
    'AK05MKYY', # chromeos15-row5-rack3-host3-chameleon
    'AK05MKYE', # chromeos15-row5-rack3-host4-chameleon
    'AK05ML07', # chromeos15-row5-rack3-host5-chameleon
    'AK05MKZ2', # chromeos15-row5-rack3-host6-chameleon
    'AK05ML0D', # chromeos15-row5-rack3-host7-chameleon
    'AK05ML0V', # chromeos15-row4-rack11-host3-chameleon
    'AL05BW95', # chromeos15-row5-rack5-host1-chameleon
    'AL05BW8G', # chromeos15-row5-rack5-host2-chameleon
    'AL05BWDL', # chromeos15-row5-rack5-host3-chameleon
    # Add new RN42 serial numbers and location above this line
])

# List of known RN52 serial numbers
RN52_SET = frozenset([
    'AK0557CM',
    'AK0557AI',
    'AH03PORA', # vaandres@ located at desk
    'AK05578J', # ibezmenov@'s desk
    'AH03PZDC', # shijinabraham@'s desk
    'A5043N39', # chromeos1-dev-host1-chameleon
    'AH03PZFV', # chromeos1-dev-host2-chameleon
    'AH03PZHG', # chromeos1-dev-host3-chameleon
    'AK0557D6', # chromeos1-dev-host5-chameleon
    'AK0557CV', # chromeos1-dev-host6-chameleon
    'A5043MG6', # chromeos1-dev-host7-chameleon
    'A5043N1U', # chromeos1-dev-host8-chameleon
    'A5043MGO', # chromeos1-dev-host9-chameleon
    'A5043MFK', # chromeos1-dev-host10-chameleon
    'AH03PZEN', # chromeos1-dev-host11-chameleon
    'A5043N2L', # chromeos1-dev-host12-chameleon
    'A5043MGB', # chromeos1-dev-host13-chameleon
    'A5043N25', # chromeos1-dev-host14-chameleon
    'AK0557A1', # chromeos15-row1-rack1-host6-chameleon
    'AH03PZDI', # chromeos15-row1-rack3-host2-chameleon
    'AH03PZEM', # chromeos15-row1-rack3-host3-chameleon
    'AK055797', # chromeos15-row1-rack4-host1-chameleon
    'AH03PZHI', # chromeos15-row1-rack4-host5-chameleon
    'AH03PZF9', # chromeos15-row1-rack5-host1-chameleon
    'AH03PZH8', # chromeos15-row1-rack5-host2-chameleon
    'AH03PZGP', # chromeos15-row1-rack5-host3-chameleon
    'AK05575U', # chromeos15-row1-rack5-host4-chameleon
    'AK055796', # chromeos15-row1-rack5-host5-chameleon
    'AH03PZDB', # chromeos15-row1-rack5-host6-chameleon
    'AK05579P', # chromeos15-row1-rack5-host7-chameleon
    'AK0557BH', # chromeos15-row2-rack9-host5-chameleon
    'AK05579H', # chromeos15-row2-rack9-host2-chameleon
    'AK05578X', # chromeos15-row2-rack9-host3-chameleon
    'AH03PZH2', # chromeos15-row2-rack11-host3-chameleon
    'AK055761', # chromeos15-row4-rack10-host1-chameleon
    'AH03PZEO', # chromeos15-row2-rack6-host3-chameleon
    'AH03PZHX', # chromeos15-row2-rack6-host1-chameleon
    'AK0557B9', # chromeos15-row4-rack9-host3-chameleon
    'AH03PZDG', # chromeos15-row2-rack5-host2-chameleon
    'AK0557BG', # chromeos15-row2-rack5-host5-chameleon
    'AK055793', # chromeos15-row2-rack10-host1-chameleon
    'AK0557AX', # chromeos15-row2-rack11-host2-chameleon
    'AK0557C1', # chromeos15-row4-rack9-host1-chameleon
    'A5043N2R', # chromeos15-row4-rack9-host2-chameleon
    'AH03PZD9', # chromeos15-row5-rack1-host1-chameleon
    'A5043MFR', # chromeos15-row5-rack1-host2-chameleon
    'A5043N2B', # chromeos15-row5-rack1-host3-chameleon
    'A5043MGA', # chromeos15-row5-rack1-host4-chameleon
    'A5043MG8', # chromeos15-row5-rack1-host5-chameleon
    'A5043N1N', # chromeos15-row5-rack1-host6-chameleon
    'A5043N19', # chromeos15-row5-rack1-host7-chameleon
    'A5043N28', # chromeos15-row5-rack3-host1-chameleon
    'A5043MGL', # chromeos15-row5-rack3-host2-chameleon
    'A5043N26', # chromeos15-row5-rack3-host3-chameleon
    'A5043MGF', # chromeos15-row5-rack3-host4-chameleon
    'A5043N1O', # chromeos15-row5-rack3-host5-chameleon
    'A5043N1W', # chromeos15-row5-rack3-host6-chameleon
    'AK05576B', # chromeos15-row5-rack3-host7-chameleon
    'A5043N2Y', # chromeos15-row4-rack11-host3-chameleon
    'A5043MFO', # chromeos15-row5-rack5-host1-chameleon
    'A5043N2A', # chromeos15-row5-rack5-host2-chameleon
    'A5043N22', # chromeos15-row5-rack5-host3-chameleon
    # Add new RN52 serial numbers and location above this line
])
