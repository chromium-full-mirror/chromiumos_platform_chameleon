# -*- coding: utf-8 -*-
# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module provides an abstraction of bluetooth audio device."""

import logging
import os
import re
import subprocess
import time

import chameleon_common  # pylint: disable=W0611

import common
from bluetooth_raspi import BluezPeripheral
from bluetooth_raspi import BluezPeripheralException
from chameleond.utils.system_tools import SystemTools
from chameleond.utils.bluetooth_peripheral_kit import PeripheralKit
from chameleond.utils.bluez_service_consts import (
    CLASS_OF_DEVICE_MASK, CLASS_OF_SERVICE_MASK,
    PERIPHERAL_DEVICE_CLASS, PERIPHERAL_DEVICE_NAME)


# The audio test data for various profiles.
audio_record_dir = '/tmp'
audio_test_data = {
  # hfp nbs test data
  'hfp_nbs': {
    'format': 's16le',
    'rate': 8000,
    'channels': 1,
    'recorded_file': os.path.join(audio_record_dir,
                                  'hfp_nbs_recorded_by_chameleon.wav'),
  },

  # hfp wbs test data
  'hfp_wbs': {
    'format': 's16le',
    'rate': 16000,
    'channels': 1,
    'recorded_file': os.path.join(audio_record_dir,
                                  'hfp_wbs_recorded_by_chameleon.wav'),
  },

  # a2dp est data
  'a2dp': {
    'format': 's16le',
    'rate': 48000,
    'channels': 2,
    'recorded_file': os.path.join(audio_record_dir,
                                  'a2dp_recorded_by_chameleon.wav'),
  },
}


class BluetoothAudioException(BluezPeripheralException):
  """A dummy exception class for BluetoothAudio class."""
  pass


class BluetoothAudio(BluezPeripheral):
  """An object that performs Bluetooth audio device related operations."""

  PULSEAUDIO = 'pulseaudio'
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

    # A hfp bluez source device looks like:
    #   5 bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway \
    #           module-bluez5-device.c  s16le 1ch 8000Hz RUNNING
    self._hfp_source_pattern = re.compile(
        r'(\d+)\s+bluez_source.*headset_audio_gateway')

    # An a2dp source device looks like
    #   1 bluez_source.DC_71_96_68_E0_9C.a2dp_source module-bluez5-device.c \
    #           s16le 2ch 44100Hz
    self._a2dp_source_pattern = re.compile(
        r'(\d+)\s+bluez_source.*a2dp_source')

    self._start_pulseaudio_cmd = ('%s --start' %
                                  SystemTools.GetToolPath(self.PULSEAUDIO))

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

  def _StartPulseaudio(self):
    """Start Pulseaudio process or restart it if runnning."""
    try:
      SystemTools.Call('killall', self.PULSEAUDIO)
    except Exception as e:
      logging.debug('%s may not be running: %s. Ignored.', self.PULSEAUDIO, e)

    try:
      self._pulseaudio = SystemTools.RunInSubprocessAsPi(
          self.PULSEAUDIO, '--start')
    except Exception as e:
      logging.error('Failed to start %s: %s.', self.PULSEAUDIO, e)
      return False

    logging.info('%s is started.', self.PULSEAUDIO)
    return True

  def StartPulseaudio(self):
    for i in range(self.START_PULSEAUDIO_TIMES):
      logging.info('try to start pulseaudio ... %d', i)
      if self._StartPulseaudio():
        time.sleep(self.WAIT_PULSEAUDIO_READY_SECS)
        output = self.ListSources()
        logging.info('ListSources: %s', output)
        if bool(output):
          return True
      time.sleep(self.INTERVAL_BETWEEN_START_PULSEAUDIO_SECS)
    return False

  def StopPulseaudio(self):
    """Stop Pulseaudio process."""
    if self._pulseaudio is None:
      logging.error('Stop %s before starting it.', self.PULSEAUDIO)
      return False

    self._pulseaudio.terminate()
    logging.info('%s is terminated.', self.PULSEAUDIO)
    self._pulseaudio = None
    return True

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

  def StartPlayingAudioSubprocess(self, audio_file):
    """Start playing the audio file in a subprocess.

    Args:
      audio_file: the audio file to play

    Returns:
      True if successful.
    """
    try:
      self._play = SystemTools.RunInSubprocess('aplay', audio_file)
    except Exception as e:
      logging.error('Failed to start playing audio %s: %s.', audio_file, e)
      return False
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

  def ListCards(self):
    """List all sound cards.

    Returns:
      the list of sounds cards
    """
    return SystemTools.OutputAsPi('pactl', 'list cards short')

  def ListSources(self):
    """List all audio sources cards.

    Returns:
      the list of audio sources
    """
    return SystemTools.OutputAsPi('pactl', 'list sources short')

  def ListSinks(self):
    """List all audio sinks.

    Returns:
      the list of audio sinks
    """
    return SystemTools.OutputAsPi('pactl', 'list sinks short')

  def GetBluezSourceDevice(self):
    """Get the number of the bluez_source device.

    A target bluez_source device looks like:
    1       bluez_source.34_13_E8_DB_47_5E.a2dp_source
    module-bluez5-device.c  s16le 2ch 48000Hz       SUSPENDED'
    18      bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway
    module-bluez5-device.c  s16le 1ch 8000Hz        RUNNING

    Returns:
      the first bluez source if found; None otherwise
    """
    sources = self.ListSources()
    for line in sources.splitlines():
      if 'bluez_source' in line:
        return line.split()[0]
    return None

  def GetBluezSourceHFPDevice(self):
    """Get the number of the bluez_source device.

    A target bluez_source HFP device looks like:
    5      bluez_source.DC_71_96_68_E0_9C.headset_audio_gateway
    module-bluez5-device.c  s16le 1ch 8000Hz        RUNNING

    Returns:
      the device number of the first hfp bluez source if found; None otherwise
    """
    sources = self.ListSources()
    for line in sources.splitlines():
      logging.info('sources: %s', line)
      result = self._hfp_source_pattern.search(line)
      if result is not None:
        hfp_id = result.group(1)
        logging.info('hfp source id: %s', hfp_id)
        return hfp_id
    return None

  def GetBluezSourceA2DPDevice(self):
    """Get the number of the bluez_source device.

    A target bluez_source A2DP device looks like:
    1       bluez_source.34_13_E8_DB_47_5E.a2dp_source
    module-bluez5-device.c  s16le 2ch 48000Hz       SUSPENDED'

    Returns:
      the device number of the first a2dp bluez source if found; None otherwise
    """
    sources = self.ListSources()
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

    device_number = self.GetBluezSourceDevice()
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
    self._record = SystemTools.RunInSubprocessAsPi('pacat', args)
    # The process needs some time to start.
    time.sleep(1)
    return True

  def StopRecordingingAudioSubprocess(self):
    """Stop the recording subprocess.

    Returns:
      True if successful
    """
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

  def GetKitInfo(self, connect_separately=False, test_reset=False):
    """A simple demo of getting Bluetooth audio device information.

    Args:
      connect_separately: whether to create a serial device
      test_reset: whether a factory reset is required
    """
    print 'advertised name:', self.GetAdvertisedName()
    print 'local bluetooth address:', self.GetLocalBluetoothAddress()
    print 'device type:', self.GetDeviceType()
    print 'Class of service:', hex(self.GetClassOfService())
    print 'Class of device:', hex(self.GetClassOfDevice())


if __name__ == '__main__':
  device = BluetoothAudio()
  device.GetKitInfo()

  # Deleting the object is required to enforce BluezPeripheral.__del__()
  # to terminate the mainloop.
  del device
