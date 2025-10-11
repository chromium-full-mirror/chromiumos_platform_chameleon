# Lint as: python2, python3
# -*- coding: utf-8 -*-
# pylint: disable=import-error

# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez MAP Server Class"""

import dataclasses
import logging
import struct

from .bluez_obex_handler import ObexHandler
from .bluez_obex_handler import ObexHeader


@dataclasses.dataclass
class AppParamsHeader:
    """Application Parameters Header Format."""

    id: int
    length: int
    value: bytes


class MapServer(ObexHandler):
    """MAP Server Implementation."""

    MAP_ROOT = "map_root"
    MAP_CONNECTION_ID = 0x00000001
    MAS_UUID = "bb582b40-420c-11db-b0de-0800200c9a66"
    TARGET_UUID = bytes.fromhex(MAS_UUID.replace("-", ""))

    # Application Parameters IDs
    PARAM_SUPPORTED_FEATURES = 0x29

    def __init__(self):
        super().__init__(self.MAP_CONNECTION_ID)
        self.curr_dir = self.MAP_ROOT

    def ProcessMapConnect(self, data):
        """Processes Connect Resuest.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        rsp_headers = []

        status, flags, req_headers = self.ProcessConnect(data)
        if status != self.RSP_SUCCESS:
            return status, rsp_headers

        for header in req_headers:
            if (
                header.id == self.OBJ_TARGET
                and header.value == self.TARGET_UUID
            ):
                rsp_headers.append(ObexHeader(self.OBJ_WHO, self.TARGET_UUID))

        conn_id_bytes = struct.pack(">I", self.MAP_CONNECTION_ID)
        rsp_headers.append(ObexHeader(self.OBJ_CONN_ID, conn_id_bytes))

        return status, rsp_headers

    def ProcessMapDisconnect(self, data):
        """Processes Disconnect Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        # Disconnect response doesn't include any headers, return empty headers
        rsp_headers = []

        status, req_headers = self.ProcessDisconnect(data)
        if status != self.RSP_SUCCESS:
            return status, rsp_headers

        return status, rsp_headers

    def ProcessMapPut(self, data):
        """Processes Put Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        rsp_headers = []

        status, req_headers = self.ProcessPut(data)
        if status != self.RSP_SUCCESS:
            return status, rsp_headers

        return status, rsp_headers

    def ProcessMapGet(self, data):
        """Processes Get Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        rsp_headers = []

        status, req_headers = self.ProcessGet(data)
        if status != self.RSP_SUCCESS:
            return status, rsp_headers

        return status, rsp_headers

    def ProcessMapSetPath(self, data):
        """Processes SetPath Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        rsp_headers = []

        status, flags, req_headers = self.ProcessSetPath(data)
        if status != self.RSP_SUCCESS:
            return status, rsp_headers

        return status, rsp_headers

    def ProcessMapRequest(self, fd):
        """Processes the incoming OBEX MAP Request.

        Args:
            fd: connection file descriptor

        Returns:
            status: SUCCESS if packet parsing succeeded
            opcode: request's OBEX opcode
            headers: a list of response headers of type ObexHeader
        """

        status = self.RSP_SUCCESS
        headers = []

        opcode, data = self.ProcessRequest(fd)
        if opcode is None:
            return status, opcode, headers

        if opcode == self.REQ_CONNECT:
            status, headers = self.ProcessMapConnect(data)

        elif opcode == self.REQ_DISCONNECT:
            status, headers = self.ProcessMapDisconnect(data)

        else:
            logging.warning(
                "MapProfile: Operation not implemented: 0x{:02x}".format(opcode)
            )
            status = self.RSP_NOT_IMPLEMENTED

        return status, opcode, headers

    def SendMapResponse(self, fd, opcode, rsp_code, headers):
        """Writes Response to the Connection Socket.

        Args:
            fd: connection file descriptor
            opcode: request's OBEX opcode
            rsp_code: response code
            headers: a list of headers of type ObexHeader
        """

        self.SendResponse(fd, opcode, rsp_code, headers)
