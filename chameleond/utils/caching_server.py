# Copyright 2016 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Caching server, providing access to the cached thumbnail images."""

import logging
import multiprocessing
import os
import time

import http.server
import socketserver


# Directory for storing the cached images.
CACHED_DIR = '/tmp/cached'


def ClearCachedDir():
  """Removes all files in the cached directory."""
  if os.path.exists(CACHED_DIR):
    for file_name in os.listdir(CACHED_DIR):
      file_path = os.path.join(CACHED_DIR, file_name)
      if os.path.isfile(file_path):
        os.unlink(file_path)
  else:
    os.makedirs(CACHED_DIR)


class RemoveFileOnceGetHandler(http.server.SimpleHTTPRequestHandler):
  """A HTTP request handler which removes the file once get."""

  def do_GET(self):
    """Responses the GET request."""
    http.server.SimpleHTTPRequestHandler.do_GET(self)
    os.remove(self.path[1:])


class CachingServer(multiprocessing.Process):
  """A caching server which starts in a new process"""

  def __init__(self, port):
    super(CachingServer, self).__init__()
    ClearCachedDir()
    os.chdir(CACHED_DIR)
    self.KillLingeringCachingServer(port)
    logging.info('Creating caching server on port %d...', port)
    self.httpd = socketserver.TCPServer(('', port), RemoveFileOnceGetHandler)

  def KillLingeringCachingServer(self, port):
    """
    lsof -i :9993
    COMMAND     PID USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME
    run_chame 22147 root   21u  IPv4 4316296      0t0  TCP *:9993 (LISTEN)
    """
    cmd = 'lsof -t -i :%d | xargs kill -9 2&>1 > /dev/null' % port
    logging.debug('killing command: %s', cmd)
    os.system(cmd)
    time.sleep(1)

  def run(self):
    try:
      logging.info('Caching server serves forever...')
      self.httpd.serve_forever()
    finally:
      logging.info('Close the caching server.')
      self.httpd.server_close()
