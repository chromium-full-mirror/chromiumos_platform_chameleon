# -*- coding: utf-8 -*-
# Copyright 2021 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Chameleond Driver for Chameleon v3 hardware."""

from collections import namedtuple
from dataclasses import dataclass, field
from enum import auto, Enum, IntEnum, StrEnum
import functools
import itertools
import inspect
import linuxpy.video.device as dev
import linuxpy.video.raw as raw
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
import types
import xmlrpc.client

from interface import ChameleondInterface
from linuxpy.ioctl import ioctl
from linuxpy.video.device import Buffer, Device, EventReader, VideoCapture
from linuxpy.video.raw import EventType, BufType

EC_PROTO_PATH = (pathlib.Path(__file__)/"../../../v3/ec/proto/v3.proto").resolve()
EC_PROTO = pw_protobuf_compiler.python_protos.Library.from_paths([EC_PROTO_PATH]).modules_by_package[""][0]
ITE_PORT_1 = EC_PROTO.it68051_port_num.PORT1
ITE_PORT_2 = EC_PROTO.it68051_port_num.PORT2
VIDEOMUX_ITE = EC_PROTO.videomux_set_request.videomux_dest.RX
VIDEOMUX_FPGA = EC_PROTO.videomux_set_request.videomux_dest.FPGA

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
  id: str | int
  pixelformat: str
  videomux_end: EC_PROTO.videomux_set_request.videomux_dest

  class Timeout(Exception):
    pass

  def __post_init__(self):
    if type(self.id) == int:
      self.path = f"/dev/v4l/by-path/platform-{self.id:x}.video-video-index0"
    else:
      self.path = self.id
    # make sure we support self.pixelformat
    with Device(self.path) as video_dev:
      assert self.pixelformat in [fmt.pixel_format.human_str() for fmt in video_dev.info.formats]

  def get_frame_size(self):
    info = {}
    with Device(self.path) as video_dev:
      info["width"] = video_dev.info.frame_sizes[0].width
      info["height"] = video_dev.info.frame_sizes[0].height
      # TODO(b/270594577): Implement better way to access size of the image in linuxpy
      fmt = dev.get_raw_format(video_dev.fileno(), BufType.VIDEO_CAPTURE)
      info["size"] = fmt.fmt.pix.sizeimage

    return info

  @staticmethod
  def _process_frame(memory_map) -> tuple[Buffer, raw.v4l2_buffer]:
    with memory_map.queue as buff:
      # Call callback with its argument
      memory_map._process_frame_callback(memory_map.buffers[buff.index], buff,
                                         memory_map._process_frame_arg)
      return b'', buff

  @staticmethod
  def save_frame_to_file(frame, buff, file):
    # Write whole frame to the file
    file.write(memoryview(frame)[:buff.bytesused])

  def get_frame(self, count=1, timeout=5, callback=save_frame_to_file):
    with Device(self.path) as video_dev:
      with EventReader(video_dev) as event_queue:
        video_dev.subscribe_event(EventType.SOURCE_CHANGE)
        while timeout is None or timeout > 0:
          start = time.clock_gettime(time.CLOCK_MONOTONIC)
          # For now save frames into tempfile to keep previous behavior
          buf = tempfile.NamedTemporaryFile(prefix="chameleond_", suffix=".fb")
          # Make sure that expected pixelformat is selected
          video_dev.set_format(BufType.VIDEO_CAPTURE, 0, 0, self.pixelformat)
          try:
            with VideoCapture(video_dev, source=raw.Capability.STREAMING) as video_capture:
              video_capture.buffer._process_frame_arg = buf.file
              video_capture.buffer._process_frame_callback = callback
              video_capture.buffer.raw_grab = types.MethodType(self._process_frame,
                                                               video_capture.buffer)
              for i in range(count):
                # For each frame _process_frame with callback is called
                frame = video_capture.buffer.frame_reader.read(timeout)
                if frame is None:
                  raise self.Timeout()

              # All frames collected, all of them have the same size
              dv_timings = raw.v4l2_dv_timings()
              ioctl(video_dev.fileno(), raw.IOC.G_DV_TIMINGS, dv_timings)
              info = {}
              info["width"] = dv_timings.bt.width
              info["height"] = dv_timings.bt.height
              # TODO(b/315132760): Now kernel only support 8 bit per color, but we should take into
              #                    account what is actual pixel format.
              info["size"] = dv_timings.bt.width * dv_timings.bt.height * 3
              return buf, info
          except OSError as e:
            # Check if exception is due to an event
            resolution_change = False
            while event := event_queue.read(0):
              if event.type == EventType.SOURCE_CHANGE:
                if event.u.src_change.changes == EventType.SRC_CH_RESOLUTION:
                  # This is resolution change, try again
                  resolution_change = True
            if not resolution_change:
              # Unknown event, just throw the catched error
              raise e from None
            # Acknowledge to device that we are aware of resolution change
            # TODO(b/270594577): Implement DV timings primitives directly in linuxpy
            dv_timings = raw.v4l2_dv_timings()
            ioctl(video_dev.fileno(), raw.IOC.QUERY_DV_TIMINGS, dv_timings)
            ioctl(video_dev.fileno(), raw.IOC.S_DV_TIMINGS, dv_timings)
          if timeout is not None:
            # Reduce timeout by elapsed time
            timeout -= time.clock_gettime(time.CLOCK_MONOTONIC) - start
    raise self.Timeout()

  def clear_edid(self):
    with Device(self.path) as video_dev:
      return video_dev.clear_edid()

  def get_edid(self):
    with Device(self.path) as video_dev:
      return video_dev.get_edid()

  def set_edid(self, new_edid):
    with Device(self.path) as video_dev:
      return video_dev.set_edid(new_edid)

  def get_video_params(self):
    with Device(self.path) as video_dev:
      dv_timings = raw.v4l2_dv_timings()
      ioctl(video_dev.fileno(), raw.IOC.QUERY_DV_TIMINGS, dv_timings)
      htotal = (dv_timings.bt.width + dv_timings.bt.hsync +
                dv_timings.bt.hbackporch + dv_timings.bt.hfrontporch)
      vtotal = (dv_timings.bt.height + dv_timings.bt.vsync +
                dv_timings.bt.vbackporch + dv_timings.bt.vfrontporch)
      pixelclock = dv_timings.bt.pixelclock
      # Calculate frame rate from pixel clock and total pixels transmited
      frame_rate = pixelclock / (htotal * vtotal)

      return {
        'clock': pixelclock / 1e6, # Convert from Hz to MHz

        'htotal': htotal,
        'hfront_porch': dv_timings.bt.hfrontporch,
        'hsync_width': dv_timings.bt.hsync,
        'hback_porch': dv_timings.bt.hbackporch,
        'hactive': dv_timings.bt.width,
        'hsync_polarity': bool(raw.PositivePolarityFlag.V4L2_DV_HSYNC_POS_POL &
                               dv_timings.bt.polarities),
        'vtotal': vtotal,
        'vfront_porch': dv_timings.bt.vfrontporch,
        'vsync_width': dv_timings.bt.vsync,
        'vback_porch': dv_timings.bt.vbackporch,
        'vactive': dv_timings.bt.height,
        'vsync_polarity': bool(raw.PositivePolarityFlag.V4L2_DV_VSYNC_POS_POL &
                               dv_timings.bt.polarities),
        'frame_rate': frame_rate,
        'interlaced': dv_timings.bt.interlaced,
        'bpc': 8, # TODO(b/315132760): Now kernel only support 8 bit, but later it should be
                  #                    possible to get that info from pixel format
      }

  def __repr__(self):
    return f"{self.__class__.__name__}({self.path!r})"


class PortId(IntEnum):
  ITE_DP1 = 0
  ITE_DP2 = 1
  ITE_HDMI1 = 2
  ITE_HDMI2 = 3
  FPGA_DP1 = 4
  FPGA_DP2 = 5
  FPGA_DP2_MST0 = 5
  FPGA_DP2_MST1 = 6
  FPGA_DP2_MST2 = 7
  FPGA_DP2_MST3 = 8


class Mux(Enum):
  VIDEOMUX_1 = auto()
  VIDEOMUX_2 = auto()
  ITE = auto()


Connector = namedtuple('Connector', ['type', 'id'])


class ConnectorId(Enum):
  LEFT_DP = Connector('dp', 1)
  RIGHT_DP = Connector('dp', 2)
  LEFT_HDMI = Connector('hdmi', 1)
  RIGHT_HDMI = Connector('hdmi', 2)

  def mux_arg(self):
    return self.value.type + str(self.value.id)

  def mux(self):
    if self.value.id == 1:
      return Mux.VIDEOMUX_1
    else:
      return Mux.VIDEOMUX_2


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
    connector: ConnectorId
    muxes: dict = field(default_factory=dict)
    video_dev: V4L = None
    audio_dev: object = None
    parent: PortId = None
    is_mst: bool = False
    children: set = field(default_factory=set)

    def __post_init__(self):
      # Implicit videomux configuration
      self.muxes[self.connector.mux()] = (self.connector.mux_arg(), self.video_dev.videomux_end)
      self.is_ite = Mux.ITE in self.muxes

      self.connector_type = self.connector.value.type.upper()

      self.has_video = self.video_dev is not None
      self.has_audio = self.audio_dev is not None

      self.edid = None

  ite_v4l_dev = V4L(0xc0060500, pixelformat="RX24", videomux_end=VIDEOMUX_ITE)
  PORTS = {
          PortId.FPGA_DP1:  Port("FPGA DP1 (left) aka DP1 SST", ConnectorId.LEFT_DP,
                                 video_dev=V4L(0xc0060a00, pixelformat="RGB3",
                                               videomux_end=VIDEOMUX_FPGA)), # SST
          PortId.FPGA_DP2:  Port("FPGA DP2 (right) aka DP2 MST0", ConnectorId.RIGHT_DP,
                                 video_dev=V4L(0xc0060600, pixelformat="RGB3",
                                               videomux_end=VIDEOMUX_FPGA),
                                 is_mst=True), # MST
          PortId.ITE_DP1:   Port("ITE DP1 (left)", ConnectorId.LEFT_DP, video_dev=ite_v4l_dev,
                                 muxes={Mux.ITE: ITE_PORT_1}),
          PortId.ITE_DP2:   Port("ITE DP2 (right)", ConnectorId.RIGHT_DP, video_dev=ite_v4l_dev,
                                 muxes={Mux.ITE: ITE_PORT_2}),
          PortId.ITE_HDMI1: Port("ITE HDMI1 (left)", ConnectorId.LEFT_HDMI, video_dev=ite_v4l_dev,
                                 muxes={Mux.ITE: ITE_PORT_1}),
          PortId.ITE_HDMI2: Port("ITE HDMI2 (right)", ConnectorId.RIGHT_HDMI, video_dev=ite_v4l_dev,
                                 muxes={Mux.ITE: ITE_PORT_2}),
          PortId.FPGA_DP2_MST1: Port("FPGA DP2 MST1", ConnectorId.RIGHT_DP,
                                     video_dev=V4L(0xc0060700, pixelformat="RGB3",
                                                   videomux_end=VIDEOMUX_FPGA),
                                     parent=PortId.FPGA_DP2_MST0, is_mst=True),
          PortId.FPGA_DP2_MST2: Port("FPGA DP2 MST2", ConnectorId.RIGHT_DP,
                                     video_dev=V4L(0xc0060800, pixelformat="RGB3",
                                                   videomux_end=VIDEOMUX_FPGA),
                                     parent=PortId.FPGA_DP2_MST0, is_mst=True),
          PortId.FPGA_DP2_MST3: Port("FPGA DP2 MST3", ConnectorId.RIGHT_DP,
                                     video_dev=V4L(0xc0060900, pixelformat="RGB3",
                                                   videomux_end=VIDEOMUX_FPGA),
                                     parent=PortId.FPGA_DP2_MST0, is_mst=True),
    #PORT("LINE_IN",   audio_dev=), # SSM2603
    #PORT("AUDIO_OUT", audio_dev=), # SSM2603
    #PORT("MIC",       audio_dev=), # SSM2603
  }

  def __init__(self, *args, **kwargs):
    super().__init__(*args, **kwargs)

    self.frame_buffer = []
    self.edid_database = {}

    # Create dict of root ports as it is useful sometimes
    self.ROOT_PORTS = {i: p for i, p in self.PORTS.items() if p.parent is None}
    # Create children sets
    for i, port in self.PORTS.items():
      if port.parent is None:
        continue
      self.PORTS[port.parent].children.add(i)

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

    self._reset_in_fpga_decoders()

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

  def _reset_in_fpga_decoders(self):
    """Reset the in-fpga decoder states."""

    # Disconect by default the in-fpga decoder HPDs
    for port_id, port in self.ROOT_PORTS.items():
      if port.has_video and not port.is_ite:
        self.Unplug(port_id)

  def Reset(self):
    """Resets Chameleon board."""
    # Let's reset the EC!
    _check_output("sudo gpioset -t0 -d open-drain --by-name STM32_RST_L=0", shell=True)
    _check_output("sudo gpioset -t0 -d open-drain --by-name STM32_RST_L=1", shell=True)

    self._reset_in_fpga_decoders()

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
    for port_id, port in self.PORTS.items():
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

  def GetPortName(self, port_id):
    """Get a human friendly name of the port.

    Args:
      port_id: The ID of the video port.

    Returns:
      String with name.
    """
    return self.PORTS[port_id].name

  def GetDetectedStatus(self):
    """Returns detetcted status of all devices.

    User can use this API to know the capability of the chameleon board.

    Returns:
      A list of a tuple of detected devices' strings detected status.
      e.g. [('HDMI', True), ('MIC', False)]
    """
    return [(port.name, i in self.ProbePorts())
              for i, port in self.ROOT_PORTS.items()]

  def GetSupportedPorts(self):
    """Returns all supported ports on the board.

    Not like the ProbePorts() method which only returns the ports which
    are connected, this method returns all supported ports on the board.

    Returns:
      A tuple of port_id, for all supported ports on the board.
    """
    return tuple([i.value for i in self.ROOT_PORTS])

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

  def GetChildren(self, port_id):
    """Returns IDs of children of the selected port.

    Get children ports that depends on the selected port. Children ports can be plugged
    using PlugWithChildren method. Child ID can be used as a port ID in all methods
    except Plug, Unplug and all HPD functions. Unplug of parent will unplug children.

    Args:
      port_id: The ID of the video port.

    Returns:
      Tuple of children IDs.
    """
    return tuple([c.value for c in self.PORTS[port_id].children])

  def IsMst(self, port_id):
    """Returns true if the port is configured as MST.

    Args:
      port_id: The ID of the video port.

    Returns:
      True if the port is MST; otherwise, False.
    """
    return self.PORTS[port_id].is_mst

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
      if port.is_ite:
        self._send_cached_edid_to_hardware(port)
        logging.warning("Might be too late to send EDID to ITE chip after port's been plugged.")
      else:
        logging.warning("New EDID will be used after next Plug() or FireHpdPulse()")

  def _send_cached_edid_to_hardware(self, port):
    """Actually send EDID cached by python to the hardware.

    Code from ApplyEdid can't always override the edid in the hardware due to
    the ways muxes are configured. Eg: setting ITE_HDMI1 edid could override
    ITE_DP2 if done the naive way.

    So we defer the sending till the Plug event so we're muxed correctly first.

    Args:
      port: Port() instance
    """
    if port.is_ite:
      if port.edid is None:
        logging.warning(f"We're not sure what EDID to use for {port}, leaving what the hardware has (either default or previous).")
        return
      self.it68051_service.write_edid(raw_edid=port.edid)
    else: # in-fpga decoder
      if port.edid is None:
        raise ChameleondError(f"{port} needs to have an EDID applied first before plugging.")
      port.video_dev.set_edid(port.edid)

  def _is_port_routed(self, port):
    """Returns true if muxes are set in the way that video reach the port.

    Args:
      port: Port() instance

    Returns:
      True if the port is routed; otherwise, False.
    """
    for mux, direction in port.muxes.items():
      match mux:
        case Mux.VIDEOMUX_1 | Mux.VIDEOMUX_2:
          board_mux_conf = self.videomux_service.get()
          current_direction = getattr(board_mux_conf, direction[0])
          if current_direction != direction[1]:
            return False
        case Mux.ITE:
          if self.it68051_service.get_selected_port().port != direction:
            return False
    return True

  def _mux_to_port(self, port):
    """Set muxes to route to the port

    Args:
      port: Port() instance
    """
    for mux, direction in port.muxes.items():
      match mux:
        case Mux.VIDEOMUX_1 | Mux.VIDEOMUX_2:
          self.videomux_service.set(
            **{direction[0]: direction[1]}
          )
        case Mux.ITE:
          self.it68051_service.select_port(port=direction)

  def _is_mutually_exclusive(self, port1, port2):
    """Returns true if the first port is mutually exclusive with the second port.

    Ports are mutually exclusive if they share connector or paths in muxes.

    Args:
      port1: Port() instance
      port2: Port() instance

    Returns:
      True if ports are mutually exclusive; otherwise, False.
    """
    for mux in port1.muxes:
      if not mux in port2.muxes:
        continue
      match mux:
        case Mux.VIDEOMUX_1 | Mux.VIDEOMUX_2:
          if port1.muxes[mux] == port2.muxes[mux]:
            # The same mux configuration, so no conflict
            continue
          if port1.muxes[mux][0] == port2.muxes[mux][0]:
            # Ports share connector, so they are in confilct
            return True
          if port1.muxes[mux][1] == port2.muxes[mux][1]:
            # Ports share destination, so they are in confilct
            return True
        case Mux.ITE:
          if port1.muxes[mux] != port2.muxes[mux]:
            # Ports use different ITE port, so they are in conflict
            return True
    return False

  def IsConflict(self, port_id_a, port_id_b):
    """Check if ports can't be plugged at the same time.

    Args:
      port_id_a: The ID of the video port.
      port_id_b: The ID of the video port.

    Returns:
      True if ports can't be plugged at the same time. Flase otherwise.
    """
    return self._is_mutually_exclusive(self.PORTS[port_id_a], self.PORTS[port_id_b])

  def GetMutuallyExclusivePorts(self, port_id):
    """Get ports that can't be plugged at the same time.

    Args:
      port_id: The ID of the video port.

    Returns:
      Tuple of port's IDs that can't be plugged at the same time as port_id.
    """
    port = self.PORTS[port_id]
    port_ids = []
    for i, other_port in self.PORTS.items():
      if other_port.has_video:
        if self._is_mutually_exclusive(port, other_port):
          port_ids.append(i.value)

    return tuple(port_ids)

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
      if not self._is_port_routed(port):
        return False

      if port.is_ite:
        # make sure we're emitting hpd
        if self.it68051_service.get_hpd(port=port.muxes[Mux.ITE]).on_off == 0:
          return False
      else: # in-fpga decoder
        # HPD is active when V4L has an EDID set
        while not port.parent is None:
          # Check if child has EDID set and move to parent
          if not bool(port.video_dev.get_edid()):
            return False
          port = self.PORTS[port.parent]
        return bool(port.video_dev.get_edid())

    # If nothing caught yet, it's probably connected
    return True

  def _can_be_plugged(self, port_id, port, raise_error=False):
    """Check if port can be plugged now.

    If video port cannot be plugged and raise_error is True, then appropriate error is raised.

    Args:
      port: Port() instance

    Returns:
      True if port can be plugged; otherwise, False.
    """
    if not port.has_video:
      return False

    if not port.parent is None:
      if raise_error:
        raise ChameleondError(f"{port_id} ({port}) has a parent. Use PlugWithChildren"
                              f"({port.parent}, [{port_id}]) instead.")
      return False
    for other_port_id, other_port in self.PORTS.items():
      if port is other_port:
        continue
      if self._is_mutually_exclusive(port, other_port):
        if self.IsPlugged(other_port_id):
          if raise_error:
            raise ChameleondError(f"Other mutually exclusive port:{other_port} already connected")
          return False

    return True

  def Plug(self, port_id):
    """Emulates plug, like asserting HPD line to high on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]

    if self._can_be_plugged(port_id, port, raise_error=True):
      # If port has a child, unplug first to clear its EDID
      if len(port.children) > 0:
        self.UnplugHPD(port_id)

      # set routing via the EC
      self._mux_to_port(port)

      self._send_cached_edid_to_hardware(port)

      if port.is_ite:
        self.it68051_service.set_hpd(port=port.muxes[Mux.ITE], on_off=1)
      else:
        # HPD was already asserted by just setting the edid a little up
        assert port.video_dev.get_edid(), f"by now {port} should have had an EDID set"

    # If we switch v4l frameworks, perhaps re-open the device here

  def PlugWithChildren(self, port_id, children_ids):
    """Plug port with its children.

    Plug port and its selected children.

    Args:
      port_id: The ID of the video port.
      children_ids: Tuple of children ports to plug.
    """
    port = self.PORTS[port_id]

    # Check if these are really children or grandchildren
    for child in children_ids:
      child_port = self.PORTS[child]
      while child_port.parent != port_id:
        if child_port.parent is None:
          raise ChameleondError(f"{child} is not a child of {port_id}")
        child_port = self.PORTS[child_port.parent]

    if self._can_be_plugged(port_id, port, raise_error=True):
      # Unplug HPD first to prevent flickering while we are setting edids to children
      self.UnplugHPD(port_id)

      self._mux_to_port(port)

      for child in children_ids:
        self._send_cached_edid_to_hardware(self.PORTS[child])

      self._send_cached_edid_to_hardware(port)

      if port.is_ite:
        self.it68051_service.set_hpd(port=port.muxes[Mux.ITE], on_off=1)
      else:
        # HPD was already asserted by just setting the edid a little up
        assert port.video_dev.get_edid(), f"by now {port} should have had an EDID set"

  def Unplug(self, port_id):
    """Emulates unplug, like deasserting HPD line to low on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    if not port.parent is None:
      raise ChameleondError(f"{port_id} ({port}) has a parent. Use Unplug({port.parent}) instead")
    if port.has_video:
      port.edid = None # forget the port's edid

      def clear_grandchildren(port):
        for child in port.children:
          child_port = self.PORTS[child]
          if child_port.has_video:
            child_port.edid = None
          clear_grandchildren(child_port)

      clear_grandchildren(port)
      self.UnplugHPD(port_id)

  def UnplugHPD(self, port_id):
    """Only deassert HPD line to low on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    assert port.has_video
    if port.is_ite:
      self.it68051_service.set_hpd(port=port.muxes[Mux.ITE], on_off=0)
    else:
      # Clearing EDID deasserts HPD
      port.video_dev.clear_edid()

      def clear_grandchildren(port):
        for child in port.children:
          child_port = self.PORTS[child]
          if child_port.has_video:
            child_port.video_dev.clear_edid()
          clear_grandchildren(child_port)

      clear_grandchildren(port)

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
    except V4L.Timeout:
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
    for i, port in self.ROOT_PORTS.items():
      if port.has_video:
        connected = getattr(source_presence, port.connector.mux_arg())
        if port.connector_type == "HDMI" and board_version <= 2:
          # HACK(b/220139622): Temporarly lie, hw issue on proto2
          # otherwise autotest gets mad
          connected = False
      if connected:
        port_ids.append(i.value)

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

    if dev.pixelformat == "RX24": # TODO(b/287467394): remove this
      # convert to RGB3 if needed
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

  def _GetFPGAVideoParams(self, port):
    assert port.has_video
    assert not port.is_ite

    return port.video_dev.get_video_params()

  def GetVideoParams(self, port_id):
    """Gets video parameters.

    Args:
      port_id: The ID of the video input port.

    Returns:
      A dict containing video parameters.
    """
    port = self.PORTS[port_id]

    if port.is_ite:
      ret = self._GetITEVideoParams(port)
      assert (ret["hactive"], ret["vactive"]) == self.DetectResolution(port_id), \
              "Resolution directly from EC should match what we get via FPGA + V4L"
    else:
      ret = self._GetFPGAVideoParams(port)

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
