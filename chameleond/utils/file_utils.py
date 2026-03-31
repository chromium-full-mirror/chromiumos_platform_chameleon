#!/usr/bin/env python
# Copyright 2017 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""File utilities."""

import uuid


def TruncateToZero(path):
    """Truncates a file size to 0.

    Args:
      path: Path to the file.
    """
    with open(path, "w"):
        pass


def GetFileToken(path):
    """Generates a token for the file path.

    Args:
      path: The file path or filename.

    Returns:
      A tuple of (token, filename). filename is stripped of /tmp/ prefix.
    """
    prefix = "/tmp/"
    filename = path[len(prefix) :] if path.startswith(prefix) else path
    token = uuid.uuid5(uuid.NAMESPACE_DNS, filename).hex
    return token, filename


def RegisterFileToken(file_dict, token, filename):
    """Stores the token and filename in the file dict.

    Args:
      file_dict: The dictionary to store the token in.
      token: The token.
      filename: The filename.
    """
    file_dict[token] = filename
