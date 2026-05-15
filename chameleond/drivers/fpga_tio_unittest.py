# -*- coding: utf-8 -*-
# Copyright 2026 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Unit tests for AEC testing methods in ChameleondDriver."""

import os
import subprocess
import sys
import unittest
from unittest.mock import MagicMock
from unittest.mock import patch


# Mock missing 'serial' and 'btsocket' modules before importing fpga_tio
sys.modules["serial"] = MagicMock()
sys.modules["btsocket"] = MagicMock()

from chameleond.drivers import fpga_tio
from chameleond.utils import ids


class TestChameleondDriverAEC(unittest.TestCase):

    @patch("chameleond.drivers.fpga_tio.subprocess.check_output")
    def test_FindALSANode_success(self, mock_check_output):
        # Simulate output of `arecord -l`
        mock_check_output.return_value = (
            "card 4: UAC2Gadget [UAC2_Gadget], device 0: UAC2 PCM [UAC2 PCM]\n"
            "  Subdevices: 1/1\n"
            "  Subdevice #0: subdevice #0\n"
        )

        self_mock = MagicMock()
        node = fpga_tio.ChameleondDriver._FindALSANode(
            self_mock, "UAC2", is_capture=True
        )
        self.assertEqual(node, "plughw:4,0")

    @patch("chameleond.drivers.fpga_tio.subprocess.check_output")
    def test_FindALSANode_not_found(self, mock_check_output):
        # Simulate output without target pattern
        mock_check_output.return_value = "card 0: ALSA [Built-in Audio]"

        self_mock = MagicMock()
        with self.assertRaises(fpga_tio.DriverError):
            fpga_tio.ChameleondDriver._FindALSANode(
                self_mock, "UAC2", is_capture=True
            )

    @patch("chameleond.drivers.fpga_tio.subprocess.check_output")
    def test_FindALSANode_command_error(self, mock_check_output):
        # Simulate command error
        mock_check_output.side_effect = subprocess.CalledProcessError(
            1, "arecord"
        )

        self_mock = MagicMock()
        with self.assertRaises(fpga_tio.DriverError):
            fpga_tio.ChameleondDriver._FindALSANode(
                self_mock, "UAC2", is_capture=True
            )

    @patch("chameleond.drivers.fpga_tio.audio_utils")
    @patch("chameleond.drivers.fpga_tio.file_utils")
    @patch("chameleond.drivers.fpga_tio.subprocess.Popen")
    @patch("chameleond.drivers.fpga_tio.system_tools.SystemTools.GetToolPath")
    def test_StartRouteWithMultiTapDelay_success(
        self, mock_get_tool_path, mock_popen, mock_file_utils, mock_audio_utils
    ):
        # Setup mocks
        mock_get_tool_path.return_value = "/usr/bin/arecord"

        self_mock = MagicMock()
        self_mock._route_processes = None
        self_mock._FindALSANode.side_effect = ["plughw:8,0", "plughw:9,0"]
        self_mock._file_dict = {}

        def mock_get_file_token(path):
            filename = os.path.basename(path)
            return "fake_token_123", filename

        mock_file_utils.GetFileToken.side_effect = mock_get_file_token

        def mock_register_file_token(file_dict, token, filename):
            file_dict[token] = filename

        mock_file_utils.RegisterFileToken.side_effect = mock_register_file_token

        def mock_get_sox_cmd(node, delay):
            return ["sox", "-t", "wav", "-", "-t", "alsa", node, "echo"]

        mock_audio_utils.GetSoxEchoCommand.side_effect = mock_get_sox_cmd

        mock_audio_utils.GetArecordCommand.return_value = [
            "/usr/bin/arecord",
            "-D",
            "plughw:8,0",
            "-f",
            "cd",
            "-t",
            "wav",
        ]

        # Call method
        token = fpga_tio.ChameleondDriver.StartRouteWithMultiTapDelay(
            self_mock, ids.USB_AUDIO_IN, ids.USB_AUDIO_OUT, delay_in_sec=10
        )

        # Verify token is generated
        self.assertTrue(token)
        self.assertIn(token, self_mock._file_dict)
        filename = self_mock._file_dict[token]
        full_path = "/tmp/" + filename
        self.addCleanup(
            lambda: os.remove(full_path) if os.path.exists(full_path) else None
        )

        # Verify Popen called 3 times (pipeline)
        self.assertEqual(mock_popen.call_count, 3)

        # Verify GetArecordCommand called correctly
        mock_audio_utils.GetArecordCommand.assert_called_once_with("plughw:8,0")

        # Check arecord call
        arecord_args = mock_popen.call_args_list[0][0][0]
        self.assertIn("arecord", arecord_args[0])
        self.assertIn("plughw:8,0", arecord_args)

        # Check tee call
        tee_args = mock_popen.call_args_list[1][0][0]
        self.assertEqual(tee_args[0], "tee")
        self.assertIn(full_path, tee_args)

        # Check sox call
        sox_args = mock_popen.call_args_list[2][0][0]
        self.assertEqual(sox_args[0], "sox")
        self.assertIn("plughw:9,0", sox_args)

        # Verify state saved
        self.assertIsInstance(self_mock._route_processes, dict)
        self.assertIn("arecord", self_mock._route_processes)
        self.assertIn("tee", self_mock._route_processes)
        self.assertIn("sox", self_mock._route_processes)
        self.assertIsNotNone(self_mock._route_start_time)
        self.assertEqual(self_mock._route_delay, 10)

    def test_StartRouteWithMultiTapDelay_already_running(self):
        self_mock = MagicMock()
        self_mock._route_processes = {"arecord": MagicMock()}

        with self.assertRaises(fpga_tio.DriverError):
            fpga_tio.ChameleondDriver.StartRouteWithMultiTapDelay(
                self_mock, ids.USB_AUDIO_IN, ids.USB_AUDIO_OUT, delay_in_sec=10
            )

    def test_StartRouteWithMultiTapDelay_not_implemented_input(self):
        self_mock = MagicMock()
        self_mock._route_processes = None
        # Use invalid device ID
        with self.assertRaises(NotImplementedError):
            fpga_tio.ChameleondDriver.StartRouteWithMultiTapDelay(
                self_mock, ids.MIC, ids.USB_AUDIO_OUT, delay_in_sec=10
            )

    def test_StartRouteWithMultiTapDelay_node_not_found(self):
        self_mock = MagicMock()
        self_mock._route_processes = None
        # Simulate node not found by raising DriverError
        self_mock._FindALSANode.side_effect = fpga_tio.DriverError("Not found")

        with self.assertRaises(fpga_tio.DriverError):
            fpga_tio.ChameleondDriver.StartRouteWithMultiTapDelay(
                self_mock, ids.USB_AUDIO_IN, ids.USB_AUDIO_OUT, delay_in_sec=10
            )

    @patch("chameleond.drivers.fpga_tio.audio_utils")
    @patch("chameleond.drivers.fpga_tio.file_utils")
    @patch("chameleond.drivers.fpga_tio.subprocess.Popen")
    def test_StartRouteWithMultiTapDelay_popen_fails(
        self, mock_popen, mock_file_utils, mock_audio_utils
    ):
        self_mock = MagicMock()
        self_mock._route_processes = None
        self_mock._FindALSANode.side_effect = ["plughw:8,0", "plughw:9,0"]
        self_mock._file_dict = {}

        # Mock file_utils
        mock_file_utils.GetFileToken.return_value = ("token123", "file123")

        # Mock audio_utils
        mock_audio_utils.GetArecordCommand.return_value = ["arecord"]
        mock_audio_utils.GetSoxEchoCommand.return_value = ["sox"]

        # Mock Popen to succeed twice and fail on the 3rd call
        p1 = MagicMock()
        p2 = MagicMock()
        mock_popen.side_effect = [p1, p2, OSError("Fake popen error")]

        with self.assertRaises(fpga_tio.DriverError) as cm:
            fpga_tio.ChameleondDriver.StartRouteWithMultiTapDelay(
                self_mock, ids.USB_AUDIO_IN, ids.USB_AUDIO_OUT, delay_in_sec=10
            )

        self.assertIn("Failed to start pipeline", str(cm.exception))

        # Verify p1 and p2 were terminated
        p1.terminate.assert_called_once()
        p2.terminate.assert_called_once()

    @patch("chameleond.drivers.fpga_tio.time.time")
    def test_StopRouteWithMultiTapDelay_success(self, mock_time):
        self_mock = MagicMock()
        p1 = MagicMock()
        p2 = MagicMock()
        p3 = MagicMock()
        self_mock._route_processes = {"arecord": p1, "tee": p2, "sox": p3}
        self_mock._route_start_time = 1000.0
        self_mock._route_delay = 10

        # Simulate time passed: 1000 + 25 = 1025 > 1000 + 20
        mock_time.return_value = 1025.0

        fpga_tio.ChameleondDriver.StopRouteWithMultiTapDelay(self_mock)

        # Verify processes were terminated
        p1.terminate.assert_called_once()
        p2.terminate.assert_called_once()
        p3.terminate.assert_called_once()

        # Verify state reset
        self.assertIsNone(self_mock._route_processes)
        self.assertIsNone(self_mock._route_start_time)
        self.assertIsNone(self_mock._route_delay)

    @patch("chameleond.drivers.fpga_tio.time.time")
    def test_StopRouteWithMultiTapDelay_too_early(self, mock_time):
        self_mock = MagicMock()
        p1 = MagicMock()
        self_mock._route_processes = {"arecord": p1}
        self_mock._route_start_time = 1000.0
        self_mock._route_delay = 10

        # Simulate time passed: 1000 + 5 = 1005 < 1000 + 10
        # Currently it succeeds as minimum delay is not enforced.
        mock_time.return_value = 1005.0

        fpga_tio.ChameleondDriver.StopRouteWithMultiTapDelay(self_mock)

        # Verify processes were terminated
        p1.terminate.assert_called_once()

        # Verify state reset
        self.assertIsNone(self_mock._route_processes)
        self.assertIsNone(self_mock._route_start_time)
        self.assertIsNone(self_mock._route_delay)

    def test_StopRouteWithMultiTapDelay_no_route(self):
        self_mock = MagicMock()
        self_mock._route_processes = None

        with self.assertRaises(fpga_tio.DriverError):
            fpga_tio.ChameleondDriver.StopRouteWithMultiTapDelay(self_mock)


if __name__ == "__main__":
    unittest.main()
