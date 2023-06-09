# -*- coding: utf-8 -*-
# Copyright 2021 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Chameleond Driver for Chameleon v3 hardware."""

from dataclasses import dataclass
import functools
import itertools
import inspect
import logging
import numpy
import pathlib
import pprint
import pw_hdlc.rpc
import pw_protobuf_compiler
import pw_rpc.callback_client.errors
import re
import serial
import subprocess
import tempfile
import threading
import time
import xmlrpc.client

from interface import ChameleondInterface

EC_PROTO_PATH = (pathlib.Path(__file__)/"../../../v3/ec/proto/v3.proto").resolve()
EC_PROTO = pw_protobuf_compiler.python_protos.Library.from_paths([EC_PROTO_PATH]).modules_by_package[""][0]

class ChameleondError(Exception):
  pass

class PwExceptionWrap:
  """
  Pigweed RPC uses the go style error handling which is not very pythonic.
  Without this wrapper, one would have to check the status (first of the
  returned tuple) at the callsite of every rpc call.
  This wrapper handles that automatically.
  """
  def __init__(self, client, service_name):
    self.service = client.rpcs()[service_name]

  def __getattr__(self, name):
    original_attr = getattr(self.service, name)
    if not hasattr(original_attr, "method"):
      # Probably some non-rpc attr, like `__repr__()`. Return it unchanged.
      return original_attr

    # therefore typeof(original_attr) == pw_rpc.callback_client.impl. .....
    original_rpc_method = original_attr
    method_type = original_rpc_method.method

    @functools.wraps(original_rpc_method)
    def exception_wrapper(*args, **kwargs):
      status, payload = original_rpc_method(*args, **kwargs)
      if status.ok():
        return payload
      if status == pw_rpc.callback_client.errors.Status.UNIMPLEMENTED:
        raise NotImplementedError(method_type)
      raise pw_rpc.callback_client.errors.RpcError(original_rpc_method, status)
    return exception_wrapper

def _check_output(args, encoding="utf-8", **kwargs):
  out = subprocess.check_output(args, encoding=encoding, **kwargs)
  if encoding is None:
    # do not touch it since it's probably binary image data from v4l2-ctl
    return out
  else:
    # let's crop the whitespace since it's a text output we want to parse
    return out.strip()

@dataclass
class V4L:
  path: str
  pixelformat: str = "RX24"

  def __post_init__(self):
    # make sure we support self.pixelformat
    list_formats_ext = _check_output([
      "v4l2-ctl",
      "--device", self.path,
      "--list-formats-ext",
    ])
    assert f"'{self.pixelformat}'" in list_formats_ext
    self.fmt_video = f"pixelformat={self.pixelformat}"

  INFO_RE = re.compile("Width/Height\s*: (?P<width>\d+)/(?P<height>\d+).*Size Image\s*: (?P<size>\d+)", re.DOTALL)
  @classmethod
  def parse_frame_info(cls, info):
    if not (match := cls.INFO_RE.search(info)):
      raise ChameleondError(f"INFO_RE can't parse:", info)

    frame_info_dict = match.groupdict()
    for field in ("width", "height", "size"):
      frame_info_dict[field] = int(frame_info_dict[field])

    return frame_info_dict

  def get_frame_size(self):
    info = _check_output([
      "v4l2-ctl",
      "--device", self.path,
      "--set-fmt-video", self.fmt_video,
      "--all",
    ])
    return self.parse_frame_info(info)

  def get_frame(self, count=1, timeout=5):
    buf = tempfile.NamedTemporaryFile(prefix="chameleond_", suffix=".fb")
    info = _check_output([
        "v4l2-ctl",
        "--device", self.path,
        "--set-fmt-video", self.fmt_video,
        "--stream-mmap",
        "--stream-count", str(count),
        "--stream-to", buf.name,
        "--all",
      ],
      timeout=timeout,
    )
    return buf, self.parse_frame_info(info)

  def __repr__(self):
    return f"{self.__class__.__name__}({self.path!r})"

class ChameleondDriver(ChameleondInterface):
  frame_buffer: list
  # The frame index which is used for the regular DumpPixels API.
  _DEFAULT_FRAME_INDEX = 0
  _DEFAULT_FRAME_LIMIT = 1

  edid_database: dict # {edid_id: edid_bytes}

  NETWORK_INTERFACE = "end0"

  EC_SERIAL_PORT = "/dev/ttyS0"

  @dataclass
  class Port:
    name: str
    video_dev: V4L = None
    audio_dev: object = None

    def __post_init__(self):
      self.is_ite = self.name.startswith("ITE_")
      self.external_name = self.name.removeprefix("ITE_")
      if self.name[-1].isdigit():
        self.port_num = int(self.name[-1])
      self.connector_type = self.external_name.removesuffix(str(self.port_num))

      self.has_video = self.video_dev is not None
      self.has_audio = self.audio_dev is not None

      if self.is_ite:
        self.ite_port = getattr(EC_PROTO.it68051_port_num, f"PORT{self.port_num}")
      dest_enum = EC_PROTO.videomux_set_request.videomux_dest
      self.videomux_direction = dest_enum.RX if self.is_ite else dest_enum.FPGA

      self.edid = None

  chameleon_parallel_framebuffer = V4L("/dev/video0")
  PORTS = [
    #Port("DP1",        video_dev=V4L("/dev/video1")),
    #Port("DP2",        video_dev=V4L("/dev/video2")),
    #Port("HDMI1",      video_dev=V4L("/dev/video3")),
    #Port("HDMI2",      video_dev=V4L("/dev/video4")),
    Port("ITE_DP1",    video_dev=chameleon_parallel_framebuffer),
    Port("ITE_DP2",    video_dev=chameleon_parallel_framebuffer),
    Port("ITE_HDMI1",  video_dev=chameleon_parallel_framebuffer),
    Port("ITE_HDMI2",  video_dev=chameleon_parallel_framebuffer),
    #PORT("LINE_IN",   audio_dev=), # SSM2603
    #PORT("AUDIO_OUT", audio_dev=), # SSM2603
    #PORT("MIC",       audio_dev=), # SSM2603
  ]

  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)

    self.frame_buffer = []
    self.edid_database = {}

    self.ec_serial = serial.Serial(self.EC_SERIAL_PORT, 115200, timeout=0.01)
    callback_client_impl = pw_hdlc.rpc.callback_client.Impl(
        default_unary_timeout_s=1.0,
        default_stream_timeout_s=1.0,
    )
    self.ec_client = pw_hdlc.rpc.HdlcRpcClient(
      read = lambda: self.ec_serial.read(4096),
      paths_or_modules = [EC_PROTO],
      channels = pw_hdlc.rpc.default_channels(self.ec_serial.write),
      client_impl = callback_client_impl,
    )

    self.board_service = PwExceptionWrap(self.ec_client, "board_service")
    self.videomux_service = PwExceptionWrap(self.ec_client, "videomux_service")
    self.it68051_service = PwExceptionWrap(self.ec_client, "it68051_service")

    logging.info("Versions:\n" +
                  pprint.pformat(self.GetVersions(), sort_dicts=False))

  def GetVersions(self):
    """Get versions for various components of Chameleon.

    Intended mostly for logging during tests. Do not make conditional decisions
    based on the contents as the format might change and is not standardized.

    Here you might find stuff like chameleon hardware revision, kernel, fpga,
    chameleond versions and more.

    Returns:
      A dict, {"component_name": version, ...}
    """
    versions = {}

    versions["chameleon"] = "v3"

    try:
      versions["board"] = self.board_service.get_board_version().version
    except Exception as e:
      versions["board"] = repr(e)

    try:
      for field, value in self.board_service.get_code_version().ListFields():
        versions[field.name] = value
    except Exception as e:
      versions["ec_ver"] = repr(e)

    try:
      versions["uboot"] = _check_output(["pacman", "--query", "uboot-chameleonv3"])
    except Exception as e:
      versions["uboot"] = repr(e)

    try:
      versions["fpga"] = _check_output(["pacman", "--query", "fpga-bitstream"])
    except Exception as e:
      versions["fpga"] = repr(e)

    try:
      versions["linux"] = _check_output(["pacman", "--query", "linux"])
    except Exception as e:
      versions["linux"] = repr(e)

    try:
      versions["last_pacman_upgrade"] = _check_output(
        "cat /var/log/pacman.log | grep upgraded | tail -n 1",
        shell=True,
      )
    except Exception as e:
      versions["last_pacman_upgrade"] = repr(e)

    try:
      ansible_log = [line.strip()
                    for line in open("/var/log/alarm-ansible").readlines()]
      versions["ansible_first"] = ansible_log[0]
      versions["ansible_last"] = ansible_log[-1]
    except Exception as e:
      versions["ansible_first"] = repr(e)
      versions["ansible_last"] = repr(e)

    try:
      versions["chameleond"] = _check_output([
        "git",
        "-C", (pathlib.Path(__file__)/"..").resolve(),
        "describe",
        "--tags",
        "--long",
        "--dirty",
      ])
    except Exception as e:
      versions["chameleond"] = repr(e)

    return versions

  def Reset(self):
    """Resets Chameleon board."""
    # Let's reset the EC!
    rst_gpio = _check_output(["sudo", "gpiofind", "STM32_RST_L"])
    _check_output(f"sudo gpioset -D open-drain {rst_gpio}=0", shell=True)
    _check_output(f"sudo gpioset -D open-drain {rst_gpio}=1", shell=True)

    # Block until we can talk to it
    for attempt in range(5):
      try:
        self.board_service.get_board_version()
        break # yay!
      except pw_rpc.callback_client.errors.RpcTimeout as e:
        # The EC probably has not booted yet
        last_error = e
        continue # try again
    else:
      # if we got to the end of the loop and we haven't
      # called "break" sucessfully
      raise last_error

    # Clear EDIDs cached in chameleond
    for port in self.PORTS:
      if port.has_video:
        port.edid = None
    self.edid_database = {}

    self.frame_buffer.clear()

  def GetMacAddress(self):
    """Gets the MAC address of this Chameleon.

    Returns:
      A string for MAC address.
    """
    return open(f"/sys/class/net/{self.NETWORK_INTERFACE}/address").read().strip()

  def GetChameleondLogs(self, cursor="main"):
    """Gets logs generated by this daemon.

    The log will go as far back as when this method was called previously
    with the same cursor.

    Args:
      cursor: An arbitrary name used to "bookmark" the last call of
              this function.

    Returns:
      Logs as a big string.
    """

    cursor = re.sub("\W", "", cursor) # take out non word characters

    return _check_output([
      "journalctl",
      "--unit", "chameleond",
      "--output", "short-full", # includes timezone
      "--cursor-file", f"/tmp/{cursor}.chameleond_log_cursor",
    ])

  def GetDetectedStatus(self):
    """Returns detetcted status of all devices.

    User can use this API to know the capability of the chameleon board.

    Returns:
      A list of a tuple of detected devices' strings detected status.
      e.g. [('HDMI', True), ('MIC', False)]
    """
    return [(port.name, i in self.ProbePorts())
              for i, port in enumerate(self.PORTS)]

  def GetSupportedPorts(self):
    """Returns all supported ports on the board.

    Not like the ProbePorts() method which only returns the ports which
    are connected, this method returns all supported ports on the board.

    Returns:
      A tuple of port_id, for all supported ports on the board.
    """
    return tuple(range(len(self.PORTS)))

  def GetSupportedInputs(self):
    """Returns all supported input ports on the board.

    Not like the ProbeInputs() method which only returns the input ports which
    are connected, this method returns all supported input ports on the board.

    Returns:
      A tuple of port_id, for all supported input port on the board.
    """
    return self.GetSupportedPorts() # TODO(audio): All of them so far

  def GetSupportedOutputs(self):
    """Returns all supported output ports on the board.

    Not like the ProbeOutputs() method which only returns the output ports which
    are connected, this method returns all supported output ports on the board.

    Returns:
      A tuple of port_id, for all supported output port on the board.
    """
    return () # TODO(audio): None of them on v3 so far

  def GetConnectorType(self, port_id):
    """Returns the string for the connector type.

    Args:
      port_id: The ID of the input/output port.

    Returns:
      A string, like "HDMI", "DP", "MIC", etc.
      This value will be used later in tests, so it cannot be arbitrary.
    """
    return self.PORTS[port_id].connector_type

  def HasAudioSupport(self, port_id):
    """Returns true if the port has audio support.

    Args:
      port_id: The ID of the input/output port.

    Returns:
      True if the input/output port has audio support; otherwise, False.
    """
    return self.PORTS[port_id].has_audio

  def HasVideoSupport(self, port_id):
    """Returns true if the port has video support.

    Args:
      port_id: The ID of the input/output port.

    Returns:
      True if the input/output port has video support; otherwise, False.
    """
    return self.PORTS[port_id].has_video

  def CreateEdid(self, edid):
    """Creates an internal record of EDID using the given byte array.

    Args:
      edid: A byte array of EDID data, wrapped in a xmlrpclib.Binary object.

    Returns:
      An edid_id.
    """

    # Find a spot
    edid_id = 0
    while edid_id in self.edid_database:
      edid_id += 1

    self.edid_database[edid_id] = edid.data

    return edid_id

  def DestroyEdid(self, edid_id):
    """Destroys the internal record of EDID. The internal data will be freed.

    Args:
      edid_id: The ID of the EDID, which was created by CreateEdid().
    """
    del self.edid_database[edid_id]

  def ReadEdid(self, port_id):
    """Reads the EDID content of the selected video input on Chameleon.

    Args:
      port_id: The ID of the video input port.

    Returns:
      A byte array of EDID data, wrapped in a xmlrpclib.Binary object,
      or None if the EDID is disabled.
    """
    # We're going to return what chameleond set this last,
    # Don't bother reading it from real hardware since we're in the habit of
    # overwriting (via _send_cached_edid_to_hardware) whatever it is there
    # every time we .Plug()
    port = self.PORTS[port_id]
    return xmlrpc.client.Binary(port.edid)

  def ApplyEdid(self, port_id, edid_id):
    """Applies the EDID to the selected video input.

    Note that this method doesn't pulse the HPD line. Should call Plug(),
    Unplug(), or FireHpdPulse() later.

    Args:
      port_id: The ID of the video input port.
      edid_id: The ID of the EDID.
    """
    port = self.PORTS[port_id]
    logging.info(f"edid_database.keys()={list(self.edid_database.keys())}")
    assert port.has_video

    edid_bytes = self.edid_database[edid_id]

    # We need to potentially pad it so it's 256 bytes (b/219231626)
    edid_bytes = edid_bytes.ljust(256, b'\0')

    port.edid = edid_bytes
    if self.IsPlugged(port_id):
      self._send_cached_edid_to_hardware(port)
      if port.is_ite:
        logging.warning("Might be too late to send EDID to ITE chip after port's been plugged.")

  def _send_cached_edid_to_hardware(self, port):
    """Actually send EDID cached by python to the hardware.

    Code from ApplyEdid can't always override the edid in the hardware due to
    the ways muxes are configured. Eg: setting ITE_HDMI1 edid could override
    ITE_DP2 if done the naive way.

    So we defer the sending till the Plug event so we're muxed correctly first.

    Args:
      port: Port() instance
    """
    if port.edid is None:
      logging.warning(f"We're not sure what EDID to use for {port}, leaving what the hardware has (either default or previous).")
      return
    if port.is_ite:
      self.it68051_service.write_edid(raw_edid=port.edid)
    else:
      raise NotImplementedError("Need to tell the FPGA Logic")

  def IsPlugged(self, port_id):
    """Returns true if the port is emulated as plugged.

    Args:
      port_id: The ID of the input/output port.

    Returns:
      True if the port is emulated as plugged; otherwise, False.
    """
    port = self.PORTS[port_id]

    if port.has_video:
      # check videomux via the EC

      # let's check if videomux is routed the right way
      board_mux_conf = self.videomux_service.get()
      current_direction = getattr(board_mux_conf, port.external_name.lower())
      if current_direction != port.videomux_direction:
        return False

      if port.is_ite:
        # make sure ite is on the correct port
        if self.it68051_service.get_selected_port().port != port.ite_port:
          return False

        # make sure we're emitting hpd
        if self.it68051_service.get_hpd(port=port.ite_port).on_off == 0:
          return False

    # If nothing caught yet, it's probably connected
    return True

  def Plug(self, port_id):
    """Emulates plug, like asserting HPD line to high on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]

    if port.has_video:
      if port.is_ite:
        for other_port_id, other_port in enumerate(self.PORTS):
          if port is other_port:
            continue
          if self.IsPlugged(other_port_id):
            if other_port.is_ite:
              raise ChameleondError(f"Other {other_port} already connected to ITE path.")
            if port.external_name == other_port.external_name:
              raise ChameleondError(f"Other path {other_port} connected to the same external port.")

      # set routing via the EC
      self.videomux_service.set(
        **{port.external_name.lower(): port.videomux_direction}
      )
      if port.is_ite:
        self.it68051_service.select_port(port=port.ite_port)
      else:
        raise NotImplementedError("Need to tell the FPGA Logic")

      self._send_cached_edid_to_hardware(port)

      if port.is_ite:
        self.it68051_service.set_hpd(port=port.ite_port, on_off=1)
      else:
        raise NotImplementedError("Need to tell the FPGA Logic")

    # If we switch v4l frameworks, perhaps re-open the device here

  def Unplug(self, port_id):
    """Emulates unplug, like deasserting HPD line to low on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    if port.has_video:
      port.edid = None # forget the port's edid
      self.UnplugHPD(port_id)

  def UnplugHPD(self, port_id):
    """Only deassert HPD line to low on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    assert port.has_video
    if port.is_ite:
      self.it68051_service.set_hpd(port=port.ite_port, on_off=0)
    else:
      raise NotImplementedError("Need to tell the FPGA Logic")

  def FireHpdPulse(self, port_id,
                   deassert_interval_usec, assert_interval_usec=None,
                   repeat_count=1, end_level=0):
    """Fires one or more HPD pulse (low -> high -> low -> ...).

    Warning: expect >100,000us error for the intervals.

    Args:
      port_id: The ID of the video input port.
      deassert_interval_usec: The time in microsecond of the deassert pulse.
      assert_interval_usec: The time in microsecond of the assert pulse.
                            If None, then use the same value as
                            deassert_interval_usec.
      repeat_count: The count of HPD pulses to fire.
      end_level: HPD ends with 0 for LOW (unplugged) or 1 for HIGH (plugged).
    """
    if assert_interval_usec is None:
      assert_interval_usec = deassert_interval_usec

    for i in range(repeat_count):
      logging.info(f"HPD Pulse {i}")

      self.UnplugHPD(port_id)
      time.sleep(deassert_interval_usec / 1e6)

      self.Plug(port_id)
      time.sleep(assert_interval_usec / 1e6)

    if not end_level:
      self.UnplugHPD(port_id)

  def FireMixedHpdPulses(self, port_id, widths_msec):
    """Fires one or more HPD pulses, starting at low, of mixed widths.

    One must specify a list of segment widths in the widths_msec argument where
    widths_msec[0] is the width of the first low segment, widths_msec[1] is that
    of the first high segment, widths_msec[2] is that of the second low segment,
    etc.
    The HPD line stops at low if even number of segment widths are specified;
    otherwise, it stops at high.

    The method is equivalent to a series of calls to Unplug() and Plug()
    separated by specified pulse widths.

    Warning: expect >100ms error for the widths

    Args:
      port_id: The ID of the video input port.
      widths_msec: list of pulse segment widths in milli-seconds.
    """
    ops = itertools.cycle([self.UnplugHPD, self.Plug])

    for delay_msec, op in zip(widths_msec, ops):
      logging.info(f"Fire {op.__name__}, wait {delay_msec}msec.")
      op(port_id)
      time.sleep(delay_msec / 1000)

    # Append a plug/unplug after the last pulse
    op = next(ops)
    logging.info(f"Fire last {op.__name__}.")
    op(port_id)

  def ScheduleHpdToggle(self, port_id, delay_ms, end_level=1):
    """Performs a HPD pulse, but schedules the last edge after a delay.

    This returns control to the caller after the first edge and allows it to
    do other stuff. Example: if a chromebook DUT is the caller, it could go
    to sleep and this Scheduled Toggle like a wakeup alarm.

    Warning: expect >100ms error for the delay.

    Args:
      port_id: The ID of the video input port.
      delay_ms: Delay in milli-second for the pulse width.
      end_level: Whether the last toggle (after the delay) should be a
                 rising edge/Plug (=1) or a falling edge/Unplug (=0).
    """
    if hasattr(self, "_scheduled_hpd") and self._scheduled_hpd.is_alive():
      raise ChameleondError("There's another HPD scheduled.")

    ops = [self.UnplugHPD, self.Plug]
    first_edge = ops[int(not end_level)]
    last_edge = ops[int(end_level)]

    def toggle_last():
      last_edge(port_id)
      logging.info(f"just ran scheduled {last_edge.__name__} after {delay_ms}ms")
    self._scheduled_hpd = threading.Timer(delay_ms / 1000, toggle_last)
    first_edge(port_id)
    self._scheduled_hpd.start()

  def WaitVideoInputStable(self, port_id, timeout=None):
    """Waits the video input stable or timeout.

    Args:
      port_id: The ID of the video input port.
      timeout: The time period to wait for.

    Returns:
      True if the video input becomes stable within the timeout period;
      otherwise, False.
    """
    port = self.PORTS[port_id]
    assert port.has_video

    if timeout is not None:
      end_time = time.time() + timeout
    else:
      end_time = float("inf")
      logging.warning("This will block forever until there's an input, even further XMLRPC calls will block.")

    if port.is_ite:
      try:
        # poll the EC for the it68051 link status
        # but we don't want to spam the log with each poll
        logging.disable(logging.INFO)

        while time.time() < end_time:
          link_status = self.it68051_service.get_link_status()
          if link_status.active:
            break
          time.sleep(0.1)

        # we either timed out, or EC thinks we have a link
        if not link_status.active:
          logging.warning("WaitVideoInputStable timed out using the EC")
          return False
      finally:
        logging.disable(logging.NOTSET)

      logging.info(f"EC says VideoStable, what about V4L? {end_time - time.time():.2f} seconds left")

    # Make sure v4l can give us at least 1 good frame
    frame_size = 0
    try:
      while not frame_size:
        v4l_frame_timeout = None
        if end_time != float("inf"):
          v4l_frame_timeout = end_time - time.time()
        _buf, frame_info = port.video_dev.get_frame(timeout=v4l_frame_timeout)
        frame_size = frame_info["size"]
    except subprocess.TimeoutExpired:
      logging.warning("WaitVideoInputStable timed out at V4L")
      return False

    logging.info(f"Video is now stable! {end_time - time.time():.2f} seconds to spare")
    return True

  def IsPhysicalPlugged(self, port_id):
    """Returns true if the physical cable is plugged between DUT and Chameleon.

    Args:
      port_id: The ID of the input/output port.

    Returns:
      True if the physical cable is plugged; otherwise, False.
    """
    return port_id in self.ProbePorts()

  def ProbePorts(self):
    """Probes all the connected ports on Chameleon board.

    Returns:
      A tuple of port_id, for the ports connected to DUT.
    """
    return self.ProbeInputs() + self.ProbeOutputs()

  def ProbeOutputs(self):
    """Probes all the connected output ports on Chameleon board.

    Returns:
      A tuple of port_id, for the output ports connected to DUT.
    """
    return () # TODO(audio): None of v3 so far

  def ProbeInputs(self):
    """Probes all the connected input ports on Chameleon board.

    Returns:
      A tuple of port_id, for the input ports connected to DUT.
    """

    board_version = self.board_service.get_board_version().version

    source_presence = self.board_service.get_source_presence()

    port_ids = []
    for i, port in enumerate(self.PORTS):
      if port.has_video:
        connected = getattr(source_presence, port.external_name.lower())
        if port.connector_type == "HDMI" and board_version <= 2:
          # HACK(b/220139622): Temporarly lie, hw issue on proto2
          # otherwise autotest gets mad
          connected = False
      if connected:
        port_ids.append(i)

    return tuple(port_ids)

  def DetectResolution(self, port_id):
    """Detects the video source resolution.

    Args:
      port_id: The ID of the video input port.

    Returns:
      A (width, height) tuple.
    """
    port = self.PORTS[port_id]
    assert port.has_video
    r = port.video_dev.get_frame_size()
    return (r["width"], r["height"])

  def CaptureVideo(self, port_id, frame_count, x=None, y=None, width=None,
                   height=None):
    """Captures the video stream on the given video input to the buffer.

    This API is a synchronous call. It returns after all the frames are
    captured. The frames can be read using the ReadCapturedFrame API.

    The example of usage:
      chameleon.CaptureVideo(hdmi_input, total_frame)
      for i in xrange(total_frame):
        frame = chameleon.ReadCapturedFrame(i, *area).data
        CompareFrame(frame, golden_frames[i])

    Args:
      port_id: The ID of the video input port.
      total_frame: The total number of frames to capture, should not larger
                   than value of GetMaxFrameLimit.
      x: The X position of the top-left corner of crop.
      y: The Y position of the top-left corner of crop.
      width: The width of the area of crop.
      height: The height of the area of crop.
    """

    if (x, y, width, height) != (None, ) * 4:
      raise NotImplementedError("frame cropping")

    port = self.PORTS[port_id]
    dev = port.video_dev
    if port.is_ite:
      ec_frame_info = self._GetITEVideoParams(port)
      # TODO: provide different bpp if needed to v4l

    self.frame_buffer.clear()

    buf, v4l_frame_info = dev.get_frame(frame_count)
    if port.is_ite:
      assert ec_frame_info["hactive"] == v4l_frame_info["width"] and \
              ec_frame_info["vactive"] == v4l_frame_info["height"], \
              "Resolution directly from EC should match what we get via FPGA + V4L"

    raw_buffer = numpy.memmap(buf.name, dtype=numpy.uint8)
    assert len(raw_buffer), "We should have gotten something from V4L"

    # fully interpret dimensions
    frames = raw_buffer.reshape(
      frame_count,
      v4l_frame_info["height"], v4l_frame_info["width"],
      -1, # let channels get autodetected for now
    )

    # convert to RGB24 if needed
    frames = frames[...,(2,1,0)]

    # TODO: Make use of x, y, width, height to crop in software

    for i, frame in enumerate(frames):
      self.frame_buffer.append(frame)

      if i==0: logging.debug(f"Captured {frame.size=} {frame.shape=}")
      peek = frame.flatten()[:20].tobytes().hex()
      logging.debug(f"frames[{i}] {peek}...")

  def GetCapturedResolution(self):
    """Gets the resolution of the last captured frame.

    If a cropping area is specified on capturing, returns the cropped
    resolution.

    Returns:
      A (width, height) tuple.
    """

    height, width, _channels = self.frame_buffer[-1].shape
    return (width, height)

  def ReadCapturedFrame(self, frame_index):
    """Reads the content of the captured frame from the buffer.

    Args:
      frame_index: The index of the frame to read.
                   This is a little awkward on chameleonv3
                   as there's no global buffer.

    Returns:
      A byte-array of the pixels, wrapped in a xmlrpclib.Binary object.
    """

    frame_bytes = self.frame_buffer[frame_index].flatten().tobytes()

    return xmlrpc.client.Binary(frame_bytes)

  def DumpPixels(self, port_id, x=None, y=None, width=None, height=None):
    """Dumps the raw pixel array of the selected area.

    If not given the area, default to capture the whole screen.

    Args:
      port_id: The ID of the video input port.
      x: The X position of the top-left corner.
      y: The Y position of the top-left corner.
      width: The width of the area.
      height: The height of the area.

    Returns:
      A byte-array of the pixels, wrapped in a xmlrpclib.Binary object.
    """
    self.CaptureVideo(port_id, self._DEFAULT_FRAME_LIMIT, x, y, width, height)
    return self.ReadCapturedFrame(self._DEFAULT_FRAME_INDEX)

  def _GetITEVideoParams(self, port):
    assert port.has_video
    assert port.is_ite

    p = self.it68051_service.get_video_params()

    assert p.v_total == sum((p.v_front_porch, p.v_sync_width, p.v_back_porch, p.v_active))
    assert p.h_total == sum((p.h_front_porch, p.h_sync_width, p.h_back_porch, p.h_active))

    return {
      'clock': p.pclk / 1e3, # Convert kHz to MHz

      'htotal': p.h_total,
      'hfront_porch': p.h_front_porch,
      'hsync_width': p.h_sync_width,
      'hback_porch': p.h_back_porch,
      'hactive': p.h_active,
      'hsync_polarity': p.h_sync_polarity_is_positive,

      'vtotal': p.v_total,
      'vfront_porch': p.v_front_porch,
      'vsync_width': p.v_sync_width,
      'vback_porch': p.v_back_porch,
      'vactive': p.v_active,
      'vsync_polarity': p.v_sync_polarity_is_positive,

      'frame_rate': p.frame_rate,
      'interlaced': not p.is_progressive,
      'bpc': 8, # EC + ITE are hardcoded to 8, 10 might be possible
    }

  def GetVideoParams(self, port_id):
    """Gets video parameters.

    Args:
      port_id: The ID of the video input port.

    Returns:
      A dict containing video parameters.
    """
    port = self.PORTS[port_id]

    if port.is_ite:
      ec_reply = self._GetITEVideoParams()
      assert (ec_reply["hactive"], ec_reply["vactive"]) == self.DetectResolution(port_id), \
              "Resolution directly from EC should match what we get via FPGA + V4L"
      return ec_reply
    else:
      raise NotImplementedError("Need to ask the FPGA Logic")

    # *_offset is weird in the interface.py, defined as:
    # ```offset from start edge to active edge```
    # A standard video transmission looks like:
    #    front_porch, sync, back_porch, active
    #                ^------offset------^
    #    ^-----------total--------------------^
    ret['hsync_offset'] = ret['hsync_width'] + ret['hback_porch']
    ret['vsync_offset'] = ret['vsync_width'] + ret['vback_porch']

    return ret

  def HasAudioBoard(self):
    """Returns True if there is an audio board.

    Returns:
      True if there is an audio board. False otherwise.
    """
    try:
      return self.audio_board is not None
    except AttributeError:
      # what's that?
      return False

  def _fmt_var(self, value, name=None):
    """Format method argument or return value so it's suitable for logging."""
    if name == "port_id":
      try:
        port_id = value
        port = self.PORTS[port_id]
        fmt_str = f"{port_id} {port}"
      except IndexError as e:
        fmt_str = f"{port_id} IndexError"

    elif isinstance(value, xmlrpc.client.Binary):
      fmt_str = f"{value.data[:16]!r}"
      if len(value.data) > 16:
        fmt_str += "..."

    else:
      fmt_str = repr(value)

    if name is None:
      return fmt_str
    else:
      return f"{name}={fmt_str}"

  def _dispatch(self, method_name, params):
    """Dispatch wrapper to improve XMLRPC call logging

    We'll log:
      * Method names
      * Nicely formatted method arguments
      * Conditionally the return values
      * Whole traceback of exceptions seen by clients
    """

    try:
      method = getattr(self, method_name)

      bound_params = inspect.signature(method).bind(*params)
      bound_params.apply_defaults()

      # format all arguments for logging
      fmt_strings = [self._fmt_var(arg_value, name=arg_name)
        for arg_name, arg_value in bound_params.arguments.items()]
      logging.info(f"XMLRPC .{method_name}({', '.join(fmt_strings)})")

      ret = method(*params)

      # log what we returned
      if method_name == "GetChameleondLogs":
        logging.info(f'XMLRPC .{method_name} returned {len(ret)} bytes')
      elif ret is not None:
        ret_str = self._fmt_var(ret)
        logging.info(f'XMLRPC .{method_name} returned => {ret_str}')

      return ret

    except Exception:
      logging.exception(f"Exception sent to XMLRPC client during .{method_name}:")
      # logging.exception automatically prints the current traceback
      raise
