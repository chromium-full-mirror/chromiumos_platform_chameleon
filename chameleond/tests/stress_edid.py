#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
"""EDID stress test - present lots of EDIDs to the DUT

This test cycles through a list of EDIDs and verifies that the DUT
recognizes the EDID and applies the correct resolution.

Based on pawel.py (b/238634042#comment2), thanks, panikiel@!
"""

import argparse
import codecs
import itertools
import os
import random
import sys
import time

import six.moves.xmlrpc_client


# TODO(b/268527894): can we pass in a JSON file of EDIDs from the command line?

# The list of EDIDs is carefully arranged so that the expected resolution is
# never the same twice in a row; this will help us find "stuck EDID" problems
# sooner, since if the list had two 1920x1080 monitors in a row and the
# first EDID got stuck, we wouldn't detect it with the second EDID because
# the resolution from the first would match what we expected from the second.
# This list includes some duplicates so the resolution always changes.
edids = [
    ('edids/daily/4K_ACER_BX320HK_HDMI.txt', [3840, 2160]),
    ('edids/daily/ACI_9155_ASUS_VH238_HDMI.txt', [1920, 1080]),
    ('edids/daily/4K_HP_Spectre32_HDMI.txt', [3840, 2160]),
    ('edids/daily/ACR_314_Acer_T232HL_HDMI.txt', [1920, 1080]),
    ('edids/daily/CEI_31032_Crestron_HDMI.txt',  [1280, 720]),
    ('edids/daily/ACR_5429_H6510BD_HDMI.txt', [1920, 1080]),
    ('edids/daily/AMX_2150_DVX-2150_HDMI.txt', [1920, 1200]),
    ('edids/daily/CEI_0_Crestron_HDMI.txt', [1920, 1080]),
    ('edids/daily/DEL_40976_DELL_2405FPW_HDMI.txt', [1920,1200]),
    ('edids/daily/CVT_3_CVT_TV_HDMI.txt', [1920,1080]),
    ('edids/daily/DEL_40983_DELL_2407WFP_HDMI.txt', [1920,1200]),
    ('edids/daily/DEL_16544_DELL_P2314T_HDMI.txt', [1920,1080]),
    ('edids/daily/DEL_61462_DELL_U2410_HDMI.txt', [1920,1200]),
    ('edids/daily/DEL_16545_DELL_P2314T_HDMI.txt', [1920,1080]),
    ('edids/daily/EXN_0_Extron_HDMI_HDMI.txt', [1280,720]),
    ('edids/daily/DTV_0_DTV_HDMI.txt', [1920,1080]),
    ('edids/daily/DTV_0_Kogan_TV_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_10346_HP_ZR24w_HDMI.txt', [1920,1200]),
    ('edids/daily/ELO_8705_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_10581_HP_ZR2440w_HDMI.txt', [1920,1200]),
    ('edids/daily/EXN_0_EXTRON_D_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_10582_HP_ZR2440w_HDMI.txt', [1920,1200]),
    ('edids/daily/GSM_1_LG_TV_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_12447_HP_Z24i_HDMI.txt', [1920,1200]),
    ('edids/daily/GSM_22594_D2342P_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_9846_HP_LP2465_HDMI.txt', [1920,1200]),
    ('edids/daily/GSM_23155_22CV241_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_9976_HP_LP2475w_HDMI.txt', [1920,1200]),
    ('edids/daily/GSM_50200_LG_TV_HDMI.txt', [1920,1080]),
    ('edids/daily/4K_ACER_BX320HK_HDMI.txt', [3840, 2160]), # dup
    ('edids/daily/GSM_50294_M3704C_HDMI.txt', [1920,1080]),
    ('edids/daily/CEI_31032_Crestron_HDMI.txt',  [1280, 720]),  # dup
    ('edids/daily/HEC_48_HDMI_HDMI.txt', [1920,1080]),
    ('edids/daily/AMX_2150_DVX-2150_HDMI.txt', [1920, 1200]),   # dup
    ('edids/daily/IFS_65330_InFocus_3118D_HDMI.txt', [1920,1080]),
    ('edids/daily/DEL_40983_DELL_2407WFP_HDMI.txt', [1920,1200]),   # dup
    ('edids/daily/JVC_37393_ILAFPJ_--_XH2_HDMI.txt', [1920,1080]),
    ('edids/daily/EXN_0_Extron_HDMI_HDMI.txt', [1280,720]), # dup
    ('edids/daily/DEL_61463_DELL_U2410_DP.txt', [1920, 1200]),
    ('edids/daily/MEL_18545_MDT551S_HDMI.txt', [1920,1080]),
    ('edids/daily/HWP_10580_HP_ZR2440w_DP.txt', [1920, 1200]),
    ('edids/daily/ACI_9713_ASUS_VE258_DP.txt', [1920,1080]),
    ('edids/daily/DEL_16443_DELL_2208WFP_DP.txt', [1680, 1050]),
    ('edids/daily/DEL_16543_DELL_P2314T_DP.txt', [1920, 1080]),
    ('edids/daily/HWP_10345_HP_ZR24w_DP.txt', [1920, 1200]),
    ('edids/daily/ACI_9713_ASUS_VE258_DP.txt', [1920,1080]),
    ('edids/daily/HWP_12446_HP_Z24i_DP.txt', [1920, 1200]),
]

# Map ports strings to numbers that chameleond uses
port_id_map = {
    'dp1' : 0,
    'dp2' : 1,
    'hdmi1' : 2,
    'hdmi2' : 3,
}



def read_edid(filename):
    """Read a text-format EDID and turn it into a binary string

    The EDIDs are stored in text files as ASCII hex digits with
    no intervening spaces, e.g.

        00ffffffffffff0022f06c2801010101
        0c170104b5402878e28d85ad4f35b125
        ...

    This function reads the text from the file, decodes it from hex
    into bytes, and then pads out to 256 bytes because the Chameleon
    wants the EDIDs to always be 256 bytes long.

    Args:
        filename: EDID file, with directory if needed to access it
    """
    edid = b''
    for line in open(filename).readlines():
        edid += codecs.decode(line.strip(), 'hex')
    return edid.ljust(256, b'\0')



def run_edid_test(port_id, pause_flag, path):
    """Apply each EDID and check that the video resolution matches expected

    Args:
        port_id: port number (0-3) of which port to use
        pause_flag: True if we should pause for input when there is a failure
        path: where to look for the EDIDs
    """
    chameleon = six.moves.xmlrpc_client.ServerProxy('http://localhost:9992')

    for (edid_name, exp_res) in itertools.cycle(edids):
        delay = random.uniform(2, 5)
        chameleon.Unplug(port_id)
        time.sleep(delay)
        edid = read_edid(os.path.join(os.path.expanduser(path),edid_name))
        edid_id = chameleon.CreateEdid(six.moves.xmlrpc_client.Binary(edid))
        chameleon.ApplyEdid(port_id, edid_id)
        chameleon.DestroyEdid(edid_id)
        chameleon.Plug(port_id)

        if not chameleon.WaitVideoInputStable(port_id, 10):
            print(edid_name, 'TIMEOUT: delay =', delay)
            continue

        res = chameleon.DetectResolution(port_id)
        if res == exp_res:
            print(edid_name, 'OK', res)
        else:
            print(edid_name, 'WRONG: expected ', exp_res, 'got', res, 'delay =', delay)
            if pause_flag:
                input('Press Enter to continue.')



def main():
    """Run an EDID stress test

    This test is intended to run directly on the Chameleon device.
    It will also work if you have an ssh connection with port 9992
    forwarded to the Chamaleon.

    This test has an internal list of several EDIDs that have caused issues
    in the past: a DUT didn't recognize it correctly, the ITE chip and/or
    the MCDP2900 modified/corrupted bytes along the way, things like that.
    The test applies each EDID and checks that the resolution of the video
    output from the DUT matches what is expected based on the EDID.
    """
    parser = argparse.ArgumentParser(
        description=main.__doc__,
        formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument('--port', type=str, required=True,
        help='Port name or number to use (0-3, DP1, DP2, HDMI1, HDMI2)')
    parser.add_argument('--pause', action='store_true', dest='pause_flag',
        required=False, help="Pause if the resolution doesn't match the EDID")
    parser.add_argument('--path', type=str, required=False, default='.',
        help='Specify where the EDID files are located')
    parser.add_argument('--autotest', action='store_const', dest='path',
        const='~/chromiumos/src/third_party/autotest/files/server/site_tests/display_EdidStress/test_data/',
        help='Use the default autotest path for EDIDs that most ChromeOS developers have. Do not use --path with this option')

    args = parser.parse_args()

    if args.port.lower() in port_id_map:
        port_id = port_id_map[args.port.lower()]
    else:
        port_id = int(args.port)

    run_edid_test(port_id, args.pause_flag, args.path)

    return True



if __name__ == '__main__':
    sys.exit(not int(main()))
