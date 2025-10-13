# Lint as: python2, python3
# -*- coding: utf-8 -*-
# pylint: disable=import-error

# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez OBEX Request/Response Classes (for MAP and PBAP)"""

import dataclasses
import logging
import struct


@dataclasses.dataclass
class ObexHeader:
    """OBEX Header Format."""

    id: int
    value: bytes


@dataclasses.dataclass
class AppParamsHeader:
    """Application Parameters Header Format."""

    id: int
    length: int
    value: bytes


class ObexHandler:
    """OBEX Operations and Opcodes Implementation."""

    OBEX_VERSION = 0x10
    FLAGS = 0x00

    # OBEX Message Opcodes
    REQ_CONNECT = 0x80
    REQ_DISCONNECT = 0x81
    REQ_PUT = 0x02
    REQ_PUT_FINAL = 0x82
    REQ_GET = 0x03
    REQ_GET_FINAL = 0x83
    REQ_SETPATH = 0x85
    REQ_ABORT = 0xFF

    # OBEX ID Types
    ID_TYPE_MASK = 0xC0  # the 2 high order bits
    ID_UNICODE_TEXT = 0x00
    ID_BYTE_SEQUENCE = 0x40
    ID_SINGLE_BYTE = 0x80
    ID_FOUR_BYTES = 0xC0

    # OBEX Object IDs
    OBJ_NAME = 0x01
    OBJ_TYPE = 0x42
    OBJ_TARGET = 0x46
    OBJ_BODY = 0x48
    OBJ_END_OF_BODY = 0x49
    OBJ_WHO = 0x4A
    OBJ_APP_PARAM = 0x4C
    OBJ_LENGTH = 0xC3
    OBJ_CONN_ID = 0xCB

    # OBEX Response Codes (without the high bit)
    RSP_CONTINUE = 0x10
    RSP_SUCCESS = 0x20
    RSP_BAD_REQUEST = 0x40
    RSP_UNAUTHORIZED = 0x41
    RSP_FORBIDDEN = 0x43
    RSP_NOT_FOUND = 0x44
    RSP_NOT_IMPLEMENTED = 0x51
    RSP_SERVICE_UNAVAILABLE = 0x53

    def __init__(self, conn_id):
        self.conn_id = conn_id
        self.max_len = 0xFFFF

    def ParseHeaders(self, data):
        """Parses OBEX Headers.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            headers: a list of parsed headers of type ObexHeader
        """

        headers = []
        i = 0

        while i < len(data):
            id = data[i]
            id_type = id & self.ID_TYPE_MASK
            i += 1
            value = b""

            if id_type == self.ID_UNICODE_TEXT:
                length = struct.unpack(">H", data[i : i + 2])[0]
                length -= 3  # length is inclusive of len(id) + len(length)
                i += 2

                value = data[i : i + length]
                i += length

            elif id_type == self.ID_BYTE_SEQUENCE:
                length = struct.unpack(">H", data[i : i + 2])[0]
                length -= 3  # length is inclusive of len(id) + len(length)
                i += 2

                value = data[i : i + length]
                i += length

            elif id_type == self.ID_SINGLE_BYTE:
                value = data[i]  # 1 byte data
                i += 1

            elif id_type == self.ID_FOUR_BYTES:
                value = data[i : i + 4]  # 4 byte data
                i += 4

            headers.append(ObexHeader(id, value))

        return headers

    def PackHeaders(self, headers):
        """Packs headers into a bytes array.

        Args:
            headers: a list of headers of type ObexHeader

        Returns:
            data: bytes array of raw data of headers
        """

        data = b""

        for header in headers:
            id_type = header.id & self.ID_TYPE_MASK

            if (
                id_type == self.ID_UNICODE_TEXT
                or id_type == self.ID_BYTE_SEQUENCE
            ):
                length = len(header.value)
                length += 3  # length is inclusive of len(id) + len(length)
                data += struct.pack(">BH", header.id, length)
                data += header.value

            elif (
                id_type == self.ID_SINGLE_BYTE or id_type == self.ID_FOUR_BYTES
            ):
                data += struct.pack(">B", header.id)
                data += header.value

        return data

    def ParseAppParams(self, data):
        """Parses Application Parameters.

        Args:
            data: bytes array of raw data from App Parameters header

        Returns:
            params: a list of parsed parameters of type AppParamsHeader
        """

        params = []
        i = 0

        while i < len(data):
            id = data[i]
            i += 1

            length = data[i]
            i += 1

            value = data[i : i + length]
            i += length

            params.append(AppParamsHeader(id, length, value))

        return params

    def PackAppParams(self, params):
        """Packs application parameters into a bytes array.

        Args:
            params: a list of parameters of type AppParamsHeader

        Returns:
            data: bytes array of raw data of application parameters
        """

        data = b""

        for param in params:
            data += struct.pack(">BB", param.id, param.length)
            data += param.value

        return data

    def ParseName(self, data):
        """Parses Name Header.

        Args:
            data: bytes array of raw data from name header

        Returns:
            name: name in string format
        """

        # OBEX Name header is encoded as UCS-2 (which is UTF-16). OBEX uses
        # network order, so decode using 'be' and strip any trailing null
        # characters.

        return data.decode("utf-16-be").strip("\x00")

    def ParseType(self, data):
        """Parses Type Header.

        Args:
            data: bytes array of raw data from type header

        Returns:
            name: type in string format
        """

        # OBEX Type header is encoded as UTF-8, so decode using standard
        # 'utf-8' and strip any trailing null characters.

        return data.decode("utf-8").strip("\x00")

    def CheckConnectionId(self, headers):
        """Checks if the connection ID in the headers matches the expected one.

        Args:
            headers: a list of headers of type ObexHeader

        Returns:
            status: SUCCESS if packet parsing succeeded
        """

        # The connection id should match only if it is available
        for header in headers:
            if header.id == self.OBJ_CONN_ID:
                conn_id = struct.unpack(">I", header.value)[0]
                if conn_id != self.conn_id:
                    return self.RSP_SERVICE_UNAVAILABLE

        return self.RSP_SUCCESS

    def ProcessConnect(self, data):
        """Processes Connect Resuest.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            flags: connect request flags
            headers: a list of parsed headers of type ObexHeader
        """

        FORMAT = ">BBH"
        FORMAT_LEN = 4

        status = self.RSP_SUCCESS

        obex_version, flags, max_packet_len = struct.unpack(
            FORMAT, data[:FORMAT_LEN]
        )
        headers = self.ParseHeaders(data[FORMAT_LEN:])

        if self.max_len > max_packet_len:
            self.max_len = max_packet_len

        return status, flags, headers

    def ProcessDisconnect(self, data):
        """Processes Disconnect Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of parsed headers of type ObexHeader
        """

        headers = self.ParseHeaders(data)
        status = self.CheckConnectionId(headers)

        return status, headers

    def ProcessPut(self, data):
        """Processes Put Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of parsed headers of type ObexHeader
        """

        headers = self.ParseHeaders(data)
        status = self.CheckConnectionId(headers)

        return status, headers

    def ProcessGet(self, data):
        """Processes Get Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of parsed headers of type ObexHeader
        """

        headers = self.ParseHeaders(data)
        status = self.CheckConnectionId(headers)

        return status, headers

    def ProcessSetPath(self, data):
        """Processes SetPath Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            flags: set path request flags
            headers: a list of parsed headers of type ObexHeader
        """

        FORMAT = ">BB"
        FORMAT_LEN = 2

        flags, constants = struct.unpack(FORMAT, data[:FORMAT_LEN])
        headers = self.ParseHeaders(data[FORMAT_LEN:])
        status = self.CheckConnectionId(headers)

        return status, flags, headers

    def ProcessRequest(self, fd):
        """Processes the incoming OBEX Request.

        Args:
            fd: connection file descriptor

        Returns:
            opcode: request's OBEX opcode
            data: bytes array of raw data of headers
        """

        FORMAT = ">BH"
        FORMAT_LEN = 3

        opcode = None
        data = b""

        header = fd.read(FORMAT_LEN)

        if header:
            opcode, length = struct.unpack(FORMAT, header)

            data = fd.read(length - FORMAT_LEN)

            logging.debug(
                "OBEX request {:02x} len {:04x} data {}".format(
                    opcode, length, data.hex()
                )
            )

        return opcode, data

    def SendResponse(self, fd, opcode, rsp_code, headers=[]):
        """Writes Response to the Connection Socket.

        Args:
            fd: connection file descriptor
            opcode: request's OBEX opcode
            rsp_code: response code
            headers: a list of headers of type ObexHeader
        """

        HIGH_BIT = 0x80

        data = b""

        # Response code high bit should be set if request opcode high bit is set
        if opcode & HIGH_BIT:
            rsp_code = rsp_code | HIGH_BIT

        # We need to add additional parameters for the CONNECT response
        if opcode == self.REQ_CONNECT:
            data += struct.pack(
                ">BBH", self.OBEX_VERSION, self.FLAGS, self.max_len
            )

        # Add any additional headers to the response data
        data += self.PackHeaders(headers)

        length = len(data)
        length += 3  # length is inclusive of len(rsp_code) + len(length)

        response = struct.pack(">BH", rsp_code, length)
        response += data

        logging.debug(
            "OBEX response {:02x} len {:04x} data {}".format(
                rsp_code, length, data.hex()
            )
        )

        fd.write(response)
