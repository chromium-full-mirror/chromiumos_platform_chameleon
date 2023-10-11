# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Create and Remove configfs based on multifunctional usb gadget config

Details of gadget config is at chameleond/utils/usb_multifunctional_gadget.py
"""

import logging
from pathlib import Path
from typing import List


CONFIGFS_DEFAULT_PATH = Path("/sys/kernel/config/usb_gadget")
UDC_DIR_DEFAULT_PATH = Path("/sys/class/udc/")


class GadgetConfigFSException(Exception):
    pass


def CreateGadget(gadget_name: str, gadget_config: dict):
    """Create a gadget file structure based on gadget config"""
    if not CONFIGFS_DEFAULT_PATH.exists():
        raise ValueError(
            f"Cannot find {CONFIGFS_DEFAULT_PATH}, libcomposite "
            " might not be enabled."
        )

    # cleanups
    ResetUDC(gadget_name)
    RemoveGadget(gadget_name)

    gadget_dir = CONFIGFS_DEFAULT_PATH / gadget_name
    gadget_dir.mkdir(exist_ok=True)

    # recursively create file system structures.
    def setupKeyVal(parent_path: Path, kv_pair: dict):
        for key, val in kv_pair.items():
            if val is None:
                # create a directory
                _MakeDir(parent_path / Path(key))
            elif isinstance(val, dict):
                # recursively do the same thing for children
                setupKeyVal(parent_path=parent_path / key, kv_pair=val)
            elif isinstance(val, str) and val.startswith("ln:"):
                # setup link
                to_file = val[3:]  # remove "ln:"
                _Link(from_file=parent_path / key, to_file=gadget_dir / to_file)
            else:
                _SetValue(file=parent_path / key, value=str(val))

    setupKeyVal(gadget_dir, gadget_config)


def _MakeDir(directory: Path):
    """Make directory."""
    try:
        directory.mkdir(exist_ok=True, parents=True)
    except OSError as e:
        logging.error("Failed to make directory for %s", directory)
        logging.error("Got Error: %s", str(e))
        raise GadgetConfigFSException(f"Failed to make directory({directory})")


def _SetValue(file: Path, value: bytes):
    """Given a path set the value in the file.

    Args:
      file: a path to set
      value: bytes value to write into the file.
    """
    try:
        file.parent.mkdir(parents=True, exist_ok=True)
        with open(file, "w", encoding="utf-8") as f:
            f.write(value)
    except OSError as e:
        logging.error("Failed to set value:%s in %s", value, file)
        logging.error("Got Error: %s", str(e))
        raise GadgetConfigFSException(
            f"Failed to set value({value}) in" f"file({file})"
        )


def _Link(from_file: Path, to_file: Path):
    """Given from_file and to_file, link from_file to to_file

    Args:
      from_file: a path, a link to be created.
      to_file: a path, a concrete file to be linked to.
    """
    try:
        from_file.parent.mkdir(parents=True, exist_ok=True)
        from_file.symlink_to(to_file)
    except OSError as e:
        logging.error("Failed to create link from %s to %s", from_file, to_file)
        logging.error("Got Error: %s", str(e))
        raise GadgetConfigFSException(
            f"Failed to create link from({from_file})" f" to({to_file})"
        )


def RemoveAllGadgets():
    """Remove all gadget in configfs"""
    if not CONFIGFS_DEFAULT_PATH.exists():
        return

    for gadget_dir in CONFIGFS_DEFAULT_PATH.iterdir():
        try:
            ResetUDC(
                gadget_dir.name
            )  # make sure no device are connected to UDC
        except OSError as e:
            logging.warning(
                "Skipped reseting UDC for gadget %s", gadget_dir.name
            )
            logging.warning("Got Error: %s", str(e))
        try:
            RemoveGadget(gadget_dir.name)
        except OSError as e:
            logging.error("Failed to remove gadget %s", gadget_dir.name)
            logging.error("Got Error: %s", str(e))
            raise GadgetConfigFSException(
                f"Failed to remove gadget" f" {gadget_dir.name}"
            )


def RemoveGadget(gadget_name: str):
    """Remove a gadget in configfs"""
    logging.info("Removing configfs for gadget %s", gadget_name)
    gadget_dir = CONFIGFS_DEFAULT_PATH / gadget_name
    if not gadget_dir.exists():
        return
    for file in gadget_dir.glob("configs/*.*/*.*"):
        if file.exists():
            file.unlink()

    for _dir in [
        *gadget_dir.glob("configs/*.*/strings/*"),
        *gadget_dir.glob("configs/*.*"),
        *gadget_dir.glob("functions/*.*"),
        *gadget_dir.glob("strings/*"),
    ]:
        if _dir.exists():
            _dir.rmdir()

    gadget_dir.rmdir()


def GetUDCName():
    """Get a UDC name"""
    if not UDC_DIR_DEFAULT_PATH.exists():
        logging.warning("UDC directory(%s) not found.", UDC_DIR_DEFAULT_PATH)
        raise GadgetConfigFSException(
            f"UDC directory({UDC_DIR_DEFAULT_PATH})" " not found."
        )
    else:
        udc_files = sorted([f.name for f in UDC_DIR_DEFAULT_PATH.iterdir()])
        if len(udc_files) == 0:
            logging.warning("Unable to find UDC in %s", UDC_DIR_DEFAULT_PATH)
            raise GadgetConfigFSException(
                f"Unable to find UDC in" f" {UDC_DIR_DEFAULT_PATH}"
            )
        return udc_files[0]


def SetUDC(gadget_name: str):
    """Set a UDC name into gadget"""
    logging.info("Setting configfs UDC for gadget %s", gadget_name)
    gadget_dir = CONFIGFS_DEFAULT_PATH / gadget_name
    if not gadget_dir.exists():
        logging.error("Gadget doesn't exists %s", {gadget_dir})
        raise GadgetConfigFSException(f"Failed to set UDC for {gadget_name}")
    try:
        udc_name = GetUDCName()
        logging.info("Found UDC %s", udc_name)
        with (gadget_dir / "UDC").open("w") as f:
            f.write(udc_name + "\n")
    except OSError as e:
        logging.error("Failed to set UDC for gadget %s", gadget_dir.name)
        logging.error("Got Error: %s", str(e))
        raise GadgetConfigFSException(f"Failed to set UDC for {gadget_name}")


def ResetUDC(gadget_name: str):
    """Reset a UDC in a gadget"""
    logging.info("Resetting configfs UDC for gadget %s", gadget_name)
    gadget_dir = CONFIGFS_DEFAULT_PATH / gadget_name
    if not gadget_dir.exists():
        return
    with (gadget_dir / "UDC").open("w") as f:
        f.write("\n")


def Describe(gadget_config: dict):
    """Print the description of gadget_config"""

    class Node:
        """Folder/File nodes for each hirerachy in gadget_config"""

        def __init__(
            self,
            children: List["Node"] = None,
            name: str = "",
            content: str = None,
        ):
            self.children = children
            if self.children is None:
                self.children = []
            self.name = name
            self.content = content  # mutually exclusive with children

    def create_tree(parent_node: Node, kv_pair: dict):
        for key, val in kv_pair.items():
            # from the key create nodes
            temp_node = parent_node
            for key_item in key.split("/"):
                if key_item:
                    new_node = Node(name=key_item)
                    temp_node.children.append(new_node)
                    temp_node = new_node

            # children
            if isinstance(val, dict):
                create_tree(parent_node=temp_node, kv_pair=val)
            elif val is None:  # an empty directory
                temp_node.content = "EMPTY_DIRECTORY"
            elif isinstance(val, str) and val.startswith("ln:"):
                # setup link
                to_file = " -> " + val[3:]  # remove "ln:"
                temp_node.content = to_file
            else:  # file with value
                temp_node.content = val

    def draw_tree(prefix: str, node: Node, islast=False):
        if node.children:
            if islast:
                logging.info(prefix[:-1] + "|-- " + node.name)
            else:
                logging.info(prefix + "-- " + node.name)
            for c in node.children[:-1]:
                draw_tree(prefix + "   |", c)
            c = node.children[-1]
            draw_tree(prefix + "    ", c, islast=True)
        else:
            if islast:
                logging.info(
                    prefix[:-1] + "|-- " + node.name + ": " + str(node.content)
                )
            else:
                logging.info(
                    prefix + "-- " + node.name + ": " + str(node.content)
                )

    root = Node(name=".")

    create_tree(root, gadget_config)

    logging.info("The directory tree below will be created.")
    draw_tree("", root)
