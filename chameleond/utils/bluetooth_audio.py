# Lint as: python2, python3
# -*- coding: utf-8 -*-
# Copyright 2020 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module provides an abstraction of bluetooth audio device."""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import logging
import os
import re
import struct
import time
import wave

from chameleond.utils import common
from chameleond.utils.bluetooth_peripheral_kit import PeripheralKit
from chameleond.utils.bluetooth_raspi import BluezPeripheral
from chameleond.utils.bluetooth_raspi import BluezPeripheralException
from chameleond.utils.bluez_service_consts import CLASS_OF_DEVICE_MASK
from chameleond.utils.bluez_service_consts import CLASS_OF_SERVICE_MASK
from chameleond.utils.bluez_service_consts import PERIPHERAL_DEVICE_CLASS
from chameleond.utils.bluez_service_consts import PERIPHERAL_DEVICE_NAME
from chameleond.utils.system_tools import SystemTools
import numpy as np
from six.moves import range

from . import chameleon_common  # pylint: disable=W0611, C0411


class BluetoothAudioException(BluezPeripheralException):
    """A dummy exception class for BluetoothAudio class."""

    pass


class Wav(object):
    """A class to generate a wav file and write frames in an efficient way."""

    # The max count of reading frames through fromfile to prevent from reading
    # unlimitedly.
    COUNT_MAX = 10

    def __init__(
        self,
        filename,
        nchannels=2,
        sample_width=2,
        frame_rate=48000,
        nframes=0,
        comptype="NONE",
        compname="not compressed",
    ):
        self.nframes = nframes
        self.filename = filename
        self.wav_file = wave.open(filename, "w")
        params = (
            nchannels,
            sample_width,
            frame_rate,
            nframes,
            comptype,
            compname,
        )
        self.wav_file.setparams(params)

    def _write(self, data):
        """Write frames to the wave file in an efficient way.

        It is about 20 times faster by writing all data at once than the usual way
        of writing frame by frame:

          for d in data:
            self.wav_file.writeframes(struct.pack('h', int(d)))

        Args:
          data: the frame data
        """
        s = "".join([struct.pack("h", int(d)) for d in data])
        self.wav_file.writeframes(s)

    def WriteToWavFile(self, fin):
        """Write the frames to the wave file.

        Read frames from fin and write the frames to the wave file.

        Args:
          fin: the input file object which is the stdout pipe of a subprocess

        Returns:
          The number of frames written into the wave file.
        """
        logging.info("WriteToWavFile: from %s to %s", fin.name, self.filename)

        nframes = 0
        count = 0
        buf_count = self.nframes
        while nframes < self.nframes and count < self.COUNT_MAX:
            frames = np.fromfile(fin.stdout, dtype=np.int16, count=buf_count)
            nframes += len(frames)
            self._write(frames)
            logging.info(
                "count %d, get / accumulate / total: %d / %d / %d frames",
                count,
                len(frames),
                nframes,
                self.nframes,
            )
            buf_count = self.nframes - nframes
            count += 1
        return nframes

    def close(self):
        """Close the wave file."""
        self.wav_file.close()


class BluetoothAudio(BluezPeripheral):
    """An object that performs Bluetooth audio device related operations."""

    PULSEAUDIO = "pulseaudio"
    OFONO = "ofono"
    MPRISPROXY = "mpris-proxy"
    PLAYERCTL = "playerctl"
    NO_PLAYER_FOUND = "No players were found\n"
    DBUS_SESSION_ENV_VAR_NAME = "DBUS_SESSION_BUS_ADDRESS"
    DBUS_SESSION_ENV_VAR_VALUE = "unix:path=/run/user/0/bus"
    SSH_OPTIONS = (
        " -i /root/.ssh/testing_rsa "
        "-o UserKnownHostsFile=/dev/null "
        "-o StrictHostKeyChecking=no "
    )
    START_PULSEAUDIO_TIMES = 5
    INTERVAL_BETWEEN_START_PULSEAUDIO_SECS = 0.2
    WAIT_PULSEAUDIO_READY_SECS = 1

    AUDIO_SERVER = "audio_server"
    A2DP_CODEC = "a2dp_codec"
    SBC = "sbc"
    AAC = "aac"

    # pipewire related processes
    # Note: pipewire-pulse is not needed in tests
    PIPEWIRE = "pipewire"
    WIREPLUMBER = "wireplumber"
    WPCTL = "wpctl"
    SYSTEMCTL = "systemctl"
    START_PIPEWIRE_TIMES = 2
    PIPEWIRE_READY_TIMEOUT_SECS = 5
    INTERVAL_BETWEEN_START_PIPEWIRE_SECS = 1

    # The pipewire related processes:
    # - pipewire: the audio server process
    # - wireplumber: an auxiliary process for configuring pipewire
    # Note: starting pipewire will auto start pipewire.socket as well.
    PIPEWIRE_PROCESSES_TO_START = [f"{PIPEWIRE}", f"{WIREPLUMBER}"]

    # Note: the pipewire.socket must be stopped before pipewire.
    #       Otherwise, pipewire.socket will auto restart pipewire.
    PIPEWIRE_PROCESSES_TO_STOP = [f"{PIPEWIRE}.socket", f"{PIPEWIRE}"]

    def __init__(self):
        """Initializes a Bluetooth audio object."""
        BluezPeripheral.__init__(self)
        self._record = None
        self._recorded_file = None
        self._remaining_size = 0
        self._chunk_file = None
        self._wav = None
        self._pulseaudio = None
        self._play = None
        self._profile = None
        self._media_player = None
        self._pi_uid = self.GetUserIdOfPi()
        self._pulse_socket_file = f"/run/user/{self._pi_uid}/pulse/native"

        # Set up the pi environment so that the audio subprocess methods in
        # SystemTools can connect to the user service manager through
        # "systemctl --user".
        # Note: the audio processes should be executed as the user pi.
        SystemTools.SetUpPiEnv(self._pi_uid)

        # Use pulseaudio as the default audio server for now.
        # Use pipewire as default later when it proves to be stable for all tests.
        self._audio_config = {
            self.AUDIO_SERVER: self.PULSEAUDIO,
            self.A2DP_CODEC: self.SBC,
        }

        # A hfp bluez source device looks like:
        #   5 bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway \
        #           module-bluez5-device.c  s16le 1ch 8000Hz RUNNING
        self._hfp_source_pattern = re.compile(
            r"(\d+)\s+bluez_source.*headset_audio_gateway"
        )

        # A target bluez_source HFP device looks like:
        #   1 bluez_sink.34_13_E8_DB_47_5E.headset_audio_gateway
        #           module-bluez5-device.c  s16le 1ch 16000Hz
        self._hfp_sink_pattern = re.compile(
            r"(\d+)\s+bluez_sink.*headset_audio_gateway"
        )

        # An a2dp source device looks like
        #   1 bluez_source.DC_71_96_68_E0_9C.a2dp_source module-bluez5-device.c \
        #           s16le 2ch 44100Hz
        self._a2dp_source_pattern = re.compile(
            r"(\d+)\s+bluez_source.*a2dp_source"
        )

        self._start_pulseaudio_cmd = "%s --start" % SystemTools.GetToolPath(
            self.PULSEAUDIO
        )

    def _MakeAudioRecordDirectory(self, audio_record_dir):
        """Create a new directory for audio recording.

        Args:
          audio_record_dir: the folder path to be created.

        """
        if not os.path.exists(audio_record_dir):
            os.makedirs(audio_record_dir)

            # Let all users have the right to r,w,x.
            # This is required for a pi user to write into this directory.
            os.chmod(audio_record_dir, 0o777)

    def ConnectToRemoteAddress(self, remote_address):
        """Connect to a remote device with a specified address.

        Args:
          remote_address: the address of the remote device to connect

        Returns:
          True if it could connect to the remote address successfully.
        """
        remote_device = self.GetDeviceWithAddress(remote_address)
        if not remote_device:
            return False

        try:
            remote_device.Connect()

        except Exception as e:
            logging.error(
                "Failed to connect to {}: {}".format(remote_address, e)
            )
            return False

        return True

    def GetAdvertisedName(self):
        """Get the name advertised by the kit.

        Returns:
          The name that the kit advertises to other Bluetooth devices.
        """
        return PERIPHERAL_DEVICE_NAME[PeripheralKit.BLUETOOTH_AUDIO]

    def GetDeviceType(self):
        """Get the peer device type

        Returns:
          The type of device emulated
        """
        return PeripheralKit.BLUETOOTH_AUDIO

    def GetClassOfDevice(self):
        """Get the class of device

        Returns:
          Class of device that is emulated by this peripheral
        """
        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.BLUETOOTH_AUDIO]
            & CLASS_OF_DEVICE_MASK
        )

    def GetClassOfService(self):
        """Get the class of service

        Returns:
          Class of service that is emulated by this peripheral
        """
        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.BLUETOOTH_AUDIO]
            & CLASS_OF_SERVICE_MASK
        )

    def GetCapabilities(self):
        """Get the capabilities of the emulated device.

        Returns:
          A dictionary from the parent plus the additional capabilities
          provided by the emulated audio device.
        """
        caps = super().GetCapabilities()
        # An example pipewire version looks like
        #   /usr/bin/pipewire
        #   Compiled with libpipewire 0.3.70
        #   Linked with libpipewire 0.3.70
        ver = SystemTools.OutputAsPi(
            self.PIPEWIRE, "--version", use_local_version=False
        )
        if ver:
            for line in ver.splitlines():
                elements = line.split()
                if "libpipewire" in elements:
                    # The capability keys are all upper case.
                    caps[self.PIPEWIRE.upper()] = elements[-1]
                    break
        logging.info("%s capabilities: %s", self.GetAdvertisedName(), caps)
        return caps

    def _PollForCondition(
        self, condition, timeout=10, sleep_interval=1, desc=None
    ):
        try:
            ret = common.PollForCondition(
                condition=condition,
                timeout=timeout,
                sleep_interval=sleep_interval,
                desc=desc,
            )
        except common.TimeoutError as e:
            ret = ""
            logging.warn(
                "Failed to run the command in %d seconds: %s.", timeout, e
            )
        return ret

    def _KillPulseAudio(self):
        """Send a SIGKILL to all pulseaudio process."""
        SystemTools.OrigCall("killall", "-9", self.PULSEAUDIO)
        logging.info("SIGKILL was sent to %s.", self.PULSEAUDIO)

    def _UsingLocalVersion(self, audio_profile):
        """Is it preferaable to use a local version of the executable?

        Use /usr/local/bin/pulseaudio for the 'hfp_wbs' and 'hfp_nbs' profiles
            - This version was made with a vendor patch to enable WBS.
              It suffers from stability issues. The pulseaudio process
              may crash at various functions.

        Use /usr/bin/pulseaudio for the 'a2dp' profile
            - This version was installed through "sudo apt install pulseaudio"
              which is a stable version from upstream.

        Args:
          audio_profile: the audio profile being tested

        Returns:
          True if a local version is preferred.
        """
        return False if audio_profile == "a2dp" else True

    def _StartPulseaudio(self, use_local_version):
        """Start Pulseaudio process or restart it if running.

        The pulseaudio command line options applied here are mostly based on trial
        and error. '--daemonize' will free pulseaudio from tightening to the
        subprocess thread (i.e. a opened terminal window in a subprocess). From
        local test experiments with bluetooth_AdapterAUSanity.au_avrcp_command_test
        daemonize the pulseaudio will slightly improve the test pass rate.
        '--disallow-exit' and '--exit-idle-time=-1' will prevent the pulseaudio
        exit by the user or due to idle timeout. In audio test that does not play
        an audio these option make sure the pulseaudio stay alive the whole test.
        '--scache-idle-time=-1' disallow auto offload samples, which always happen
        before pulseaudio exit itself.

        TODO(michaelfsun/josephsih): running pulseaudio related test with more/less
        command line options to make a data driven decision on how to start
        pulseaudio b/153289327.

        Args:
          use_local_version: True to use a local version of executable

        Returns:
          True if it starts successfully.
        """
        self._KillPulseAudio()

        try:
            self._pulseaudio = SystemTools.RunInSubprocessAsPi(
                self.PULSEAUDIO,
                "--start --daemonize --disallow-exit"
                " --exit-idle-time=-1 --scache-idle-time=-1 --log-level=debug",
                use_local_version,
            )
        except Exception as e:
            logging.error("Failed to start %s: %s.", self.PULSEAUDIO, e)
            return False

        logging.info("%s is started.", self.PULSEAUDIO)
        return True

    def StartPulseaudio(self, audio_profile):
        """Start pulseaudio process.

        Retry a few times as sometimes it may not start correctly.

        Args:
          audio_profile: the audio profile being tested

        Returns:
          True if it starts successfully.
        """
        for i in range(self.START_PULSEAUDIO_TIMES):
            logging.info("try to start pulseaudio ... %d", i)
            if self._StartPulseaudio(self._UsingLocalVersion(audio_profile)):
                time.sleep(self.WAIT_PULSEAUDIO_READY_SECS)
                output = self._PollForCondition(
                    lambda: self.ListSources(audio_profile),
                    desc="pulseaudio fully started",
                )
                logging.info("ListSources: %s", output)
                if bool(output):
                    return True
            time.sleep(self.INTERVAL_BETWEEN_START_PULSEAUDIO_SECS)
        return False

    def GetUserIdOfPi(self):
        """Get the user ID for the user pi.

        Returns:
          the pi's user id
        """
        return SystemTools.Output("id", "-u", "pi").strip()

    def _GetPipewireStatusOuput(self):
        """Get the pipewire status output.

        If pipewire is not fully started yet, the output would be
        > Could not connect to PipeWire

        Otherwise, the output would look something like below.
        Note that the bluez node would not appear initially if
        there is no bluetooth connection yet.

        Audio
         ├─ Devices:
         │      52. Built-in Audio                      [alsa]
         │      53. Built-in Audio                      [alsa]
         │      54. Built-in Audio                      [alsa]

        Returns:
          the output of wpctl status
        """
        return SystemTools.OutputAsPi(
            self.WPCTL, "status", use_local_version=False
        )

    def _GetPipewireBluezId(self):
        """Get the bluez device id assigned in pipewire.

        In the following example output, '68' will be returned for bluez.

        Audio
         ├─ Devices:
         │      52. Built-in Audio                      [alsa]
         │      53. Built-in Audio                      [alsa]
         │      54. Built-in Audio                      [alsa]
         │      68. 18-26-49-ED-36-94                   [bluez5]

        Returns:
          the bluez id if available; None otherwise
        """
        output = self._GetPipewireStatusOuput()
        if not bool(output):
            return None

        lines = output.split("\n")
        for line in lines:
            if "bluez5" in line:
                logging.info("wpctl status for bluez audio device: %s", line)
                bluez_id = int(line.split()[1].split(".")[0])
                return bluez_id
        return None

    def GetPipewireBluezId(self):
        """Get the pipewire bluez id.

        Use `wpctl status` to get the id of the bluez audio device.

        Returns:
          the audio device id if available; None otherwise
        """
        if not self._pi_uid:
            logging.error("The user ID of pi is not available.")
            return None

        bluez_id = self._PollForCondition(
            lambda: self._GetPipewireBluezId(),
            desc="pipewire audio profile connected",
        )
        bluez_id = bluez_id if bool(bluez_id) else None
        logging.info("GetPipewireBluezId: %s", bluez_id)
        return bluez_id

    def _StartPipewire(self):
        """Start Pipewire processes.

        Returns:
          True if they start successfully.
        """
        # Stop pipewire in case it is still running.
        self.StopPipewire()

        logging.info("trying to start pipewire")

        # Start the processes sequentially as pi.
        result_flag = self.SystemctlProcessCommand(
            "pi", "start", self.PIPEWIRE_PROCESSES_TO_START
        )

        if result_flag:
            logging.info(
                "% are started: %s",
                str(self.PIPEWIRE_PROCESSES_TO_STOP),
                result_flag,
            )
        return result_flag

    def StartPipewire(self):
        """Start the pipewire processes.

        Retry a few times as sometimes they may not start correctly.

        Returns:
          True if they start successfully.
        """
        for i in range(self.START_PIPEWIRE_TIMES):
            if not self._StartPipewire():
                time.sleep(self.INTERVAL_BETWEEN_START_PIPEWIRE_SECS)
                continue

            if bool(
                self._PollForCondition(
                    self._GetPipewireStatusOuput,
                    timeout=self.PIPEWIRE_READY_TIMEOUT_SECS,
                    desc="pipewire fully started",
                )
            ):
                return True
        return False

    def GetAudioServerName(self):
        """Get the audio server.

        Returns:
          the audio server name
        """
        return self._audio_config.get(self.AUDIO_SERVER)

    def StartAudioServer(self, audio_profile):
        """Start the audio server.

        There are multiple audio servers including pulseaudio and pipewire.
        Start the specified audio server after stopping the other non-used one.

        Args:
          audio_profile: the audio profile being tested which determines
                which version of the audio server to start.

        Returns:
          True if it starts successfully.
        """
        audio_server = self.GetAudioServerName()
        logging.info("audio server: %s", audio_server)
        if audio_server == self.PULSEAUDIO:
            self.StopPipewire()
            return self.StartPulseaudio(audio_profile)
        else:
            self.StopPulseaudio()
            return self.StartPipewire()

    def SetAudioConfig(self, audio_config):
        """Set the audio configuration.

        Args:
          audio_config: an audio configuration dict
        """
        self._audio_config.update(audio_config)

    def _PrintProcessStderr(self, proc):
        """Print the stderr of the proc if any."""
        if proc:
            _, stderr_data = proc.communicate()
            if bool(stderr_data):
                logging.error("[%s]: %s", proc.name, stderr_data)

    def StopPulseaudio(self):
        """Stop Pulseaudio process.

        In addition to terminating the pulseaudio process started by chameleond, it
        is required to kill the pulseaudio processes that may start as root.

        Returns:
          True if it stops successfully.
        """
        if self._pulseaudio:
            self._pulseaudio.terminate()
        else:
            # Kill any unexpected residual pulseaudio process below.
            msg = "%s may have been launched unexpectedly. Kill it anyway."
            logging.warn(msg, self.PULSEAUDIO)

        self._KillPulseAudio()
        self._PrintProcessStderr(self._pulseaudio)
        self._pulseaudio = None
        logging.info("%s has been stopped", self.PULSEAUDIO)
        return True

    def _IsActive(self, unit, user):
        """Is a systemctl unit active?

        A unit is active if the return code is 0.

        Args:
          user: the user can be 'pi' or 'root'

        Returns: True if the unit is active
        """
        args_str = f"--user is-active {unit}"
        if user == "pi":
            rc = SystemTools.OrigCallAsPi(self.SYSTEMCTL, args_str)
        else:
            rc = SystemTools.OrigCall(self.SYSTEMCTL, *args_str.split())

        logging.info(f"({user}) systemctl {args_str}: {rc}")
        return rc == 0

    def SystemctlProcessCommand(self, user, command, processes):
        result_flag = True

        for proc in processes:
            args_str = f"--user {command} {proc}"
            if user == "pi":
                rc = SystemTools.OrigCallAsPi(self.SYSTEMCTL, args_str)
            else:
                rc = SystemTools.OrigCall(self.SYSTEMCTL, *args_str.split())

            if rc < 0:
                logging.error("failed to {args_str}: {rc}.")
                result_flag = False

            if command == "stop":
                if not self._PollForCondition(
                    lambda: not self._IsActive(proc, user),
                    desc=f"{proc} is not active",
                ):
                    result_flag = False
            else:  # command == 'start'
                if not self._PollForCondition(
                    lambda: self._IsActive(proc, user), desc=f"{proc} is active"
                ):
                    result_flag = False

        return result_flag

    def StopPipewire(self):
        """Stop the Pipewire processes.

        Terminate the pipewire processes.

        Note that we must stop the pipewire.socket before stopping pipewire.
        Otherwise, pipewire may still be started by pipewire.socket.

        A traditional `killall` method does not work as the processes may be
        restarted automatically.

        Returns: True if they stop successfully.
        """
        logging.info("trying to stop pipewire")

        result_flag = True
        # Stop the processes that have been started as root.
        if not self.SystemctlProcessCommand(
            "root", "stop", self.PIPEWIRE_PROCESSES_TO_STOP
        ):
            result_flag = False

        # Stop the processes that have been started as pi.
        if not self.SystemctlProcessCommand(
            "pi", "stop", self.PIPEWIRE_PROCESSES_TO_STOP
        ):
            result_flag = False

        if result_flag:
            logging.info(
                "% are stopped: %s",
                str(self.PIPEWIRE_PROCESSES_TO_STOP),
                result_flag,
            )
        return result_flag

    def StopAudioServer(self):
        """Stop the audio server."""
        server_name = self.GetAudioServerName()
        if server_name == self.PULSEAUDIO:
            return self.StopPulseaudio()
        elif server_name == self.PIPEWIRE:
            return self.StopPipewire()
        else:
            raise BluetoothAudioException(f"Unknown audio server {server_name}")

    def StartOfono(self):
        """Start/restart Ofono process.

        Returns:
          True if it starts successfully.
        """
        self.StopOfono()

        try:
            SystemTools.Call("service", self.OFONO, "start")
            logging.info("%s is started.", self.OFONO)
            return True
        except Exception as e:
            logging.error("Failed to start %s: %s.", self.OFONO, e)
            return False

    def StopOfono(self):
        """Stop Ofono process.

        Returns:
          True if it stops successfully.
        """
        stop_cmd_args = ["service", self.OFONO, "stop"]
        if SystemTools.OrigCall(*stop_cmd_args) == 0:
            logging.info("%s is stopped.", self.OFONO)
            return True
        else:
            logging.warn("Failed to stop %s. Ignored.", self.ofono)
            return False

    def PlayAudio(self, audio_file):
        """Play the audio file.

        Args:
          audio_file: the audio file to play

        Returns:
          True if successful.
        """
        try:
            SystemTools.Call("aplay", audio_file)
            logging.info("Finished playing audio file %s", audio_file)
        except Exception as e:
            logging.error("Failed to play %s: %s.", audio_file, e)
            return False
        return True

    def StartPlayingAudioSubprocess(
        self, audio_profile, test_data, wait_secs=1
    ):
        """Start playing the audio file in a subprocess.

        Args:
          audio_profile: the audio profile, either a2dp, hfp_wbs, or hfp_nbs.
          test_data: a dictionary about the audio test data transmitted by the test
                     server.
          wait_secs: the time interval to wait for ofono to complete starting.

        Returns:
          True if successful.
        """
        if self._play:
            logging.error(
                "Trying to start audio playing process when it is still running."
            )
            return False

        device_number = self._PollForCondition(
            lambda: self.GetBluezSinkHFPDevice(audio_profile),
            desc="GetBluezSinkHFPDevice",
        )
        if device_number is None:
            logging.error(
                "Failed to get the device number of bluez_sink for HFP"
            )
            return False

        self._profile = test_data
        file_path = test_data["device_file"]

        sample_format = test_data["format"].lower().replace("_", "")

        args = (
            "--playback --device={d} --file-format=wav --format={s} --rate={r} "
        )
        args += "--channels={c} {fp}"
        args = args.format(
            d=device_number,
            s=sample_format,
            r=test_data["rate"],
            c=test_data["channels"],
            fp=file_path,
        )

        self._play = SystemTools.RunInSubprocessAsPi(
            "pacat", args, self._UsingLocalVersion(audio_profile)
        )
        # The process needs some time to start.
        time.sleep(wait_secs)
        return True

    def StopPlayingAudioSubprocess(self):
        """Stop playing the audio file in the subprocess.

        Returns:
          True if successful.
        """
        if self._play is None:
            logging.error("Stop playing audio before starting it.")
            return False

        self._play.terminate()
        self._PrintProcessStderr(self._play)
        self._play = None
        return True

    def ListCards(self, audio_profile):
        """List all sound cards.

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the list of sounds cards
        """
        return SystemTools.OutputAsPi(
            "pactl", "list cards short", self._UsingLocalVersion(audio_profile)
        )

    def ListSources(self, audio_profile):
        """List all audio sources cards.

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the list of audio sources
        """
        return SystemTools.OutputAsPi(
            "pactl",
            "list sources short",
            self._UsingLocalVersion(audio_profile),
        )

    def ListSinks(self, audio_profile):
        """List all audio sinks.

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the list of audio sinks
        """
        return SystemTools.OutputAsPi(
            "pactl", "list sinks short", self._UsingLocalVersion(audio_profile)
        )

    def GetBluezSourceDevice(self, audio_profile):
        """Get the number of the bluez_source device.

        A target bluez_source device looks like:
        1       bluez_source.34_13_E8_DB_47_5E.a2dp_source
        module-bluez5-device.c  s16le 2ch 48000Hz       SUSPENDED'
        18      bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway
        module-bluez5-device.c  s16le 1ch 8000Hz        RUNNING

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the first bluez source if found; None otherwise
        """
        sources = self.ListSources(audio_profile)
        for line in sources.splitlines():
            if "bluez_source" in line:
                return line.split()[0]
        return None

    def GetBluezSourceHFPDevice(self, audio_profile):
        """Get the number of the bluez_source device.

        A target bluez_source HFP device looks like:
        5      bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway
        module-bluez5-device.c  s16le 1ch 8000Hz        RUNNING

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the device number of the first hfp bluez source if found; None otherwise
        """
        sources = self.ListSources(audio_profile)
        for line in sources.splitlines():
            logging.info("sources: %s", line)
            result = self._hfp_source_pattern.search(line)
            if result is not None:
                hfp_id = result.group(1)
                logging.info("hfp source id: %s", hfp_id)
                return hfp_id
        return None

    def GetBluezSinkHFPDevice(self, audio_profile):
        """Get the number of the bluez_sink device.

        A target bluez_source HFP device looks like:
        1       bluez_sink.34_13_E8_DB_47_5E.headset_audio_gateway
        module-bluez5-device.c  s16le 1ch 16000Hz

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the device number of the first hfp bluez sink if found; None otherwise
        """
        sinks = self.ListSinks(audio_profile)
        for line in sinks.splitlines():
            logging.info("sinks: %s", line)
            result = self._hfp_sink_pattern.search(line)
            if result is not None:
                hfp_id = result.group(1)
                logging.info("hfp sink id: %s", hfp_id)
                return hfp_id
        return None

    def GetBluezSourceA2DPDevice(self, audio_profile):
        """Get the number of the bluez_source device.

        A target bluez_source A2DP device looks like:
        1       bluez_source.34_13_E8_DB_47_5E.a2dp_source
        module-bluez5-device.c  s16le 2ch 48000Hz       SUSPENDED'

        Args:
          audio_profile: the audio profile being tested

        Returns:
          the device number of the first a2dp bluez source if found; None otherwise
        """
        sources = self.ListSources(audio_profile)
        for line in sources.splitlines():
            logging.info("sources: %s", line)
            result = self._a2dp_source_pattern.search(line)
            if result is not None:
                a2dp_id = result.group(1)
                logging.info("a2dp source id: %s", a2dp_id)
                return a2dp_id
        return None

    def StartRecordingAudioSubprocessPulseaudio(
        self, audio_profile, test_data, recording_entity="recorded_by_peer"
    ):
        """Start recording audio in a subprocess.

        Args:
          audio_profile: the audio profile used to get the recording settings
          test_data: the details of the file being recorded
          recording_entity: which entity will record the audio, defined in
                            bluetooth_audio_test_data.py

        Returns:
          True if successful
        """
        if self._record:
            logging.error(
                "Trying to start audio recording process when it is still running."
            )
            return False

        device_number = self._PollForCondition(
            lambda: self.GetBluezSourceDevice(audio_profile),
            desc="GetBluezSourceDevice",
        )

        if device_number is None:
            logging.error("Failed to get the device number of bluez_source")
            return False

        self._profile = test_data
        sample_format = test_data["format"].lower().replace("_", "")
        file_path = test_data[recording_entity]

        self._MakeAudioRecordDirectory(os.path.split(file_path)[0])

        if audio_profile.startswith("a2dp"):
            # default is .raw (not .wav)
            file_format = ""
        else:
            file_format = "--file-format=wav"

        args = "--record --device={d} --format={s} --rate={r} --channels={c} "
        args += "--raw {ff} {fp}"
        args = args.format(
            d=device_number,
            s=sample_format,
            r=test_data["rate"],
            c=test_data["channels"],
            ff=file_format,
            fp=file_path,
        )

        self._record = SystemTools.RunInSubprocessAsPi(
            "pacat", args, self._UsingLocalVersion(audio_profile)
        )

        # Polling until the pacat process fully launches.
        # Otherwise, we may hit the error:
        #   FileNotFoundError: [Errno 2] No such file or directory:
        #                      '/tmp/audio/a2dp_recorded_by_peer.raw'
        self._PollForCondition(
            lambda: os.path.isfile(file_path), desc=f"{file_path} created"
        )
        self._recorded_file = open(file_path, "rb")
        return True

    def StartRecordingAudioSubprocessPipewire(
        self, audio_profile, test_data, recording_entity="recorded_by_peer"
    ):
        """Start recording audio in a subprocess.

        The output of `wpctl status` looks like below. The target bluez_id is 69
        in this example.
        ...
        Audio
         ├─ Devices:
         │      52. Built-in Audio                      [alsa]
         │      63. Built-in Audio                      [alsa]
         │      67. Built-in Audio                      [alsa]
         │      69. Chromebook_AD2C                     [bluez5]
        ...


        Args:
          audio_profile: the audio profile used to get the recording settings
          test_data: the details of the file being recorded
          recording_entity: which entity will record the audio, defined in
                            bluetooth_audio_test_data.py

        Returns:
          True if successful
        """
        self._profile = test_data
        file_path = test_data[recording_entity]
        self._MakeAudioRecordDirectory(os.path.split(file_path)[0])

        bluez_id = self.GetPipewireBluezId()
        if bluez_id is None:
            return False

        args = (
            f"--target {bluez_id} "
            f"--rate {test_data['rate']} "
            f"--channels {test_data['channels']} "
            f"--channel-map stereo {file_path}"
        )

        self._record = SystemTools.RunInSubprocessAsPi(
            "pw-record", args, self._UsingLocalVersion(audio_profile)
        )

        # Polling until the pw-record process fully launches.
        # Otherwise, we may hit the error:
        #   FileNotFoundError: [Errno 2] No such file or directory:
        #                      '/tmp/audio/a2dp_recorded_by_peer.raw'
        self._PollForCondition(
            lambda: os.path.isfile(file_path), desc=f"{file_path} created"
        )
        self._recorded_file = open(file_path, "rb")
        return True

    def StartRecordingAudioSubprocess(
        self, audio_profile, test_data, recording_entity="recorded_by_peer"
    ):
        """Start recording audio in a subprocess.

        Start the selected audio server subprocess based on the audio server name.

        Args:
          audio_profile: the audio profile used to get the recording settings
          test_data: the details of the file being recorded
          recording_entity: which entity will record the audio, defined in
                            bluetooth_audio_test_data.py

        Returns:
          True if successful
        """
        server_name = self.GetAudioServerName()
        if server_name == self.PULSEAUDIO:
            return self.StartRecordingAudioSubprocessPulseaudio(
                audio_profile, test_data, recording_entity
            )

        elif server_name == self.PIPEWIRE:
            return self.StartRecordingAudioSubprocessPipewire(
                audio_profile, test_data, recording_entity
            )

        else:
            raise BluetoothAudioException(f"Unknown audio server {server_name}")

    def _WriteOneChunk(self):
        """Write one chunk of data to the chunk file.

        Read audio data from the recorded file and save it to the chunk file.
        Note that this method reads as much data as possible and writes it out.
        The remaining data would be handled in next iteration by _PollForCondition.

        Returns:
          True if it is completed.
        """
        if self._remaining_size <= 0:
            return True

        buf = self._recorded_file.read(self._remaining_size)
        self._chunk_file.write(buf)
        self._remaining_size -= len(buf)
        logging.debug("remaining size %d", self._remaining_size)
        return self._remaining_size <= 0

    def HandleOneChunk(self, chunk_in_secs, index, dut_ip):
        """Save one chunk of data into a file and remote copy it to the DUT.

        Args:
          chunk_in_secs: the duration of the chunk to save in seconds.
          index: the i-th chunk in the whole recorded audio streams.
          dut_ip: the DUT IP address to copy the chunk file to.

        Returns:
          the chunk filename if successful; None otherwise.
        """

        profile = self._profile
        nframes = profile["rate"] * profile["channels"] * chunk_in_secs
        chunk_filename = profile["chunk_file"] % index

        # Each frame takes 16 bits, or 2 bytes.
        buf_size = nframes * 2
        self._remaining_size = buf_size
        logging.debug("start writing %d bytes to %s", buf_size, chunk_filename)
        with open(chunk_filename, "wb") as self._chunk_file:
            try:
                self._PollForCondition(
                    self._WriteOneChunk,
                    sleep_interval=0.2,
                    desc="write chunk %d" % index,
                )
            except common.TimeoutError as e:
                logging.error("writting to %s: %s", chunk_filename, e)
                return None

        self.ScpToDut(chunk_filename, chunk_filename, dut_ip)
        return chunk_filename

    def StopRecordingingAudioSubprocess(self):
        """Stop the recording subprocess.

        Returns:
          True if successful
        """
        logging.info("Audio recording is being terminated.")

        if self._record is None:
            logging.error("Stop audio recording before starting it.")
            return False

        if self._record.poll() is None:
            logging.info(
                "Audio recording is not finished yet, terminating it now."
            )
            self._record.terminate()

        logging.info("Printing process error.")
        self._PrintProcessStderr(self._record)
        logging.info("Audio recording is terminated.")
        self._record = None

        self._recorded_file.close()
        self._recorded_file = None

        return True

    def ScpToDut(self, src_file, dst_file, dut_ip):
        """Scp the src_file to the dst_file at dut_ip.

        Args:
          src_file: the source file
          dst_file: the destination file at the dut
          dut_ip: the ip address of the dut

        Returns:
          True if successful
        """
        args = (
            "%s %s root@%s:%s" % (self.SSH_OPTIONS, src_file, dut_ip, dst_file)
        ).split()
        SystemTools.Call("scp", *args)

    def ExportMediaPlayer(self):
        """Export the Bluetooth media player.

        Start the mpris-proxy process to export the active media player to the
        system. Always terminate previous processes and start a new one.

        When mpris-proxy starting, it will try to auto-launch a dbus session.
        Auto-launch a dbus session means trying to connect to an existing dbus
        session if the environment variable DBUS_SESSION_BUS_ADDRESS is set or
        create a new session otherwise. To prevent playerctl to start a new dbus
        session, check and fill the DBUS_SESSION_BUS_ADDRESS variable before
        calling the mpris-proxy.

        Returns:
          Return True if one and only one mpris-proxy is running
        """
        SystemTools.OrigCall("killall", "-9", self.MPRISPROXY)

        if self.DBUS_SESSION_ENV_VAR_NAME not in os.environ:
            os.environ[
                self.DBUS_SESSION_ENV_VAR_NAME
            ] = self.DBUS_SESSION_ENV_VAR_VALUE

        return bool(SystemTools.RunInSubprocess(self.MPRISPROXY))

    def UnexportMediaPlayer(self):
        """Stop all mpris-proxy processes."""
        SystemTools.OrigCall("killall", "-9", self.MPRISPROXY)
        self._media_player = None

    def GetExportedMediaPlayer(self):
        """Get the exported media player's name with playerctl.

        Function include a check of environmental variable
        DBUS_SESSION_BUS_ADDRESS as same as ExportMediaPlayer() to prevent
        playerctl start a new dbus session before try to connect to an existing
        session.

        Returns:
          Return player name if only one player found, empty string otherwise.
        """
        if self.DBUS_SESSION_ENV_VAR_NAME not in os.environ:
            os.environ[
                self.DBUS_SESSION_ENV_VAR_NAME
            ] = self.DBUS_SESSION_ENV_VAR_VALUE

        output = SystemTools.Output(self.PLAYERCTL, "--list-all")
        if len(output.splitlines()) != 1 or output == self.NO_PLAYER_FOUND:
            return ""

        self._media_player = output.strip()
        return self._media_player

    def _PlayerCommandOutput(self, *args):
        """Execute command towards the given player, and return its output.

        Args:
          *args: playerctl args to be executed.

        Returns:
          Requested media information on success, empty string otherwise.
        """
        if self._media_player is None:
            logging.error("No Bluetooth media player was exported.")
            return ""

        return SystemTools.Output(
            self.PLAYERCTL, "-p", self._media_player, *args
        ).strip()

    def SendMediaPlayerCommand(self, command):
        """Execute command towards the given player.

        Args:
          command: playerctl command to be executed.

        Returns:
          Return True if success, False otherwise.
        """
        if self._media_player is None:
            logging.error("No Bluetooth media player was exported.")
            return False

        return (
            SystemTools.OrigCall(
                self.PLAYERCTL, "-p", self._media_player, command
            )
            == 0
        )

    def GetMediaPlayerMediaInfo(self):
        """Retrieve media information through playerctl calls.

        Returns:
          A dictionary of all supported media information
        """
        media_info = dict()

        media_info["status"] = self._PlayerCommandOutput("status")
        media_info["position"] = self._PlayerCommandOutput("position")
        media_info["volume"] = self._PlayerCommandOutput("volume")
        media_info["title"] = self._PlayerCommandOutput("metadata", "title")
        media_info["album"] = self._PlayerCommandOutput("metadata", "album")
        media_info["artist"] = self._PlayerCommandOutput("metadata", "artist")
        media_info["length"] = self._PlayerCommandOutput(
            "metadata", "mpris:length"
        )

        return media_info

    def GetKitInfo(self):
        """A simple demo of getting Bluetooth audio device information."""
        print("advertised name:", self.GetAdvertisedName())
        print("local bluetooth address:", self.GetLocalBluetoothAddress())
        print("device type:", self.GetDeviceType())
        print("Class of service:", hex(self.GetClassOfService()))
        print("Class of device:", hex(self.GetClassOfDevice()))


if __name__ == "__main__":
    device = BluetoothAudio()
    device.GetKitInfo()

    # Deleting the object is required to enforce BluezPeripheral.__del__()
    # to terminate the mainloop.
    del device
