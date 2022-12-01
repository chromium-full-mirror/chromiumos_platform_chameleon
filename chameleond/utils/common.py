# -*- coding: utf-8 -*-
# Copyright 2014 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Common utilities."""

from __future__ import print_function

import logging
import time


class TimeoutError(Exception):
  """Exception raised on timeout."""
  pass


def WaitForCondition(func, value, delay, timeout):
  """Waits for the given function matches the given value.

  Args:
    func: The function to be tested.
    value: The value to fit the condition.
    delay: The time of delay for each try.
    timeout: The timeout in second to break the check.

  Raises:
    TimeoutError on timeout.
  """
  end_time = start_time = time.time()
  while end_time - start_time < timeout:
    if func() == value:
      break
    logging.debug('Waiting for condition %s == %s', func.__name__, str(value))
    time.sleep(delay)
    end_time = time.time()
  else:
    message = ('Timeout on waiting for condition %s == %s' %
               (func.__name__, str(value)))
    logging.warn(message)
    raise TimeoutError(message)


def PollForCondition(condition, exception=None, timeout=10, sleep_interval=0.1,
                     desc=None):
  """Polls until a condition becomes truthy and returns the condition's output.

  This function polls until bool(condition) becomes True.

  This function is different from the WaitForCondition function above primarily
  for two things:
  - This function allows any output returned from the condition function that
    is evaluated to be true. This is useful when the output is not known in
    advance.
  - This function returns the output of the condition.

  Minor differences also include
  - This function allows for a customized timeout description.
  - This function allows for a customized exception.

  Args:
    condition: function taking no args and returning anything that will
               evaluate to True in a conditional check
    exception: exception to throw if condition doesn't evaluate to true
    timeout: maximum number of seconds to wait
    sleep_interval: time to sleep between polls
    desc: description of default TimeoutError used if 'exception' is None

  Returns:
    The evaluated value that caused the poll loop to terminate.

  Raises:
    Raise 'exception' arg if supplied; TimeoutError otherwise
  """
  start_time = time.time()
  while True:
    value = condition()
    if bool(value):
      return value

    if time.time() + sleep_interval - start_time <= timeout:
      time.sleep(sleep_interval)
      continue

    # Raise an exception due to timeout.
    if exception:
      logging.error('Raise error %r due to unexpected value: %r',
                    exception, str(value))
      raise exception # pylint: disable=raising-bad-type

    if desc is None:
      desc = condition.__name__
    msg = 'Timed out waiting for ' + desc
    logging.error(msg)
    raise TimeoutError(msg)


def lazy(original_class):
  """lazy instantiation of the original_class.

  The original_class would be instantiated when any method or
  data member is accessed at the first time.

  Usage:
    Assume that the orignal instantiation is as follows:

      o = original_class(*args, **kwargs)

    To use lazy instantiation, it would be something like

      o = lazy(original_class)(*args, **kwargs)

  Note:
  - The following assignment statement would not instantiate the object.

    oo = o

  - However, the following statement would instantiate the object.

    print(o)

    since it invokes o.__str__()

  Args:
    original_class: the original class to be instantiated in the lazy way.
  """

  class LazyInstantiation(object):
    """The lazy wrapper class."""

    def __init__(self, *args, **kargs):
      self._args = args
      self._kargs = kargs
      self._class = original_class
      self._obj = None
      self._loaded = False

    def _load(self):
      self._obj = self._class(*self._args, **self._kargs)
      self._loaded = True

    def __getattr__(self, name):
      if not self._loaded:
        logging.info('Load %s to access %s.', self._class.__name__, name)
        self._load()
      return getattr(self._obj, name)

  return LazyInstantiation
