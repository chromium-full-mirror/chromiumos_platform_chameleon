# Lint as: python2, python3
# -*- coding: utf-8 -*-
# pylint: disable=import-error

# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez PBAP Server Class"""

import dataclasses
import logging
import struct

from .bluez_obex_handler import ObexHandler
from .bluez_obex_handler import ObexHeader


class PbapServer(ObexHandler):
    """PBAP Server Implementation."""

    PBAP_ROOT = "pbap_root"
    PBAP_CONNECTION_ID = 0x00000002
    PBAP_CONNECT_UUID = "796135f0-f0c5-11d8-0966-0800200c9a66"
    TARGET_UUID = bytes.fromhex(PBAP_CONNECT_UUID.replace("-", ""))

    # Application Parameters IDs
    PARAM_SUPPORTED_FEATURES = 0x29

    def __init__(self):
        super().__init__(self.PBAP_CONNECTION_ID)
        self.curr_dir = self.PBAP_ROOT

    def ProcessPbapConnect(self, data):
        """Processes Connect Resuest.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        rsp_headers = []

        status, _, req_headers = self.ProcessConnect(data)

        for header in req_headers:
            if (
                header.id == self.OBJ_TARGET
                and header.value == self.TARGET_UUID
            ):
                rsp_headers.append(ObexHeader(self.OBJ_WHO, self.TARGET_UUID))

        conn_id_bytes = struct.pack(">I", self.PBAP_CONNECTION_ID)
        rsp_headers.append(ObexHeader(self.OBJ_CONN_ID, conn_id_bytes))

        return status, rsp_headers

    def ProcessPbapDisconnect(self, data):
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

    def ProcessPbapGet(self, data):
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

    def ProcessPbapSetPath(self, data):
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

    def ProcessPbapRequest(self, fd):
        """Processes the incoming OBEX PBAP Request.

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
            status, headers = self.ProcessPbapConnect(data)

        elif opcode == self.REQ_DISCONNECT:
            status, headers = self.ProcessPbapDisconnect(data)

        else:
            logging.warning(
                "PbapProfile: Operation not implemented: 0x{:02x}".format(
                    opcode
                )
            )
            status = self.RSP_NOT_IMPLEMENTED

        return status, opcode, headers

    def SendPbapResponse(self, fd, opcode, rsp_code, headers):
        """Writes Response to the Connection Socket.

        Args:
            fd: connection file descriptor
            opcode: request's OBEX opcode
            rsp_code: response code
            headers: a list of headers of type ObexHeader
        """

        self.SendResponse(fd, opcode, rsp_code, headers)
