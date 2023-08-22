# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Utilities for analog audio testbed.

The analog audio testbed consists of:
a. Raspberry Pi 4B
b. an External USB Soundcard
c. a 3-channel relay to control TRRS circuit

Here are the helper functions we need.
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import logging
import re
import subprocess

from RPi import GPIO

LIST_OF_RPI_GPIO_PINs = [20, 21, 26]

def Exists():
    """Returns a Boolean of existence of analog audio testbed.

    In the current testbed setup, the existence of relay and external USB sound
    card is bounded together.

    Returns:
        True if USB sound card is attached. False otherwise.
    """
    logging.info("Checking the existence of analog audio testbed...")
    output = subprocess.check_output(['aplay','-l']).decode('utf-8')
    ext_card = re.search("([\d]): ICUSBAUDIO7D", output)
    return bool(ext_card)

def SwitchRelay(active):
    """Switch the NO (normally opened) Relay.

    The relay is used to connect / disconnect the circuit of TRRS cable.

    The TRRS audio jack hardware detection on DUT is based on the hardware
    impedance of injected audio jack (cable). However, it is very difficult
    to adjust the hardware impedance such that both Pi and DUT to see each
    other as Headphone + Mic (and vice versa).

    To use Pi + external USB sound card, we need both:
    a. DUT Hardware detection, which will happen when boot / reboot.
    b. Testbed TRRS cable circuit connection

    For the current setup, the DUT can detect both Headphone and Mic when
    the circuit is DISCONNECTED. The circuit will stay open (DISCONNECTED),
    so hardware detection will be always good.

    To use the testbed, we need to close (CONNECT) the circuit AFTER the
    DUT hardware detection.

    Input:
        True if you want to connect the circuit.
        False if you want to disconnect the circuit (for hardware detection)
    """
    logging.info("Switching GPIO Relay. TRRS Circuit connection: %s", active)
    GPIO.setmode(GPIO.BCM)
    for pin in LIST_OF_RPI_GPIO_PINs:
        GPIO.setup(pin, GPIO.OUT)
        GPIO.output(pin, 0 if active else 1)
