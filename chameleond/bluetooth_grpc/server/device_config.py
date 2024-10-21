# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.


from blueship import config_pb2


DEFAULT_CHAMELEON_CONFIG = config_pb2.Configuration(
    api=config_pb2.APIConfig(
        support_api_version=config_pb2.ConfigVariant(
            writable=False, string_value="0.0"
        ),
    ),
)
