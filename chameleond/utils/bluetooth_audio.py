# -*- coding: utf-8 -*-
# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module provides an abstraction of bluetooth audio device."""

from __future__ import print_function

# TODO: to port chromite.lib.cros_logging to replace legacy logging
import logging  # pylint: disable=cros-logging-import
import os
import re
import time

from . import chameleon_common  # pylint: disable=W0611

from . import common
from .bluetooth_raspi import BluezPeripheral
from .bluetooth_raspi import BluezPeripheralException
from chameleond.utils.system_tools import SystemTools
from chameleond.utils.bluetooth_peripheral_kit import PeripheralKit
from chameleond.utils.bluez_service_consts import (
    CLASS_OF_DEVICE_MASK, CLASS_OF_SERVICE_MASK,
    PERIPHERAL_DEVICE_CLASS, PERIPHERAL_DEVICE_NAME)


# The audio test data for various profiles.
audio_test_dir = os.path.join(os.path.dirname(__file__), 'data/audio')
audio_record_dir = '/tmp'
audio_test_data = {
    # hfp nbs test data
    'hfp_nbs': {
        'format': 's16le',
        'rate': 8000,
        'channels': 1,
        'file': os.path.join(audio_test_dir,
                             'sine_3500hz_rate8000_ch1_5secs.wav'),
        'recorded_file': os.path.join(audio_record_dir,
                                      'hfp_nbs_recorded_by_peer.wav'),
    },

    # hfp wbs test data
    'hfp_wbs': {
        'format': 's16le',
        'rate': 16000,
        'channels': 1,
        'file': os.path.join(audio_test_dir,
                             'sine_7000hz_rate16000_ch1_5secs.wav'),
        'recorded_file': os.path.join(audio_record_dir,
                                      'hfp_wbs_recorded_by_peer.wav'),
    },

    # a2dp est data
    'a2dp': {
        'format': 's16le',
        'rate': 48000,
        'channels': 2,
        'recorded_file': os.path.join(audio_record_dir,
                                      'a2dp_recorded_by_peer.wav'),
    },
}


class BluetoothAudioException(BluezPeripheralException):
  """A dummy exception class for BluetoothAudio class."""
  pass


class BluetoothAudio(BluezPeripheral):
  """An object that performs Bluetooth audio device related operations."""

  PULSEAUDIO = 'pulseaudio'
  OFONO = 'ofono'
  MPRISPROXY = 'mpris-proxy'
  PLAYERCTL = 'playerctl'
  NO_PLAYER_FOUND = 'No players were found\n'
  DBUS_SESSION_ENV_VAR_NAME = 'DBUS_SESSION_BUS_ADDRESS'
  DBUS_SESSION_ENV_VAR_VALUE = 'unix:path=/run/user/0/bus'
  SSH_OPTIONS = (' -i /root/.ssh/testing_rsa '
                 '-o UserKnownHostsFile=/dev/null '
                 '-o StrictHostKeyChecking=no ')
  START_PULSEAUDIO_TIMES = 5
  INTERVAL_BETWEEN_START_PULSEAUDIO_SECS = 0.2
  WAIT_PULSEAUDIO_READY_SECS = 1

  def __init__(self):
    """Initializes a Bluetooth audio object."""
    BluezPeripheral.__init__(self)
    self._record = None
    self._pulseaudio = None
    self._play = None
    self._profile = None
    self._media_player = None

    # A hfp bluez source device looks like:
    #   5 bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway \
    #           module-bluez5-device.c  s16le 1ch 8000Hz RUNNING
    self._hfp_source_pattern = re.compile(
        r'(\d+)\s+bluez_source.*headset_audio_gateway')

    # A target bluez_source HFP device looks like:
    #   1 bluez_sink.34_13_E8_DB_47_5E.headset_audio_gateway
    #           module-bluez5-device.c  s16le 1ch 16000Hz
    self._hfp_sink_pattern = re.compile(
        r'(\d+)\s+bluez_sink.*headset_audio_gateway')

    # An a2dp source device looks like
    #   1 bluez_source.DC_71_96_68_E0_9C.a2dp_source module-bluez5-device.c \
    #           s16le 2ch 44100Hz
    self._a2dp_source_pattern = re.compile(
        r'(\d+)\s+bluez_source.*a2dp_source')

    self._start_pulseaudio_cmd = ('%s --start' %
                                  SystemTools.GetToolPath(self.PULSEAUDIO))

  def ConnectToRemoteAddress(self, remote_address):
    """Connect to a remote device with a specified address.

    Args:
      remote_address: the address of the remote device to connect

    Returns:
      True if it could connect to the remote address successfully.
    """
    remote_device = self.GetDeviceWithAddress(remote_address)
    if remote_device and remote_device.Connect():
      return True
    return False

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
    return (PERIPHERAL_DEVICE_CLASS[PeripheralKit.BLUETOOTH_AUDIO] &
            CLASS_OF_DEVICE_MASK)

  def GetClassOfService(self):
    """Get the class of service

    Returns:
      Class of service that is emulated by this peripheral
    """
    return (PERIPHERAL_DEVICE_CLASS[PeripheralKit.BLUETOOTH_AUDIO] &
            CLASS_OF_SERVICE_MASK)

  def _KillPulseAudio(self):
    """Send a SIGKILL to all pulseaudio process."""
    SystemTools.OrigCall('killall', '-9', self.PULSEAUDIO)
    logging.info('SIGKILL was sent to %s.', self.PULSEAUDIO)

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
    return False if audio_profile == 'a2dp' else True

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
          self.PULSEAUDIO, '--start --daemonize --disallow-exit'
          ' --exit-idle-time=-1 --scache-idle-time=-1 --log-level=debug',
          use_local_version)
    except Exception as e:
      logging.error('Failed to start %s: %s.', self.PULSEAUDIO, e)
      return False

    logging.info('%s is started.', self.PULSEAUDIO)
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
      logging.info('try to start pulseaudio ... %d', i)
      if self._StartPulseaudio(self._UsingLocalVersion(audio_profile)):
        time.sleep(self.WAIT_PULSEAUDIO_READY_SECS)
        output = self.ListSources(audio_profile)
        logging.info('ListSources: %s', output)
        if bool(output):
          return True
      time.sleep(self.INTERVAL_BETWEEN_START_PULSEAUDIO_SECS)
    return False

  def StopPulseaudio(self):
    """Stop Pulseaudio process.

    In addition to terminating the pulseaudio process started by chameleond, it
    is required to kill the pulseaudio processes that may start as root.

    Returns:
      True if it stops successfully.
    """
    if self._pulseaudio is None:
      logging.error('Stop %s before starting it.', self.PULSEAUDIO)
      return False

    self._pulseaudio.terminate()
    self._KillPulseAudio()
    self._pulseaudio = None
    return True

  def StartOfono(self):
    """Start/restart Ofono process.

    Returns:
      True if it starts successfully.
    """
    self.StopOfono()

    try:
      SystemTools.Call('service', self.OFONO, 'start')
      logging.info('%s is started.', self.OFONO)
      return True
    except Exception as e:
      logging.error('Failed to start %s: %s.', self.OFONO, e)
      return False

  def StopOfono(self):
    """Stop Ofono process.

    Returns:
      True if it stops successfully.
    """
    stop_cmd_args = ['service', self.OFONO, 'stop']
    if SystemTools.OrigCall(*stop_cmd_args) == 0:
      logging.info('%s is stopped.', self.OFONO)
      return True
    else:
      logging.warn('Failed to stop %s. Ignored.', self.ofono)
      return False

  def PlayAudio(self, audio_file):
    """Play the audio file.

    Args:
      audio_file: the audio file to play

    Returns:
      True if successful.
    """
    try:
      SystemTools.Call('aplay', audio_file)
      logging.info('Finished playing audio file %s', audio_file)
    except Exception as e:
      logging.error('Failed to play %s: %s.', audio_file, e)
      return False
    return True

  def StartPlayingAudioSubprocess(self, audio_profile, wait_secs=1):
    """Start playing the audio file in a subprocess.

    Args:
      audio_profile: the audio file to play
      wait_secs: the time interval to wait for ofono to complete starting.

    Returns:
      True if successful.
    """
    if self._play:
      logging.error(
          'Trying to start audio playing process when it is still running.')
      return False

    device_number = self.GetBluezSinkHFPDevice(audio_profile)
    if device_number is None:
      logging.error('Failed to get the device number of bluez_sink for HFP')
      return False

    self._profile = profile = audio_test_data.get(audio_profile)
    if profile is None:
      logging.error('%s is not a supported audio profile', audio_profile)
      return False

    args = (('--playback --device=%s --format=%s --rate=%d --channels=%d %s') %
            (device_number, profile['format'], profile['rate'],
             profile['channels'], profile['file']))
    self._play = SystemTools.RunInSubprocessAsPi(
        'pacat', args, self._UsingLocalVersion(audio_profile))
    # The process needs some time to start.
    time.sleep(wait_secs)
    return True


  def StopPlayingAudioSubprocess(self):
    """Stop playing the audio file in the subprocess.

    Returns:
      True if successful.
    """
    if self._play is None:
      logging.error('Stop playing audio before starting it.')
      return False

    self._play.terminate()
    self._play = None
    return True

  def ListCards(self, audio_profile):
    """List all sound cards.

    Args:
      audio_profile: the audio profile being tested

    Returns:
      the list of sounds cards
    """
    return SystemTools.OutputAsPi('pactl', 'list cards short',
                                  self._UsingLocalVersion(audio_profile))

  def ListSources(self, audio_profile):
    """List all audio sources cards.

    Args:
      audio_profile: the audio profile being tested

    Returns:
      the list of audio sources
    """
    return SystemTools.OutputAsPi('pactl', 'list sources short',
                                  self._UsingLocalVersion(audio_profile))

  def ListSinks(self, audio_profile):
    """List all audio sinks.

    Args:
      audio_profile: the audio profile being tested

    Returns:
      the list of audio sinks
    """
    return SystemTools.OutputAsPi('pactl', 'list sinks short',
                                  self._UsingLocalVersion(audio_profile))

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
      if 'bluez_source' in line:
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
      logging.info('sources: %s', line)
      result = self._hfp_source_pattern.search(line)
      if result is not None:
        hfp_id = result.group(1)
        logging.info('hfp source id: %s', hfp_id)
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
      logging.info('sinks: %s', line)
      result = self._hfp_sink_pattern.search(line)
      if result is not None:
        hfp_id = result.group(1)
        logging.info('hfp sink id: %s', hfp_id)
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
      logging.info('sources: %s', line)
      result = self._a2dp_source_pattern.search(line)
      if result is not None:
        a2dp_id = result.group(1)
        logging.info('a2dp source id: %s', a2dp_id)
        return a2dp_id
    return None

  def StartRecordingAudioSubprocess(self, audio_profile):
    """Start recording audio in a subprocess.

    Args:
      audio_profile: the audio profile used to get the recording settings

    Returns:
      True if successful
    """
    if self._record:
      logging.error(
          'Trying to start audio recording process when it is still running.')
      return False

    device_number = self.GetBluezSourceDevice(audio_profile)
    if device_number is None:
      logging.error('Failed to get the device number of bluez_source')
      return False

    self._profile = profile = audio_test_data.get(audio_profile)
    if profile is None:
      logging.error('%s is not a supported audio profile', audio_profile)
      return False

    args = (('--record --device=%s --format=%s --rate=%d --channels=%d '
             '--raw --file-format=wav %s') %
            (device_number, profile['format'], profile['rate'],
             profile['channels'], profile['recorded_file']))
    self._record = SystemTools.RunInSubprocessAsPi(
        'pacat', args, self._UsingLocalVersion(audio_profile))
    # The process needs some time to start.
    time.sleep(1)
    return True

  def StopRecordingingAudioSubprocess(self):
    """Stop the recording subprocess.

    Returns:
      True if successful
    """
    logging.info('Audio recording is being terminated.')

    if self._record is None:
      logging.error('Stop audio recording before starting it.')
      return False

    if self._record.poll() is None:
      self._record.terminate()
      logging.info('Audio recording is terminated.')
    self._record = None
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
    args = ('%s %s root@%s:%s' %
            (self.SSH_OPTIONS, src_file, dut_ip, dst_file)).split()
    SystemTools.Call('scp', *args)


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
    SystemTools.OrigCall('killall', '-9', self.MPRISPROXY)

    if not os.environ.has_key(self.DBUS_SESSION_ENV_VAR_NAME):
      os.environ[self.DBUS_SESSION_ENV_VAR_NAME] = (
          self.DBUS_SESSION_ENV_VAR_VALUE)

    return bool(SystemTools.RunInSubprocess(self.MPRISPROXY))


  def UnexportMediaPlayer(self):
    """Stop all mpris-proxy processes."""
    SystemTools.OrigCall('killall', '-9', self.MPRISPROXY)
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
    if not os.environ.has_key(self.DBUS_SESSION_ENV_VAR_NAME):
      os.environ[self.DBUS_SESSION_ENV_VAR_NAME] = (
          self.DBUS_SESSION_ENV_VAR_VALUE)

    output = SystemTools.Output(self.PLAYERCTL, '--list-all')
    if len(output.splitlines()) != 1 or output == self.NO_PLAYER_FOUND:
      return ''

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
      logging.error('No Bluetooth media player was exported.')
      return ''

    return SystemTools.Output(
        self.PLAYERCTL, '-p', self._media_player, *args).strip()


  def SendMediaPlayerCommand(self, command):
    """Execute command towards the given player.

    Args:
      command: playerctl command to be executed.

    Returns:
      Return True if success, False otherwise.
    """
    if self._media_player is None:
      logging.error('No Bluetooth media player was exported.')
      return False

    return SystemTools.OrigCall(self.PLAYERCTL, '-p', self._media_player,
                                command) == 0


  def GetMediaPlayerMediaInfo(self):
    """Retrieve media information through playerctl calls.

    Returns:
      A dictionary of all supported media information
    """
    media_info = dict()

    media_info['status'] = self._PlayerCommandOutput('status')
    media_info['position'] = self._PlayerCommandOutput('position')
    media_info['volume'] = self._PlayerCommandOutput('volume')
    media_info['title'] = self._PlayerCommandOutput('metadata', 'title')
    media_info['album'] = self._PlayerCommandOutput('metadata', 'album')
    media_info['artist'] = self._PlayerCommandOutput('metadata', 'artist')
    media_info['length'] = self._PlayerCommandOutput('metadata',
                                                     'mpris:length')

    return media_info


  def GetKitInfo(self):
    """A simple demo of getting Bluetooth audio device information."""
    print('advertised name:', self.GetAdvertisedName())
    print('local bluetooth address:', self.GetLocalBluetoothAddress())
    print('device type:', self.GetDeviceType())
    print('Class of service:', hex(self.GetClassOfService()))
    print('Class of device:', hex(self.GetClassOfDevice()))


if __name__ == '__main__':
  device = BluetoothAudio()
  device.GetKitInfo()

  # Deleting the object is required to enforce BluezPeripheral.__del__()
  # to terminate the mainloop.
  del device
