# Lint as: python2, python3
# pylint: disable=import-error,no-name-in-module
# -*- coding: utf-8 -*-
# Copyright 2022 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module implements the Fast Pair GATT service on bluez"""

from base64 import b64encode
import logging
from math import floor
from os import urandom

from chameleond.utils import pairing_agent
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import algorithms
from cryptography.hazmat.primitives.ciphers import Cipher
from cryptography.hazmat.primitives.ciphers import modes
import dbus

from utils.bluez_le_hid_service import LEApplication
from utils.example_gatt_server import Characteristic
from utils.example_gatt_server import GATT_CHRC_IFACE
from utils.example_gatt_server import Service


class FastPairLEApplication(LEApplication):
    """Fast Pair application."""

    def __init__(self, bus, device):
        LEApplication.__init__(self, bus)
        self._service = FastPairService(bus, 0, device)
        self.AddService(self._service)

    def GetServiceData(self):
        return self._service.GetServiceData()

    def SetAntiSpoofingKeyPem(self, key_pem):
        self._service.SetAntiSpoofingKeyPem(key_pem)

    def AddAccountKey(self, account_key):
        self._service.AddAccountKey(account_key.data)


class FastPairService(Service):
    """Fast Pair service

    See https://developers.google.com/nearby/fast-pair/spec for public spec.
    """

    SERVICE_UUID = "0xFE2C"
    POINT_CONVERSION_UNCOMPRESSED = 0x04
    ACCOUNT_KEY_LENGTH = 16
    MAX_ACCOUNT_KEYS = 5

    def __init__(self, bus, index, device):
        Service.__init__(self, bus, index, self.SERVICE_UUID, True)

        self.add_characteristic(ModelIDChrc(bus, 0, self))
        self.add_characteristic(KeyBasedPairingChrc(bus, 1, self))
        self.add_characteristic(PasskeyChrc(bus, 2, self))
        self.add_characteristic(AccountKeyChrc(bus, 3, self))
        self.add_characteristic(AdditionalDataChrc(bus, 4, self))

        self._device = device
        self._account_keys = []

        self._anti_spoofing_key = None
        self._shared_secret = None

    def GetServiceData(self):
        if len(self._account_keys) < 1:
            logging.info("Returning model ID service data")
            # Model ID for this test device
            return [0x38, 0x35, 0x67]

        # https://developers.google.com/nearby/fast-pair/spec#advertising_payload_fast_pair_account_data
        size_of_filter = floor((1.2 * len(self._account_keys)) + 3)
        account_key_filter = [0] * size_of_filter
        salt = urandom(1)

        for key in self._account_keys:
            v = key + salt

            digest = hashes.Hash(hashes.SHA256(), backend=default_backend())
            digest.update(v)
            hash_v = digest.finalize()

            for i in range(0, len(hash_v), 4):
                piece = int.from_bytes(hash_v[i : i + 4], "big")
                m = piece % (size_of_filter * 8)
                account_key_filter[m // 8] |= 1 << (m % 8)

        service_data = [0]
        service_data.append(size_of_filter << 4)
        service_data += account_key_filter
        service_data.append(17)  # Salt header and length (1)
        service_data.append(int.from_bytes(salt, "big"))

        logging.info("Returning account key filter service data")
        return service_data

    def SetAntiSpoofingKeyPem(self, key_pem):
        if key_pem:
            logging.info("Setting the anti-spoofing key")
            self._anti_spoofing_key = serialization.load_pem_private_key(
                key_pem.data, password=None, backend=default_backend()
            )
        else:
            logging.info("Clearing the anti-spoofing key")
            self._anti_spoofing_key = None

    def GetDeviceAddressBytes(self):
        address = self._device.GetLocalBluetoothAddress()
        normalized_address = address.replace(":", "")
        return bytes.fromhex(normalized_address)

    def SetSharedSecretFromPublicKey(self, public_key_bytes):
        logging.info("Setting shared secret from given public key")

        if self._anti_spoofing_key is None:
            logging.error(
                "Antispoofing key not set. Cannot compute shared secret."
            )
            return False

        # First we prefix the public key with the 'uncompressed' point type.
        public_key_bytes.insert(
            0, dbus.Byte(self.POINT_CONVERSION_UNCOMPRESSED)
        )

        curve = ec.SECP256R1()
        public_key = ec.EllipticCurvePublicKey.from_encoded_point(
            curve, bytes(public_key_bytes)
        )

        shared_key = self._anti_spoofing_key.exchange(ec.ECDH(), public_key)

        digest = hashes.Hash(hashes.SHA256(), backend=default_backend())
        digest.update(shared_key)
        shared_key_bytes = digest.finalize()

        self._shared_secret = bytes(list(shared_key_bytes)[:16])
        logging.info("Shared secret successfully set.")

        return True

    def SetSharedSecretFromAccountKeys(self, encrypted_bytes):
        for account_key in self._account_keys:
            cipher = Cipher(
                algorithms.AES(account_key),
                modes.ECB(),
                backend=default_backend(),
            )
            decrypted_bytes = cipher.decryptor().update(bytes(encrypted_bytes))

            if len(decrypted_bytes) != 0:
                self._shared_secret = account_key
                return True

            return False

    def Decrypt(self, encrypted_bytes):
        logging.info("Attempting to decrypt %d bytes", len(encrypted_bytes))

        if self._shared_secret is None:
            logging.error("Failed to decrypt value: No shared secret set.")
            return None

        cipher = Cipher(
            algorithms.AES(self._shared_secret),
            modes.ECB(),
            backend=default_backend(),
        )
        return cipher.decryptor().update(bytes(encrypted_bytes))

    def Encrypt(self, bytes_to_encrypt):
        logging.info("Attempting to encrypt %d bytes", len(bytes_to_encrypt))

        if self._shared_secret is None:
            logging.error("Failed to encrypt value: No shared secret set.")
            return None

        cipher = Cipher(
            algorithms.AES(self._shared_secret),
            modes.ECB(),
            backend=default_backend(),
        )
        return cipher.encryptor().update(bytes(bytes_to_encrypt))

    def AddAccountKey(self, account_key):
        if len(self._account_keys) == self.MAX_ACCOUNT_KEYS:
            self._account_keys.pop(0)

        self._account_keys.append(account_key)

    def AddEncryptedAccountKey(self, value):
        if self._shared_secret is None:
            logging.warning(
                "Ignoring AddEncryptedAccountKey call. No shared secret set."
            )
            return

        if len(value) != self.ACCOUNT_KEY_LENGTH:
            logging.warning(
                "Ignoring AddEncryptedAccountKey call. Invalid length"
            )
            return

        decrypted_account_key = self.Decrypt(value)

        if decrypted_account_key is None:
            logging.warning(
                "Ignoring AddEncryptedAccountKey call. Failed to decrypt value."
            )
            return

        self.AddAccountKey(decrypted_account_key)

        logging.info(
            "Pairing procedure complete. Update advertisement to non-discoverable advertisement."
        )
        self._device.SetDiscoverable(False)
        self._device.SetDiscoverable(True)


class ModelIDChrc(Characteristic):
    """Model ID Characteristic"""

    CHRC_UUID = "FE2C1233-8366-4814-8EB0-01DE32100BEA"
    MODEL_ID = [dbus.Byte(b) for b in bytes.fromhex("383567")]

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.CHRC_UUID, ["read"], service
        )

    def ReadValue(self, _):
        return self.MODEL_ID


class KeyBasedPairingChrc(Characteristic):
    """Key-based Pairing Characteristic"""

    CHRC_UUID = "FE2C1234-8366-4814-8EB0-01DE32100BEA"
    REQUEST_BYTES_LENGTH = 16
    REQUEST_TYPE = 0x0
    RESPONSE_TYPE = 0x01
    EXT_RESPONSE_TYPE = 0x02
    SALT_BYTES_LENGTH = 9
    EXT_SALT_BYTES_LENGTH = 7
    KEY_BASED_PAIRING_REQUEST_TYPE = 0x0
    ENCRYPTED_REQUEST_BYTES_LENGTH = 16
    REQUEST_WITH_KEY_LENGTH = 80
    EXT_RESPONSE_FLAGS = 0xC0

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.CHRC_UUID, ["write", "notify"], service
        )

        self._notifying = False
        self._supports_ble_spec = False

    def VerifyRequestBytes(self, request_bytes):
        """Verify the request bytes according to the spec.

        See https://developers.google.com/nearby/fast-pair/spec#data_format
        """

        if len(request_bytes) != self.REQUEST_BYTES_LENGTH:
            logging.warning(
                "Invalid request bytes length. Expected:%d Actual:%d",
                self.REQUEST_BYTES_LENGTH,
                len(request_bytes),
            )
            return False

        # First byte should be the Key-based Pairing request message type (0x0)
        if request_bytes[0] != self.REQUEST_TYPE:
            logging.warning(
                "Invalid first byte in request bytes: Expected:%s Actual:%s",
                hex(self.REQUEST_TYPE),
                hex(request_bytes[0]),
            )
            return False

        # Second byte should be 0x0, 0x10, 0x08, 0x18 which are the four flag values we
        # support
        if request_bytes[1] not in [0x0, 0x10, 0x08, 0x18]:
            logging.warning(
                """Invalid second byte in request bytes: Expected:0x0, 0x10, 0x08, or 0x18
                                            , Actual:%s""",
                hex(request_bytes[1]),
            )
            return False

        # Flag = 0x08 and 0x18 indicates the seeker supports the BLE Device Specification
        if request_bytes[1] == 0x08 or request_bytes[1] == 0x18:
            logging.info(
                "Seeker indicates support for BLE device specification."
            )
            self._supports_ble_spec = True

        # Bytes 2-7 should be this devices address.
        if self.service.GetDeviceAddressBytes() != request_bytes[2:8]:
            logging.warning("Invalid Provider's address bytes in request.")
            return False

        # If flag bits 1 or 3 is set, verify bytes 8-13 are non-zero
        if (
            (request_bytes[1] & 0x1 != 0) or (request_bytes[1] & 0x10 != 0)
        ) and not any(request_bytes[8:14]):
            logging.warning(
                "Invalid bytes 8-13 in request. Expected Seeker's address to be set"
            )
            return False

        # Remaining bytes are the random salt value. Exepct this to not be all zeros
        if not any(request_bytes[14:]):
            logging.warning("Invalid salt valud in request bytes.")
            return False

        return True

    def BuildResponseBytes(self):
        # First byte is the message type, 0x01 = Key-based pairing response.
        response_bytes = bytes([self.RESPONSE_TYPE])

        # Bytes 1-6 are this devices address.
        response_bytes += self.service.GetDeviceAddressBytes()

        # Bytes 7-15 are random bytes to represent a salt value.
        response_bytes += urandom(self.SALT_BYTES_LENGTH)

        return response_bytes

    def BuildExtendedResponseBytes(self):
        # First byte is the message type, 0x02 = Key-based pairing extended response.
        response_bytes = bytes([self.EXT_RESPONSE_TYPE])

        # Byte 1 is the flags. We support LE only and prefer LE bonding.
        response_bytes += bytes([self.EXT_RESPONSE_FLAGS])

        # Byte 2 is the number of provider's addresses. We support 1.
        response_bytes += bytes([0x01])

        # Bytes 3-8 are this devices address.
        response_bytes += self.service.GetDeviceAddressBytes()

        # Bytes 9-15 are random bytes to represent a salt value.
        response_bytes += urandom(self.EXT_SALT_BYTES_LENGTH)

        return response_bytes

    def StartNotify(self):
        """Called by dbus - requests notifications"""

        logging.info("KeyBasedPairingChrc: StartNotify")
        if self._notifying:
            return

        self._notifying = True

    def StopNotify(self):
        """Called by dbus - requests stop to notifications"""

        logging.info("KeyBasedPairingChrc: StopNotify")
        if not self._notifying:
            return

        self._notifying = False

    def WriteValue(self, value, _):
        """Called by dbus - writes a value to this characteristic"""

        logging.info(
            "KeyBasedPairingChrc: WriteValue: %s", b64encode(bytes(value))
        )

        if not self._notifying:
            logging.warning(
                "Ignoring WriteValue because of no active notify session"
            )
            return

        valid_length = (
            len(value) == self.ENCRYPTED_REQUEST_BYTES_LENGTH
            or len(value) == self.REQUEST_WITH_KEY_LENGTH
        )

        if not valid_length:
            logging.warning("Ignoring WriteValue because of invalid length")
            return

        encrypted_request = value[: self.ENCRYPTED_REQUEST_BYTES_LENGTH]

        if len(value) == self.REQUEST_WITH_KEY_LENGTH:
            public_key = value[self.ENCRYPTED_REQUEST_BYTES_LENGTH :]

            if not self.service.SetSharedSecretFromPublicKey(public_key):
                logging.warning(
                    "Ignoring write - Failed to compute shared secret"
                )
                return

        else:
            if not self.service.SetSharedSecretFromAccountKeys(
                encrypted_request
            ):
                logging.warning(
                    "Ignoring write - Failed to find shared account key"
                )
                return

        decrypted_bytes = self.service.Decrypt(encrypted_request)

        if decrypted_bytes is None:
            logging.warning("Ignoring request. Failed to decrypt bytes")
            return

        if not self.VerifyRequestBytes(decrypted_bytes):
            logging.warning("Ignoring request due to invalid bytes")
            return

        if self._supports_ble_spec:
            response_bytes = self.BuildExtendedResponseBytes()
        else:
            response_bytes = self.BuildResponseBytes()
        encrypted_response = self.service.Encrypt(response_bytes)

        if encrypted_response is None:
            logging.warning("Failed to encrypt response.")
            return

        # Notify response.
        self.PropertiesChanged(
            GATT_CHRC_IFACE,
            {"Value": [dbus.Byte(b) for b in encrypted_response]},
            [],
        )


class PasskeyChrc(Characteristic):
    """Passkey Characteristic"""

    CHRC_UUID = "FE2C1235-8366-4814-8EB0-01DE32100BEA"
    REQUEST_BYTES_LENGTH = 16
    SEEKERS_MESSAGE_TYPE = 0x02
    PROVIDERS_MESSAGE_TYPE = 0x03
    SALT_BYTES_LENGTH = 12

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.CHRC_UUID, ["write", "notify"], service
        )

        self._notifying = False

    def StartNotify(self):
        """Called by dbus - requests notifications"""

        logging.info("PasskeyChrc: StartNotify")
        if self._notifying:
            return

        self._notifying = True

    def StopNotify(self):
        """Called by dbus - requests stop to notifications"""

        logging.info("PasskeyChrc: StopNotify")
        if not self._notifying:
            return

        self._notifying = False

    def VerifyPasskeyBytes(self, passkey_bytes):
        """Verify the passkey bytes according to the spec.

        See https://developers.google.com/nearby/fast-pair/spec#Passkey
        """

        if len(passkey_bytes) != self.REQUEST_BYTES_LENGTH:
            logging.warning(
                "Invalid passkey bytes length. Expected:%d Actual:%d",
                self.REQUEST_BYTES_LENGTH,
                len(passkey_bytes),
            )
            return False

        # First byte should be 0x02 - Seeker's Passkey message type
        if passkey_bytes[0] != self.SEEKERS_MESSAGE_TYPE:
            logging.warning(
                "Invalid first byte in passkey. Expected:%s, Actual:%s",
                hex(self.SEEKERS_MESSAGE_TYPE),
                hex(passkey_bytes[0]),
            )
            return False

        return True

    def BuildResponseBytes(self):
        # First byte is the message type - 0x03 is Provider's passkey.
        response_bytes = bytes([self.PROVIDERS_MESSAGE_TYPE])

        # Bytes 1-3 are this devices passkey.
        response_bytes += pairing_agent.agent.passkey.to_bytes(3, "big")

        # Bytes 4-15 are the salt value (random bytes)
        response_bytes += urandom(self.SALT_BYTES_LENGTH)

        return response_bytes

    def WriteValue(self, value, _):
        """Called by dbus - writes a value to this characteristic"""

        logging.info("PasskeyChrc: WriteValue: %s", b64encode(bytes(value)))

        decrypted_bytes = self.service.Decrypt(value)

        if decrypted_bytes is None:
            logging.warning("Ignoring passkey write - Failed to decrypt bytes")
            return

        if not self.VerifyPasskeyBytes(decrypted_bytes):
            logging.warning("Ignoring passkey write due to invalid bytes.")
            return

        passkey = int.from_bytes(decrypted_bytes[1:4], "big")

        if pairing_agent.agent.DoesPasskeyMatch(passkey):
            logging.info("Passkey matches.")
        else:
            logging.warning(
                "Passkeys didn't match. Expected: %06d Actual: %06d",
                pairing_agent.agent.passkey,
                passkey,
            )
            return

        response_bytes = self.BuildResponseBytes()
        encrypted_response = self.service.Encrypt(response_bytes)

        if encrypted_response is None:
            logging.warning("Failed to encrypt response")
            return

        # Notify response.
        self.PropertiesChanged(
            GATT_CHRC_IFACE,
            {"Value": [dbus.Byte(b) for b in encrypted_response]},
            [],
        )


class AdditionalDataChrc(Characteristic):
    """Additional Data Characteristic"""

    CHRC_UUID = "FE2C1237-8366-4814-8EB0-01DE32100BEA"

    # This Additional Data Characteristic is defined in the spec here:
    # https://developers.google.com/nearby/fast-pair/specifications/characteristics#AdditionalData
    # The implementation is currently a mock that supports 'write' and 'notify' but is a no-op
    # for both.
    # TODO(b/286997038): Allow the Provider implementation to support device name changes via this
    # Additional Data characteristic.

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.CHRC_UUID, ["write", "notify"], service
        )

        self._notifying = False

    def StartNotify(self):
        """Called by dbus - requests notifications"""

        logging.info("AdditionalDataChrc: StartNotify")
        if self._notifying:
            return

        self._notifying = True

    def StopNotify(self):
        """Called by dbus - requests stop to notifications"""

        logging.info("AdditionalDataChrc: StopNotify")
        if not self._notifying:
            return

        self._notifying = False

    def WriteValue(self, value, _):
        """Called by dbus - writes a value to this characteristic"""

        logging.info(
            "AdditionalDataChrc: WriteValue: %s", b64encode(bytes(value))
        )

        # Notify response.
        self.PropertiesChanged(GATT_CHRC_IFACE, {"Value": []}, [])


class AccountKeyChrc(Characteristic):
    """Account Key Characteristic"""

    CHRC_UUID = "FE2C1236-8366-4814-8EB0-01DE32100BEA"
    ACCOUNT_KEY_LENGTH = 16

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.CHRC_UUID, ["write"], service
        )

    def WriteValue(self, value, _):
        """Called by dbus - writes a value to this characteristic"""

        logging.info("AccountKeyChrc: WriteValue: %s", b64encode(bytes(value)))

        if len(value) != self.ACCOUNT_KEY_LENGTH:
            logging.warning("Ignoring write - Invalid length.")
            return

        self.service.AddEncryptedAccountKey(value)
