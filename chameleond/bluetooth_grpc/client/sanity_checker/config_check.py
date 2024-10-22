# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import unittest

from blueship import config_pb2
from blueship.config_grpc import Config
import grpc


PANDORA_SERVER_PORT = 8999


class ConfigGrpcTests(unittest.TestCase):
    """Class to perform sanity check on ConfigService via unittest framework"""

    DEFAULT_API_VERSION = "0.0"

    def setUp(self):
        """Setup the testing environment"""
        # TODO: Start gRPC server before the tests
        self.proxy = grpc.insecure_channel(f"localhost:{PANDORA_SERVER_PORT}")
        self.config_proxy = Config(self.proxy)

    def tearDown(self):
        """Clear the testing environment"""
        self.config_proxy.ClearConfig()

    def test_read_api(self):
        """Test Support API Version can be read"""
        resp = self.config_proxy.ReadConfig()
        self.assertEqual(
            resp.config.api.support_api_version.string_value,
            self.DEFAULT_API_VERSION,
        )

    def test_write_api(self):
        """Test Support API Version can not be written on chameleon"""
        write_config = config_pb2.Configuration()
        write_config.api.support_api_version.string_value = "0.2"
        resp = self.config_proxy.WriteConfig(write_config)
        # Write config request should succeed
        self.assertTrue(resp.success)

        # API version should not be changed.
        resp = self.config_proxy.ReadConfig()
        self.assertEqual(
            resp.config.api.support_api_version.string_value,
            self.DEFAULT_API_VERSION,
        )


if __name__ == "__main__":
    unittest.main()
