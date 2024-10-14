# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from blueship.audio_grpc import Audio
import grpc
from pandora.host_grpc import Host
from pandora.security_grpc import Security


PANDORA_SERVER_PORT = 8999

proxy = grpc.insecure_channel(f"localhost:{PANDORA_SERVER_PORT}")
host_proxy = Host(proxy)
security_proxy = Security(proxy)
audio_proxy = Audio(proxy)

print(
    "Example usage:\n"
    "This starts an interactive shell where you can call any function in the\n"
    "proxy as if you are writing Python. Type `exit` to leave.\n"
    ">   audio_proxy.StartPlayAudioRequest(0, '/tmp/audio/record.wav')\n"
    ">   audio_proxy.StopRecordAudio()\n"
    ">   exit\n"
    "------------------------------------------------------------------------\n"
)

print(
    "Available proxy:\n"
    f"\thost_proxy ({type(host_proxy)})\n"
    f"\tsecurity_proxy ({type(security_proxy)})\n"
    f"\taudio_proxy ({type(audio_proxy)})\n"
)

while True:
    cmd = input("> ")
    if cmd == "exit":
        break
    try:
        exec(cmd)
    except Exception as error:
        print(error)
