# Lint as: python2, python3
# -*- coding: utf-8 -*-
# pylint: disable=import-error

# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez PBAP Server Class"""

import dataclasses
import logging
import os
import pathlib
import struct

from .bluez_obex_handler import AppParamsHeader
from .bluez_obex_handler import ObexHandler
from .bluez_obex_handler import ObexHeader


class PbapServer(ObexHandler):
    """PBAP Server Implementation."""

    PBAP_ROOT = "pbap_root"
    PBAP_CONNECTION_ID = 0x00000002
    PBAP_CONNECT_UUID = "796135f0-f0c5-11d8-0966-0800200c9a66"
    TARGET_UUID = bytes.fromhex(PBAP_CONNECT_UUID.replace("-", ""))

    # Application Parameters IDs
    PARAM_MAX_LIST_COUNT = 0x04
    PARAM_LIST_START_OFFSET = 0x05
    PARAM_PROPERTY_SELECTOR = 0x06
    PARAM_FORMAT = 0x07
    PARAM_PHONEBOOK_SIZE = 0x08
    PARAM_VCARD_SELECTOR = 0x0C
    PARAM_VCARD_SELECTOR_OPERATOR = 0x0E
    PARAM_RESET_NEW_MISSED_CALLS = 0x0F

    # vCard Formats
    VCARD_FORMAT_2_1 = 0x00
    VCARD_FORMAT_3_0 = 0x01

    # PBAP Request Types
    TYPE_PULL_PHONEBOOK = "x-bt/phonebook"

    def __init__(self):
        super().__init__(self.PBAP_CONNECTION_ID)
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        self.curr_dir = self.PBAP_ROOT

    def ProcessPullPhoneBook(self, name, params):
        """Lists phonebook records from the specified folder.

        Args:
            params: a list of request parameters of type AppParamsHeader

        Returns:
            status: SUCCESS if listing succeeded
            headers: a list of response headers of type ObexHeader
        """

        status = self.RSP_SUCCESS
        rsp_headers = []
        rsp_params = []

        list_count = 0
        max_list_count = None
        list_start_offset = None

        for param in params:
            if param.id == self.PARAM_MAX_LIST_COUNT:
                max_list_count = struct.unpack(">H", param.value)[0]
            elif param.id == self.PARAM_LIST_START_OFFSET:
                list_start_offset = struct.unpack(">H", param.value)[0]
            elif param.id == self.PARAM_FORMAT:
                vcard_format = struct.unpack(">B", param.value)[0]
                if vcard_format != self.VCARD_FORMAT_3_0:
                    logging.warning(
                        "PbapServer: Ignoring vCard version 0x{}".format(
                            param.value.hex()
                        )
                    )
            elif (
                param.id == self.PARAM_PROPERTY_SELECTOR
                or param.id == self.PARAM_RESET_NEW_MISSED_CALLS
                or param.id == self.PARAM_VCARD_SELECTOR
                or param.id == self.PARAM_VCARD_SELECTOR_OPERATOR
            ):
                logging.warning(
                    "PbapServer: Ignoring pull-phonebook param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )
            else:
                logging.warning(
                    "PbapServer: Unexpected pull-phonebook param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )

        path = os.path.join(self.base_dir, self.curr_dir, name)
        base = os.path.splitext(path)[0]

        if not os.path.exists(base) or not os.path.isdir(base):
            logging.error("PbapProfile: Phonebook not found {}".format(base))
            status = self.RSP_NOT_FOUND
            return status, rsp_headers

        vcard_obj = ""

        i = 0
        for item in pathlib.Path(base).iterdir():
            ext = os.path.splitext(item.name)[1]

            if ext == ".vcf":
                # If max_list_count is 0, only count total items
                if max_list_count is not None and max_list_count == 0:
                    list_count += 1
                    continue

                # Skip all items before list_start_offset'th item
                if list_start_offset is not None and i < list_start_offset:
                    i += 1
                    continue

                try:
                    fd = open(os.path.join(base, item.name), "r")
                    data = fd.read()
                    fd.close()

                    vcard_obj += data
                except Exception as e:
                    logging.error(
                        "PbapProfile: Read error {}: {}".format(
                            os.path.join(base, item.name), e
                        )
                    )
                    status = self.RSP_NOT_FOUND
                    return status, rsp_headers

                list_count += 1

                # if max_list_count is specified, list only that many items
                if max_list_count is not None and list_count == max_list_count:
                    break

        # If max_list_count is 0, return item count, else return actual items
        if max_list_count is not None and max_list_count == 0:
            list_count_bytes = struct.pack(">H", list_count)
            rsp_params.append(
                AppParamsHeader(
                    self.PARAM_PHONEBOOK_SIZE,
                    len(list_count_bytes),
                    list_count_bytes,
                )
            )
            rsp_headers.append(
                ObexHeader(self.OBJ_APP_PARAM, self.PackAppParams(rsp_params))
            )
        else:
            rsp_headers.append(
                ObexHeader(self.OBJ_END_OF_BODY, vcard_obj.encode("utf-8"))
            )

        logging.debug(
            "PbapProfile: Pull Phonebook {}, max {}, offset {} - {} items".format(
                name, max_list_count, list_start_offset, list_count
            )
        )

        return status, rsp_headers

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

        self.curr_dir = self.PBAP_ROOT

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

        name = ""
        type = ""
        params = []

        for header in req_headers:
            if header.id == self.OBJ_NAME:
                name = self.ParseName(header.value)
            elif header.id == self.OBJ_TYPE:
                type = self.ParseType(header.value)
            elif header.id == self.OBJ_APP_PARAM:
                params = self.ParseAppParams(header.value)
            elif header.id != self.OBJ_CONN_ID:
                logging.warning(
                    "PbapProfile: Unexpected get header 0x{:02x} 0x{}".format(
                        header.id, header.value.hex()
                    )
                )

        headers = []

        if type == self.TYPE_PULL_PHONEBOOK:
            status, headers = self.ProcessPullPhoneBook(name, params)
        else:
            logging.error("PbapProfile: Unsupported Get {}".format(type))
            status = self.RSP_NOT_IMPLEMENTED

        rsp_headers += headers

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

        elif opcode == self.REQ_GET or opcode == self.REQ_GET_FINAL:
            status, headers = self.ProcessPbapGet(data)

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
