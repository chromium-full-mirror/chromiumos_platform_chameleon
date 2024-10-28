# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from blueship import manager_pb2


DEFAULT_CHAMELEON_CONFIG = manager_pb2.Configuration(
    api=manager_pb2.APIConfig(
        support_api_version=manager_pb2.ConfigVariant(
            writable=False, string_value="0.0"
        ),
    ),
    device=manager_pb2.DeviceInfoConfig(
        io_capability=manager_pb2.ConfigVariant(
            writable=True,
            io_capability=manager_pb2.IO_CAPABILITY_NO_INPUT_NO_OUTPUT,
        ),
        category=manager_pb2.ConfigVariant(
            writable=True, device_category=manager_pb2.DEVICE_CATEGORY_KEYBOARD
        ),
    ),
    controller=manager_pb2.ControllerConfig(
        support_classic=manager_pb2.ConfigVariant(
            writable=True,
            bool_value=False,
        ),
        support_le=manager_pb2.ConfigVariant(
            writable=True,
            bool_value=True,
        ),
    ),
    security=manager_pb2.SecurityConfig(
        pin=manager_pb2.ConfigVariant(writable=True, string_value="0000"),
    ),
    audio=manager_pb2.AudioConfig(
        supported_codecs=manager_pb2.ConfigVariant(
            writable=True,
            codec_list=manager_pb2.RepeatedCodec(
                codec_list=[manager_pb2.CODEC_CVSD]
            ),
        )
    ),
)
