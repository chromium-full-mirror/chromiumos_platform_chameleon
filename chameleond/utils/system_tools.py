# -*- coding: utf-8 -*-
# Copyright (c) 2014 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""System tools required for Chameleond execution."""

from __future__ import print_function

# TODO: to port chromite.lib.cros_logging to replace legacy logging
import logging  # pylint: disable=cros-logging-import
import os
import subprocess
import sys
import threading


class _SystemTools(object):
  """A class to wrap the required tools for Chameleond execution."""

  _TOOL_PATHS = {
      'aplay': '/usr/bin/aplay',
      'arecord': '/usr/bin/arecord',
      'avsync': '/usr/bin/avsync',
      'chameleond': '/etc/init.d/chameleond',
      'date': '/bin/date',
      'dut-control': '/usr/local/lib/python-exec/python2.7/dut-control',
      'histogram': '/usr/bin/histogram',
      'hpd_control': '/usr/bin/hpd_control',
      'i2cdump': '/usr/local/sbin/i2cdump',
      'i2cget': '/usr/local/sbin/i2cget',
      'i2cset': '/usr/local/sbin/i2cset',
      'killall': '/usr//bin/killall',
      'logger': '/usr/bin/logger',
      'lsmod': '/sbin/lsmod',
      'lspci': 'lspci',
      'memtool': '/usr/bin/memtool',
      'modinfo': '/sbin/modinfo',
      'modprobe': '/sbin/modprobe',
      'reboot': '/sbin/reboot',
      'ofono': '/usr/sbin/ofonod',
      'pactl': '/usr/bin/pactl',
      'pactl.local': '/usr/local/bin/pactl',
      'pacat': '/usr/bin/pacat',
      'pacat.local': '/usr/local/bin/pacat',
      'pgrep': '/usr/bin/pgrep',
      'pixeldump': '/usr/bin/pixeldump',
      'printer': '/usr/bin/printer',
      'pulseaudio': '/usr/bin/pulseaudio',
      'pulseaudio.local': '/usr/local/bin/pulseaudio',
      'scp': '/usr/bin/scp',
      'service': '/usr/sbin/service',
      'servod': '/usr/local/lib/python-exec/python2.7/servod',
      'ssh': '/usr/bin/ssh',
      'su': '/bin/su',
      'wget': '/usr/bin/wget',
  }

  def __init__(self):
    """Constructs a _SystemTools object."""
    self._CheckRequiredTools()
    self._pi_args = 'su - pi -c'.split()
    self._GetPiEnv()

  def _GetPiEnv(self):
    """Get a proper environment for Pi.

    We need to set XDG_RUNTIME_DIR for pi for pulseaudio tools to run
    correctly. Setting environmental variable DBUS_SESSION_BUS_ADDRESS to force
    the pulseaudio to connect to an existing DBSU session before starting a new
    one.
    """
    self._pi_env = os.environ.copy()
    self._pi_env['XDG_RUNTIME_DIR'] = '/run/user/1000'
    self._pi_env['DBUS_SESSION_BUS_ADDRESS'] = '/run/user/1000/bus'

  def GetToolPath(self, name):
    """Get the path of the tool.

    Args:
      name: Name of the system tool.

    Returns:
      The path of the tool; or None if not found.
    """
    return self._TOOL_PATHS.get(name)

  def _CheckRequiredTools(self):
    """Checks all the required tools exist.

    Raises:
      SystemToolsError if missing a tool.
    """
    for path in list(self._TOOL_PATHS.values()):
      if not os.path.isfile(path):
        # It is okay that some tools may not exist in a particular platform.
        logging.warning('IOError: Required tool %s not existed', path)

  def _MakeCommand(self, name, args):
    """Combines the system tool and its parameters into a list.

    Args:
      name: Name of the system tool.
      args: List of arguments passed in by user.

    Returns:
      A list representing the complete command.
    """
    return [self._TOOL_PATHS[name]] + [str(arg) for arg in args]

  def OrigCall(self, name, *args):
    """Calls the tool with arguments using subprocess.call().

    Args:
      name: The name of the tool.
      *args: The arguments of the tool.
    """
    command = self._MakeCommand(name, args)
    return subprocess.call(command)

  def Call(self, name, *args):
    """Calls the tool with arguments using subprocess.check_call().

    Args:
      name: The name of the tool.
      *args: The arguments of the tool.
    """
    command = self._MakeCommand(name, args)
    subprocess.check_call(command)

  def Output(self, name, *args):
    """Calls the tool with arguments and returns its output.

    Args:
      name: The name of the tool.
      *args: The arguments of the tool.

    Returns:
      The output message of the call, including stderr message.
    """
    command = self._MakeCommand(name, args)
    try:
      output = subprocess.check_output(command, stderr=subprocess.STDOUT)
    except Exception as e:
      logging.error('Output error: %s', e)
      return ''
    if sys.version_info >= (3, 0):
      return output.decode()
    else:
      return output

  def _FindPreferredExecutablePath(self, name):
    """Find the preferred executable path.

    For some daemons, e.g., pulseaudio, there may exist a locally made
    version. In this situation, the executables will reside in
    /usr/local/bin instead of the original /usr/bin when they are installed.

    Returns:
      The preferred executable path if a locally made version exists;
      otherwise, the original installed path.
    """
    local_name = name + '.local'
    local_path = self._TOOL_PATHS.get(local_name)
    return (local_path if local_path is not None and os.path.isfile(local_path)
            else self._TOOL_PATHS[name])

  def OutputAsPi(self, name, args_str):
    """Calls the tool with arguments as Pi and returns its output.

    This is primarily used on Raspberry Pi as the chameleon host. This is
    needed as some commands, e.g., pactl and pacat in pulseaudio, require
    to run with pi as the user. The chameleond root user is not allowed to
    access pulseaudio for security concern.

    Args:
      name: The name of the tool.
      args_str: the args string (not a list)

    Returns:
      The output message of the call, including stderr message.
    """
    preferred_path = self._FindPreferredExecutablePath(name)
    args = self._pi_args + [preferred_path + ' ' + args_str]
    try:
      output = subprocess.check_output(args, env=self._pi_env).decode()
      return output
    except Exception as e:
      logging.error('Output error: %s', e)
      return ''

  def DelayedCall(self, time, name, *args):
    """Calls the tool with arguments after a given delay.

    The method returns first before the execution.

    Args:
      time: The time in second.
      name: The name of the tool.
      *args: The arguments of the tool.
    """
    threading.Timer(time, lambda: self.Call(name, *args)).start()

  def RunInSubprocess(self, name, *args):
    """Calls the tool and run it in a separate process.

    This tool will be useful for starting and later killing aplay and arecord
    processes which have to be interrupted. The command outputs are channelled
    to stdout and/or stderr.

    Args:
      name: The name of the tool.
      *args: The arguments of the tool.

    Returns:
      process: The subprocess spawned for the command.
    """
    return self.RunInSubprocessOutputToFile(name, subprocess.PIPE, *args)

  def RunInSubprocessAsPi(self, name, args_str):
    """Calls the tool and run it in a separate process as user Pi.

    This is primarily used on Raspberry Pi as the chameleon host. This is
    needed as some commands, e.g., pactl and pacat in pulseaudio, require
    to run with pi as the user. The chameleond root user is not allowed to
    access pulseaudio for security concern.

    Args:
      name: The name of the tool.
      args_str: the args string (not a list)

    Returns:
      process: The subprocess spawned for the command.
    """
    preferred_path = self._FindPreferredExecutablePath(name)
    args = self._pi_args + [preferred_path + ' ' + args_str]
    logging.info('args: %s', str(args))
    return subprocess.Popen(args, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)

  def RunInSubprocessOutputToFile(self, name, handle, *args):
    """Calls the tool and run it in a separate process, and outputs to a file.

    Args:
      name: The name of the tool.
      handle: The file handle to output stdout and stderr.
      *args: The arguments of the tool.

    Returns:
      process: The subprocess spawned for the command.
    """
    command = self._MakeCommand(name, args)
    process = subprocess.Popen(command,
                               stdout=handle,
                               stderr=handle)
    return process

  def GetSubprocessOutput(self, process, decode=True):
    """Returns the output of the command called in the process spawned.

    Args:
      process: The subprocess in which a command is called.
      decode: If true, decode output from byte strings to strings.

    Returns:
      A tuple (return_code, out, err).
      return_code: 0 on success, 1 on error.
      out: Content of command output to stdout, usually when command succeeds.
      err: Content of command output to stderr when an error occurs.
    """
    out, err = process.communicate()
    return_code = process.returncode
    if decode:
      return (return_code, out.decode(), err.decode())
    return (return_code, out, err.decode())

# Singleton
SystemTools = _SystemTools()
