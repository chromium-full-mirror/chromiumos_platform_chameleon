# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module describe the extensions for USBMultiFunctionalGadget"""

import abc
import copy
import re
from typing import List, Tuple

from chameleond.utils import usb
from chameleond.utils import usb_audio_configs


class USBMultiFunctionalGadgetExtension(abc.ABC):
    """Provides translation for configuration of modprobe args to config.

    When users provides configuration for MultiFunctionalUSBGadget(MFG), and
    requests for specific features from MFG the extensions enable translation
    between classic method of enabling the kernel as module(ie. modprobe) and
    configuration in configfs[1].

    This class provides functional parity to enable gadgets perform

    [1]: https://github.com/torvalds/linux/tree/master/Documentation/ABI/testing
    """

    # FUNCTION_NAME is the name of the function described in Section 3 of "Linux
    # USB gadget configured through configfs"
    # eg. hid in "configfs-usb-gadget-hid" or uac2 in "configfs-usb-gadget-uac2"
    FUNCTION_NAME: str = None

    def ExtensionEnabled(self, config: dict) -> bool:
        """Check if extension is needed based on FUNCTION_NAME"""
        func_configs = self.FilterFunctionsConfig(config)
        return len(func_configs) > 0

    def FilterFunctionsConfig(self, config: dict) -> List[Tuple[str, dict]]:
        if "functions" not in config:
            raise ValueError("No functions provided in config.")
        func_configs = []
        for key, val in config["functions"].items():
            # key is expected to be in the format <name>.<instance name> as
            # described in Section 3 of "Linux USB gadget configured through
            # configfs"
            func_name, instance_name = key.split(".")
            if func_name == self.FUNCTION_NAME:
                func_configs.append((instance_name, val))
        return func_configs

    @abc.abstractmethod
    def UpdateConfig(
        self,
        config: dict,
    ) -> dict:
        """Updates the gadget config for extensions

        Called in USBMultiFunctionalGadget._SetupGadget
        """

    @abc.abstractmethod
    def CompleteSetup(self):
        """Called when gadget is plugged"""

    @abc.abstractmethod
    def ResetSetup(self):
        """Called when gadget unplugged or failed to plug"""


class USBMultiFunctionalGadgetAudioExtension(USBMultiFunctionalGadgetExtension):
    """Provides USB Audio methods for flow manager."""

    FUNCTION_NAME: str = "uac2"

    def __init__(
        self,
    ):
        self._driver_configs_to_set = usb_audio_configs.USBAudioDriverConfigs()
        self._driver_configs_in_use = None

    def UpdateConfig(
        self,
        config: dict,
    ) -> dict:
        modprobe_args = self._FormatDriverConfigsForModprobe(
            self._driver_configs_to_set
        )
        for instance_name, func_config in self.FilterFunctionsConfig(config):
            func_config = copy.copy(func_config)

            func_config["p_chmask"] = modprobe_args["p_chmask"]
            func_config["p_srate"] = modprobe_args["p_srate"]
            func_config["p_ssize"] = modprobe_args["p_ssize"]

            func_config["c_chmask"] = modprobe_args["c_chmask"]
            func_config["c_srate"] = modprobe_args["c_srate"]
            func_config["c_ssize"] = modprobe_args["c_ssize"]

            config["functions"][
                self.FUNCTION_NAME + "." + instance_name
            ] = func_config

        return config

    def CompleteSetup(self):
        self._driver_configs_in_use = self._driver_configs_to_set

    def ResetSetup(self):
        self._driver_configs_in_use = None

    def _FormatDriverConfigsForModprobe(self, driver_configs):
        """Converts configurations stored in driver_configs into modprobe args.

        Check USBAudioController._FormatDriverConfigsForModprobe for more
        info.
        """
        p_configs = driver_configs.GetPlaybackConfigs()
        p_chmask = self._TransformChannelNumberToChannelMask(p_configs.channel)
        p_srate = p_configs.rate
        p_ssize_in_bits = self._ExtractBitsFromSampleFormat(
            p_configs.sample_format
        )
        p_ssize_in_bytes = p_ssize_in_bits // 8

        c_configs = driver_configs.GetCaptureConfigs()
        c_chmask = self._TransformChannelNumberToChannelMask(c_configs.channel)
        c_srate = c_configs.rate
        c_ssize_in_bits = self._ExtractBitsFromSampleFormat(
            c_configs.sample_format
        )
        c_ssize_in_bytes = c_ssize_in_bits // 8

        device_info = driver_configs.GetDeviceInfoDict()

        params_dict = {
            "p_chmask": p_chmask,
            "p_srate": p_srate,
            "p_ssize": p_ssize_in_bytes,
            "c_chmask": c_chmask,
            "c_srate": c_srate,
            "c_ssize": c_ssize_in_bytes,
            "idVendor": device_info["vendor_id"],
            "idProduct": device_info["product_id"],
            "bcdDevice": device_info["bcd_device"],
            "iSerialNumber": device_info["serial_number"],
            "iManufacturer": device_info["manufacturer"],
            "iProduct": device_info["product"],
        }
        return params_dict

    def _TransformChannelNumberToChannelMask(self, channel_number: int):
        """Transforms channel number to integer equivalent of a binary mask.

        Check USBAudioController._TransformChannelNumberToChannelMask for more
        info.
        """
        channel_mask = pow(2, channel_number) - 1
        return channel_mask

    def _ExtractBitsFromSampleFormat(self, sample_format):
        """Validate and extracts sample size in bits.

        Check USBAudioController._ExtractBitsFromSampleFormat for more info.
        """
        try:
            sample_format_lower = sample_format.lower()
            pattern = re.compile(r"s(\d+)_le")
            match_result = pattern.match(sample_format_lower)
            if match_result is not None:
                sample_size = int(match_result.group(1))
                return sample_size
            else:
                raise usb.USBControllerError(
                    "Sample format %s in driver configs is"
                    " invalid." % sample_format
                )
        except ValueError:
            raise usb.USBControllerError(
                "Sample format %s in driver configs is"
                " invalid." % sample_format
            )

    def GetSupportedPlaybackDataFormat(self, *, driver):
        """Returns the playback data format as supported by the USB driver.

        Check USBAudioController.GetSupportedPlaybackDataFormat for more info
        """
        if not driver.DriverIsEnabled():
            error_message = (
                "Invalid Call: Supported format not applicable "
                "since driver is not enabled."
            )
            raise usb.USBControllerError(error_message)
        return self._driver_configs_in_use.GetPlaybackConfigs()

    def GetSupportedCaptureDataFormat(self, *, driver):
        """Returns the capture data format as supported by the USB driver.

        Check USBAudioController.GetSupportedCaptureDataFormat for more info
        """
        if not driver.DriverIsEnabled():
            error_message = (
                "Invalid Call: Supported format not applicable "
                "since driver is not enabled."
            )
            raise usb.USBControllerError(error_message)
        return self._driver_configs_in_use.GetCaptureConfigs()

    def SetDriverPlaybackConfigs(self, playback_configs, *, driver):
        """Sets playback-related configs in _driver_configs_to_set.

        Check USBAudioController.SetDriverPlaybackConfigs for more info
        """
        was_modprobed = driver.DriverIsEnabled()
        driver.DisableDriver()
        self._driver_configs_to_set.SetPlaybackConfigs(playback_configs)
        if was_modprobed:
            driver.EnableDriver()

    def SetDriverCaptureConfigs(self, capture_configs, *, driver):
        """Sets capture-related configs in _driver_configs_to_set.

        Check USBAudioController.SetDriverCaptureConfigs for more info
        """
        was_modprobed = driver.DriverIsEnabled()
        driver.DisableDriver()
        self._driver_configs_to_set.SetCaptureConfigs(capture_configs)
        if was_modprobed:
            driver.EnableDriver()
