# Lint as: python2, python3
# -*- coding: utf-8 -*-
# pylint: disable=import-error

# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez MAP Server Class"""

import datetime
import logging
import os
import pathlib
import struct

from .bluez_obex_handler import AppParamsHeader
from .bluez_obex_handler import ObexHandler
from .bluez_obex_handler import ObexHeader


class MapServer(ObexHandler):
    """MAP Server Implementation."""

    MAP_ROOT = "map_root"
    MAP_CONNECTION_ID = 0x00000001
    MAS_UUID = "bb582b40-420c-11db-b0de-0800200c9a66"
    TARGET_UUID = bytes.fromhex(MAS_UUID.replace("-", ""))

    # Application Parameters IDs
    PARAM_MAX_LIST_COUNT = 0x01
    PARAM_LIST_START_OFFSET = 0x02
    PARAM_FILTER_MESSAGE_TYPE = 0x03
    PARAM_FILTER_PERIOD_BEGIN = 0x04
    PARAM_FILTER_PERIOD_END = 0x05
    PARAM_FILTER_READ_STATUS = 0x06
    PARAM_FILTER_RECIPIENT = 0x07
    PARAM_FILTER_ORIGINATOR = 0x08
    PARAM_FILTER_PRIORITY = 0x09
    PARAM_ATTACHMENT = 0x0A
    PARAM_NEW_MESSAGE = 0x0D
    PARAM_PARAMETER_MASK = 0x10
    PARAM_FOLDER_LISTING_SIZE = 0x11
    PARAM_LISTING_SIZE = 0x12
    PARAM_SUBJECT_LENGTH = 0x13
    PARAM_CHARSET = 0x14
    PARAM_FRACTION_REQUEST = 0x15
    PARAM_FRACTION_DELIVER = 0x16
    PARAM_MSE_TIME = 0x19
    PARAM_CONVERSATION_ID = 0x22
    PARAM_FILTER_MESSAGE_HANDLE = 0x24
    PARAM_SUPPORTED_FEATURES = 0x29

    # MAP Request Types
    TYPE_FOLDER_LISTING = "x-obex/folder-listing"
    TYPE_MSG_LISTING = "x-bt/MAP-msg-listing"
    TYPE_GET_MESSAGE = "x-bt/message"
    TYPE_NOTIFICATION_REG = "x-bt/MAP-NotificationRegistration"

    # MAP Message Types
    MSG_SMS_GSM = 0x01
    MSG_SMS_CDMA = 0x02
    MSG_EMAIL = 0x04
    MSG_MMS = 0x80
    MSG_IM = 0x10

    # XML Headers
    TAG_HEADER = '<?xml version="1.0" encoding="utf-8" standalone="yes" ?>\n'
    TAG_FOLDER_LISTING_BEGIN = '<folder-listing version="1.0">\n'
    TAG_FOLDER_LISTING_FOLDER = '  <folder name="{}" />\n'
    TAG_FOLDER_LISTING_FILE = '  <file name="{}" />\n'
    TAG_FOLDER_LISTING_END = "</folder-listing>\n"
    TAG_MESSAGE_LISTING_BEGIN = '<MAP-msg-listing version="1.0">\n'
    TAG_MESSAGE_LISTING_MSG = '  <msg attachment_size="0" datetime="{}" handle="{}" priority="no" protected="no" read="yes" reception_status="complete" recipient_addressing="" recipient_name="" sender_addressing="+15256461234" sender_name="" sent="no" size="16" subject="Test Message {}" text="yes" type="SMS_GSM" />\n'
    TAG_MESSAGE_LISTING_END = "</MAP-msg-listing>\n"

    def __init__(self):
        super().__init__(self.MAP_CONNECTION_ID)
        self.curr_time = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        self.curr_dir = self.MAP_ROOT

    def ProcessFolderListing(self, params):
        """Lists items in the current folder.

        Args:
            params: a list of request parameters of type AppParamsHeader

        Returns:
            status: SUCCESS if folder listing succeeded
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
            else:
                logging.warning(
                    "MapServer: Unexpected folder-listing param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )

        # Create the folder listing XML object
        xml_obj = self.TAG_HEADER + self.TAG_FOLDER_LISTING_BEGIN
        path = os.path.join(self.base_dir, self.curr_dir)

        i = 0
        for item in pathlib.Path(path).iterdir():
            # If max_list_count is 0, only count total items
            if max_list_count is not None and max_list_count == 0:
                list_count += 1
                continue

            # Skip all items before list_start_offset'th item
            if list_start_offset is not None and i < list_start_offset:
                i += 1
                continue

            if item.is_dir():
                xml_obj += self.TAG_FOLDER_LISTING_FOLDER.format(item.name)
            elif item.is_file():
                xml_obj += self.TAG_FOLDER_LISTING_FILE.format(item.name)

            list_count += 1

            # if max_list_count is specified, list only that many items
            if max_list_count is not None and list_count == max_list_count:
                break

        xml_obj += self.TAG_FOLDER_LISTING_END

        # If max_list_count is 0, return item count, else return actual items
        if max_list_count is not None and max_list_count == 0:
            list_count_bytes = struct.pack(">H", list_count)
            rsp_params.append(
                AppParamsHeader(
                    self.PARAM_FOLDER_LISTING_SIZE,
                    len(list_count_bytes),
                    list_count_bytes,
                )
            )
            rsp_headers.append(
                ObexHeader(self.OBJ_APP_PARAM, self.PackAppParams(rsp_params))
            )
        else:
            rsp_headers.append(
                ObexHeader(self.OBJ_END_OF_BODY, xml_obj.encode("utf-8"))
            )

        logging.debug(
            "MapProfile: List folder {}, max {}, offset {} - {} items".format(
                self.curr_dir, max_list_count, list_start_offset, list_count
            )
        )

        return status, rsp_headers

    def ProcessMessageListing(self, name, params):
        """Lists messages in the given folder.

        Args:
            name: name of the folder to list the messages from
            params: a list of request parameters of type AppParamsHeader

        Returns:
            status: SUCCESS if message listing succeeded
            headers: a list of response headers of type ObexHeader
        """

        status = self.RSP_SUCCESS
        rsp_headers = []
        rsp_params = []

        list_count = 0
        max_list_count = None
        list_start_offset = None
        filter_msg_type = None

        for param in params:
            if param.id == self.PARAM_MAX_LIST_COUNT:
                max_list_count = struct.unpack(">H", param.value)[0]
            elif param.id == self.PARAM_LIST_START_OFFSET:
                list_start_offset = struct.unpack(">H", param.value)[0]
            elif param.id == self.PARAM_FILTER_MESSAGE_TYPE:
                filter_msg_type = struct.unpack(">B", param.value)[0]
            elif (
                param.id == self.PARAM_FILTER_PERIOD_BEGIN
                or param.id == self.PARAM_FILTER_PERIOD_END
                or param.id == self.PARAM_FILTER_READ_STATUS
                or param.id == self.PARAM_FILTER_RECIPIENT
                or param.id == self.PARAM_FILTER_ORIGINATOR
                or param.id == self.PARAM_FILTER_PRIORITY
                or param.id == self.PARAM_PARAMETER_MASK
                or param.id == self.PARAM_SUBJECT_LENGTH
                or param.id == self.PARAM_CONVERSATION_ID
                or param.id == self.PARAM_FILTER_MESSAGE_HANDLE
            ):
                logging.warning(
                    "MapServer: Ignoring message-listing param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )
            else:
                logging.warning(
                    "MapServer: Unexpected message-listing param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )

        # Create the message listing XML object
        xml_obj = self.TAG_HEADER + self.TAG_MESSAGE_LISTING_BEGIN
        path = os.path.join(self.base_dir, self.curr_dir, name)

        # We only have GSM messages, so, include messages only if the SMS_GSM
        # messages are requested or no filter is set. Note that if the bit for
        # specific message type is set, it means exclude that type of messages.
        if filter_msg_type is None or (filter_msg_type & self.MSG_SMS_GSM) == 0:
            i = 0
            for item in pathlib.Path(path).iterdir():
                if item.is_file() and item.name != "mlisting.xml":
                    # If max_list_count is 0, only count total messages
                    if max_list_count is not None and max_list_count == 0:
                        list_count += 1
                        continue

                    # Skip all messages before list_start_offset'th message
                    if list_start_offset is not None and i < list_start_offset:
                        i += 1
                        continue

                    # Use self.curr_time as message timestamp so these messages
                    # will always look like recent messages for every test run.
                    xml_obj += self.TAG_MESSAGE_LISTING_MSG.format(
                        self.curr_time, item.name, list_count
                    )

                    list_count += 1

                    # if max_list_count is specified, list only that many messages
                    if (
                        max_list_count is not None
                        and list_count == max_list_count
                    ):
                        break

        xml_obj += self.TAG_MESSAGE_LISTING_END

        # Add message listing size to app parameters
        list_count_bytes = struct.pack(">H", list_count)
        curr_time_bytes = self.curr_time.encode("utf-8")

        rsp_params.append(
            AppParamsHeader(
                self.PARAM_LISTING_SIZE, len(list_count_bytes), list_count_bytes
            )
        )
        rsp_params.append(AppParamsHeader(self.PARAM_NEW_MESSAGE, 1, b"\x00"))
        rsp_params.append(
            AppParamsHeader(
                self.PARAM_MSE_TIME, len(curr_time_bytes), curr_time_bytes
            )
        )

        # Create response headers
        rsp_headers.append(
            ObexHeader(self.OBJ_APP_PARAM, self.PackAppParams(rsp_params))
        )

        # Return message list only if max_list_count not specified or non-zero
        if max_list_count is None or max_list_count != 0:
            rsp_headers.append(
                ObexHeader(self.OBJ_END_OF_BODY, xml_obj.encode("utf-8"))
            )

        logging.debug(
            "MapProfile: List message {}, max {}, offset {}, type {} - {} items".format(
                os.path.join(self.curr_dir, name),
                max_list_count,
                list_start_offset,
                filter_msg_type,
                list_count,
            )
        )

        return status, rsp_headers

    def ProcessGetMessage(self, name, params):
        """Returns the message data of the given message handle.

        Args:
            name: name of the message handle in the current folder
            params: a list of request parameters of type AppParamsHeader

        Returns:
            status: SUCCESS if get message succeeded
            headers: a list of response headers of type ObexHeader
        """

        status = self.RSP_SUCCESS
        rsp_headers = []
        rsp_params = []

        fraction_request = False

        for param in params:
            if param.id == self.PARAM_FRACTION_REQUEST:
                fraction_request = True
            elif (
                param.id == self.PARAM_ATTACHMENT
                or param.id == self.PARAM_CHARSET
            ):
                logging.warning(
                    "MapServer: Ignoring get-message param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )
            else:
                logging.warning(
                    "MapServer: Unexpected get-message param 0x{:02x} 0x{}".format(
                        param.id, param.value.hex()
                    )
                )

        # Every message handle is unique and it could be present anywhere in
        # the map_root. So, search in the entire map_root tree.
        path = str(next(pathlib.Path(self.base_dir).rglob(name)))
        data = b""

        if not os.path.exists(path):
            logging.error("MapProfile: Message not found {}".format(path))
            status = self.RSP_NOT_FOUND
            return status, rsp_headers

        # Read the message data, which is already in BMSG format
        try:
            fd = open(path, "rb")
            data = fd.read()
            fd.close()
        except Exception as e:
            logging.error("MapProfile: Read error {}: {}".format(path, e))
            status = self.RSP_NOT_FOUND
            return status, rsp_headers

        # Create response headers
        if fraction_request:
            rsp_params.append(
                AppParamsHeader(self.PARAM_FRACTION_DELIVER, 1, b"\x00")
            )
            rsp_headers.append(
                ObexHeader(self.OBJ_APP_PARAM, self.PackAppParams(rsp_params))
            )

        rsp_headers.append(ObexHeader(self.OBJ_END_OF_BODY, data))

        logging.debug(
            "MapProfile: Get message {}".format(
                pathlib.Path(path).relative_to(pathlib.Path(self.base_dir))
            )
        )

        return status, rsp_headers

    def ProcessNotificationReg(self, params, data, length):
        """Enables/disables notification registration.

        Args:
            params: a list of request parameters of type AppParamsHeader
            data: request data
            length: request data length

        Returns:
            status: SUCCESS if set notification registration succeeded
            headers: a list of response headers of type ObexHeader
        """

        # Set Notification Registration response doesn't require any headers in
        # response. Return success with empty headers so the client knows that
        # the registration succeeded.
        return self.RSP_SUCCESS, []

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

        self.curr_dir = self.MAP_ROOT

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

        type = ""
        params = []
        data = b""
        length = 0

        for header in req_headers:
            if header.id == self.OBJ_TYPE:
                type = self.ParseType(header.value)
            elif header.id == self.OBJ_APP_PARAM:
                params = self.ParseAppParams(header.value)
            elif header.id == self.OBJ_LENGTH:
                length = struct.unpack(">I", header.value)[0]
            elif (
                header.id == self.OBJ_BODY or header.id == self.OBJ_END_OF_BODY
            ):
                data = header.value
            elif header.id != self.OBJ_CONN_ID:
                logging.warning(
                    "MapProfile: Unexpected Put header 0x{:02x} 0x{}".format(
                        header.id, header.value.hex()
                    )
                )

        headers = []

        if type == self.TYPE_NOTIFICATION_REG:
            status, headers = self.ProcessNotificationReg(params, data, length)
        else:
            logging.error("MapProfile: Unsupported Put {}".format(type))
            status = self.RSP_NOT_IMPLEMENTED

        rsp_headers += headers

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
                    "MapProfile: Unexpected get header 0x{:02x} 0x{}".format(
                        header.id, header.value.hex()
                    )
                )

        headers = []

        if type == self.TYPE_FOLDER_LISTING:
            status, headers = self.ProcessFolderListing(params)
        elif type == self.TYPE_MSG_LISTING:
            status, headers = self.ProcessMessageListing(name, params)
        elif type == self.TYPE_GET_MESSAGE:
            status, headers = self.ProcessGetMessage(name, params)
        else:
            logging.error("MapProfile: Unsupported Get {}".format(type))
            status = self.RSP_NOT_IMPLEMENTED

        rsp_headers += headers

        return status, rsp_headers

    def ProcessMapSetPath(self, data):
        """Processes SetPath Request.

        Args:
            data: bytes array of raw data from OBEX packet

        Returns:
            status: SUCCESS if packet parsing succeeded
            headers: a list of response headers of type ObexHeader
        """

        # SetPath response doesn't include any headers, return empty headers
        rsp_headers = []

        status, flags, req_headers = self.ProcessSetPath(data)
        if status != self.RSP_SUCCESS:
            return status, rsp_headers

        for header in req_headers:
            if header.id == self.OBJ_NAME:
                to_parent = flags & 0x01  # check 0th bit of flags
                name = self.ParseName(header.value)

                temp_curr_dir = self.curr_dir

                if to_parent:
                    if self.curr_dir == self.MAP_ROOT:
                        logging.error("MapProfile: Already at map_root")
                        status = self.RSP_FORBIDDEN
                        break

                    if len(name):
                        # Go 1 level up and switch to "name" directory
                        self.curr_dir = os.path.dirname(self.curr_dir)
                        self.curr_dir = os.path.join(self.curr_dir, name)
                    else:
                        # Go 1 level up
                        self.curr_dir = os.path.dirname(self.curr_dir)
                else:
                    if len(name):
                        # Go 1 level down to "name" directory
                        self.curr_dir = os.path.join(self.curr_dir, name)
                    else:
                        # Go to root directory
                        self.curr_dir = self.MAP_ROOT

                dest_dir = os.path.join(self.base_dir, self.curr_dir)
                if not os.path.exists(dest_dir) or not os.path.isdir(dest_dir):
                    logging.error(
                        "MapProfile: Cannot switch to {}".format(dest_dir)
                    )
                    self.curr_dir = temp_curr_dir
                    status = self.RSP_NOT_FOUND
                    break

                logging.debug("MapProfile: Switch to {}".format(self.curr_dir))

            elif header.id != self.OBJ_CONN_ID:
                logging.warning(
                    "MapProfile: Unexpected set-path header 0x{:02x} 0x{}".format(
                        header.id, header.value.hex()
                    )
                )

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

        elif opcode == self.REQ_PUT or opcode == self.REQ_PUT_FINAL:
            status, headers = self.ProcessMapPut(data)

        elif opcode == self.REQ_GET or opcode == self.REQ_GET_FINAL:
            status, headers = self.ProcessMapGet(data)

        elif opcode == self.REQ_SETPATH:
            status, headers = self.ProcessMapSetPath(data)

        else:
            logging.error(
                "MapProfile: Unsupported Request 0x{:02x}".format(opcode)
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
