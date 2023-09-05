# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Create a multifunctional usb gadget with configfs

Multi Functional USB Gadget is configured with the dictionary below:
- is a format used by USBMultiFunctionalGadget
- a description of file structure of a gadget. Which once created will be used
by linux libcomposite module to create the gadget.
- The "Linux USB gadget configured through configfs"[1] describes the
configuration of the gadget through configfs. This format is just a configfs
described in a key-value format instead of regular linux file system structure.
- the dict keys are the relative path of the folder/files
- the dict values can be either:
  - string/int/byte: means the value is the content in the file
  - None: means the key is a empty directory
  - string that starts with "ln:<PATH>" which means the key is a link to the
  PATH. Where PATH can be any directory
- Example (comments for descriptions):
{
  "idVendor": 0x047F,  # idVendor file at the root of gadget with
             # content 0x047F
  "strings/0x409": {  # a nested directory "strings/0x409" with 3 files
    "serialnumber": "ABC",
    "manufacturer": "ChromeOS",
    "product": product_name,
  },
  "functions": {
    # https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/configfs-usb-gadget-uac2
    "uac2.usb0": {
      "c_hs_bint": 1,
      "p_hs_bint": 1,
    },
    # https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/configfs-usb-gadget-hid
    "hid.usb0": {
      "protocol": 1,
      "subclass": 1,
      "report_length": 8,
      "report_desc": hid_report_descriptor,
    },
  },
  "configs/c.1": {

    # a empty directory "configs/c.1/strings/0x409"
    "strings/0x409": None,

    # "ln:" is a special syntax which means the file uac2.usb0 is a link to
    # the folder: "functions/uac2.usb0"
    "uac2.usb0": "ln:functions/uac2.usb0",
    "hid.usb0": "ln:functions/hid.usb0",
  },
}

[1]: https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt

"""

from enum import Enum
import logging

from chameleond.utils.usb import USBController, USBControllerError
from chameleond.utils import gadget_configfs


class USBMaxSpeedEnum(str, Enum):
  """Maximum speed depending on USB speed class"""

  super_speed_plus = "super-speed-plus"
  super_speed = "super-speed"
  high_speed = "high-speed"
  full_speed = "full-speed"
  low_speed = "low-speed"

  def __str__(self) -> str:
    """converts python string formatting to value of enum formatting"""
    return self.value


class USBMultiFunctionalGadget(USBController):
  """Simulate a USB device that has multiple functionalites.

  USBMultiFunctionalGadget class uses linux's configfs feature to interact with
  the linux gadget libcomposite module to simulate a USB device that has one or
  more usb capabilities.

  The complete list of USB features can be found here:
    https://github.com/torvalds/linux/tree/master/Documentation/ABI/testing
  """

  KERNEL_NAME = "libcomposite"
  KERNEL_DEPENDENCIES = ["usb_f_hid", "usb_f_uac2", "u_audio"]
  INSTANCE = None

  @classmethod
  def CleanConnectedGadgets(cls):
    # make sure no device are connected to UDC
    gadget_configfs.RemoveAllGadgets()

  @classmethod
  def CleanKernelDependencies(cls):
    for kernel_dep in cls.KERNEL_DEPENDENCIES:
      try:
        driver = USBController(kernel_dep)
        if driver.DriverIsEnabled():
          driver.DisableDriver()
      except USBControllerError as e:
        logging.error("Failed to clean kernel for %s", cls.KERNEL_NAME)
        logging.error("Failed to disable driver. (driver: %s)", kernel_dep)
        logging.error("Got Error: %s", str(e))
        raise USBControllerError(f"Failed to clean kernel for {cls.KERNEL_NAME}")

  def __init__(self, gadget_name: str, gadget_config: dict):
    """Instantiate the USBMultiFunctionalGadget object

    Args:
      gadget_name: the name of the gadget
      gadget_config: a dict that describes the file and directories
        needed to create the gadget. For examples check the header of
        this file.
    """
    super().__init__(self.KERNEL_NAME)

    self.gadget_name = gadget_name
    self.gadget_config = gadget_config
    logging.info("Completed initialization of USBMultiFunctionalGadget")

  def __new__(cls, *args, **kwargs):

    if cls.INSTANCE is not None:
      logging.info("Disabling driver for gadget %s", cls.INSTANCE.gadget_name)
      cls.INSTANCE.DisableDriver()

    logging.info("Cleaning up older gadgets")
    cls.CleanConnectedGadgets()

    logging.info("Removing %s dependencies", cls.KERNEL_NAME)
    cls.CleanKernelDependencies()

    if cls.INSTANCE is None:
      cls.INSTANCE = super().__new__(cls)

    return cls.INSTANCE

  def EnableDriver(self):
    """Modprobes USB driver module.

    Overwrites the default EnableDriver in superclass.
    """
    enable_driver_ret_code = super().EnableDriver()
    self._SetupGadget()
    self._PlugGadget()
    return enable_driver_ret_code

  def DisableDriver(self):
    """Removes USB driver module from kernel.

    Overwrites the default DisableDriver in superclass.
    """
    self._UnplugGadget()
    self._TeardownGadget()

    self.CleanKernelDependencies()

    disable_driver_ret_code = super().DisableDriver()
    return disable_driver_ret_code

  def _SetupGadget(self):
    """Create gadget in chameleon"""
    gadget_configfs.CreateGadget(self.gadget_name, self.gadget_config)

  def _TeardownGadget(self):
    """Remove gadget from chameleon"""
    gadget_configfs.RemoveGadget(self.gadget_name)

  def _PlugGadget(self):
    """Plug gadget from DUT"""
    gadget_configfs.SetUDC(self.gadget_name)

  def _UnplugGadget(self):
    """Unplug gadget from DUT"""
    gadget_configfs.ResetUDC(self.gadget_name)
