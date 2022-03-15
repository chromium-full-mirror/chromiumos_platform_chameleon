# -*- coding: utf-8 -*-
# Copyright (c) 2021 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Chameleond Driver for Chameleon v3 hardware."""

from dataclasses import dataclass
import logging
import numpy
import pathlib
import pw_hdlc.rpc
import pw_protobuf_compiler
import serial
import subprocess
import time
import xmlrpc.client


from . import chameleon_common  # pylint: disable=W0611
from chameleond.interface import ChameleondInterface

EC_PROTO_PATH = (pathlib.Path(__file__)/"../../../v3/ec/proto/v3.proto").resolve()
EC_PROTO = pw_protobuf_compiler.python_protos.Library.from_paths([EC_PROTO_PATH]).modules_by_package[""][0]

class V4L:
  def __init__(self, path):
    self.path = path

  def get_resolution(self):
    list_formats = subprocess.run(
        ["v4l2-ctl", "--list-formats-ext", "-d", self.path],
        encoding="utf-8",
        stdout=subprocess.PIPE,
        check=True,
    ).stdout.strip()

    # last word will have the resolution in "widthxheight" format
    return tuple(int(d) for d in list_formats.split()[-1].split("x"))

  def get_frame(self, count=1, timeout=None):
    return subprocess.run(
      [
        "v4l2-ctl",
        "--stream-mmap",
        "--stream-count", str(count),
        "--device", self.path,
        "--stream-to", "-"
      ],
      stdout=subprocess.PIPE,
      check=True,
      timeout=timeout,
    ).stdout

  def __repr__(self):
    return f"{self.__class__.__name__}({self.path!r})"

class ChameleondDriver(ChameleondInterface):
  frame_buffer: list
  # The frame index which is used for the regular DumpPixels API.
  _DEFAULT_FRAME_INDEX = 0
  _DEFAULT_FRAME_LIMIT = 1

  edid_database: dict # {edid_id: edid_bytes}

  NETWORK_INTERFACE = "eth0"

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
    self.ec_client = pw_hdlc.rpc.HdlcRpcClient(
      read = lambda: self.ec_serial.read(4096),
      paths_or_modules = [EC_PROTO],
      channels = pw_hdlc.rpc.default_channels(self.ec_serial.write),
    )

    self.board_service = self.ec_client.rpcs()["board_service"]
    self.videomux_service = self.ec_client.rpcs()["videomux_service"]
    self.it68051_service = self.ec_client.rpcs()["it68051_service"]

  def Reset(self):
    """Resets Chameleon board."""
    pass

  def GetMacAddress(self):
    """Gets the MAC address of this Chameleon.

    Returns:
      A string for MAC address.
    """
    return open(f"/sys/class/net/{self.NETWORK_INTERFACE}/address").read().strip()

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
    """Returns the human readable string for the connector type.

    Args:
      port_id: The ID of the input/output port.

    Returns:
      A string, like "HDMI", "DP", "MIC", etc.
    """
    return self.PORTS[port_id].name

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

    logging.info(f"CreateEdid [edid_id={edid_id}]={edid.data[:16]!r}...")

    return edid_id

  def DestroyEdid(self, edid_id):
    """Destroys the internal record of EDID. The internal data will be freed.

    Args:
      edid_id: The ID of the EDID, which was created by CreateEdid().
    """
    del self.edid_database[edid_id]
    logging.info(f"DestroyEdid edid_id={edid_id}")

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
    logging.info(f"ReadEdid {port} port.edid={port.edid!r}")
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
    logging.info(f"ApplyEdid {port} edid_id={edid_id}"
                 f"self.edid_database.keys()={self.edid_database.keys()}")
    assert port.has_video

    edid_bytes = self.edid_database[edid_id]

    # We need to potentially pad it so it's 256 bytes (b/219231626)
    edid_bytes = edid_bytes.ljust(256, b'\0')

    port.edid = edid_bytes
    if self.IsPlugged(port_id):
      self._send_cached_edid_to_hardware(port)

  def _send_cached_edid_to_hardware(self, port, maybe=False):
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
      status, response = self.videomux_service.get()
      # TODO(amstan): figure out what to do with status
      current_direction = getattr(response, port.external_name.lower())
      if current_direction != port.videomux_direction:
        return False

      if port.is_ite:
        # make sure ite is on the correct port
        status, response = self.it68051_service.get_selected_port()
        if response.port != port.ite_port:
          return False

        # make sure we're emitting hpd
        status, response = self.it68051_service.get_hpd(port=port.ite_port)
        if response.on_off == 0:
          return False

    # If nothing caught yet, it's probably connected
    return True

  def Plug(self, port_id):
    """Emulates plug, like asserting HPD line to high on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    logging.info(f"Plug {port}")

    if port.has_video:
      # set routing via the EC
      self.videomux_service.set(
        **{port.external_name.lower(): port.videomux_direction}
      )
      if port.is_ite:
        self.it68051_service.select_port(port=port.ite_port)
        self.it68051_service.set_hpd(port=port.ite_port, on_off=1)
      else:
        raise NotImplementedError("Need to tell the FPGA Logic")
      self._send_cached_edid_to_hardware(port)

    # If we switch v4l frameworks, perhaps re-open the device here

  def Unplug(self, port_id):
    """Emulates unplug, like deasserting HPD line to low on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    logging.info(f"Unplug {port}")
    if port.has_video:
      # TODO: disconnect edid
      port.edid = None
      # TODO: disconnect ddc
      # TODO: Perhaps just videomux away? if we can figure out a way
      #    self.videomux_service.all_off()
      self.UnplugHPD(port_id)

  def UnplugHPD(self, port_id):
    """Only deassert HPD line to low on a video port.

    Args:
      port_id: The ID of the input/output port.
    """
    port = self.PORTS[port_id]
    logging.info(f"UnplugHPD {port}")
    assert port.has_video
    if port.is_ite:
      self.it68051_service.set_hpd(port=port.ite_port, on_off=0)
    else:
      raise NotImplementedError("Need to tell the FPGA Logic")

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
    logging.info(f"WaitVideoInputStable {port} timeout={timeout}")
    assert port.has_video

    if port.is_ite:
      # TODO: Poll the EC with new api to see if we have a connection
      pass
      # TODO: lower timeout by elapsed time

    # wait for v4l to show signs of life
    # just this alone seems to work great
    buf = None
    while not buf:
      buf = port.video_dev.get_frame(timeout=timeout)
      # TODO: lower timeout by elapsed time

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

    status, payload = self.board_service.get_source_presence()

    port_ids = []
    for i, port in enumerate(self.PORTS):
      if port.has_video:
        connected = getattr(payload, port.external_name.lower())
      if connected:
        port_ids.append(i)

    logging.info(f"ProbeInputs returning {[self.PORTS[p] for p in port_ids]}")
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
    return port.video_dev.get_resolution()

  def _AutoFillArea(self, port_id, x, y, width, height):
    """Verifies the area argument correctness and fills the default values.

    It keeps x=None and y=None if all of the x, y, width, and height are None.
    That hints FPGA to use a full-screen capture, not a cropped-sccren capture.

    Args:
      port_id: The ID of the video input port.
      x: The X position of the top-left corner.
      y: The Y position of the top-left corner.
      width: The width of the area.
      height: The height of the area.

    Returns:
      A tuple of (x, y, width, height)

    Raises:
      DriverError if the area is not specified correctly.
    """
    if (x, y, width, height) == (None, ) * 4:
      return (None, None) + self.DetectResolution(port_id)
    elif (x, y) == (None, ) * 2 or None not in (x, y, width, height):
      return (x, y, width, height)
    else:
      raise DriverError("Some of area arguments are not specified.")

  def CaptureVideo(self, port_id, total_frame, x=None, y=None, width=None,
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

    logging.info(f"CaptureVideo {self.PORTS[port_id]}, "
                 f"(x={x}, y={y}, width={width}, height={height})")

    # TODO: Make use of x, y, width, height to crop in software

    dev = self.PORTS[port_id].video_dev
    self.frame_buffer.clear()

    # TODO(amstan): pass total_frame to v4l2_ctl instead of a loop
    for i in range(total_frame):
      frame = dev.get_frame()
      self.frame_buffer.append(frame)
      logging.debug (f"frame[{i}] len={len(frame)} {frame[:20].hex()}...")
      assert frame, "We should have gotten something from V4L"

  def ReadCapturedFrame(self, frame_index):
    """Reads the content of the captured frame from the buffer.

    Args:
      frame_index: The index of the frame to read.
                   This is a little awkward on chameleonv3
                   as there"s no global buffer.

    Returns:
      A byte-array of the pixels, wrapped in a xmlrpclib.Binary object.
    """

    # format is BGR32
    frame = numpy.frombuffer(self.frame_buffer[frame_index], dtype=numpy.uint8)

    # convert to RGB24
    frame = frame.reshape(-1,4)[:,0:3][:,::-1].flatten()

    return xmlrpc.client.Binary(frame.tobytes())

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
    x, y, width, height = self._AutoFillArea(port_id, x, y, width, height)
    self.CaptureVideo(port_id, self._DEFAULT_FRAME_LIMIT, x, y, width, height)
    return self.ReadCapturedFrame(self._DEFAULT_FRAME_INDEX)

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
