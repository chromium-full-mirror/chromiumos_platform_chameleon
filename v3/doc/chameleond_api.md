# Chameleond (RPC) API

- Reset(self):

  Disconnect all ports, remove all EDIDs, discard all captured frames. Basically return Chameleon to the known fresh state.

- GetChameleondLogs(self, cursor="main"):

  Get logs from journalctl. Useful for debugging. For tests not so much.
  Returns string with logs.

- GetVersions(self):

  Gets versions of various components. Useful for debugging and logging. Tests shouldn’t act differently based on versions.
  Returns dictionary with component as a key and version string as a value.

- GetDetectedStatus(self):

  Gets list of all ports and if there is physically something connected to the port. Note some ports share physical connection, so all of them will have the same detect status. Note2 only parent MST port (MST Stream 0) is on the list, other MST ports are omitted.
  Returns list of tuples. The first item of the tuple is port name, the second is True if there is
  physical connection, otherwise False.

- GetSupportedPorts(self):

  Get list of all ports IDs. Note only parent MST port (MST Stream 0) is on the list, other MST ports are omitted.
  Returns tuple where each item is ID of one of the ports.

- GetSupportedInputs(self):

  At the moment there are no outputs so this is exactly the same as GetSupportedPorts.
  Returns tuple where each item is ID of one of the ports.

- GetSupportedOutputs(self):

  At the moment there are no outputs so the list is empty.
  Returns tuple where each item is ID of one of the ports.

- IsPhysicalPlugged(self, port_id):

  Check if there is physically something connected to the connector used by the port.
  Returns True if there is physical connection, otherwise False.

- ProbePorts(self):

  Get list of all ports that are physically connected to something. Note some ports share physical connection, so there can be more probed ports than cables plugged into chameleon. Note2 only parent MST port (MST Stream 0) can be on the list, other MST ports are omitted.
  Returns tuple where each item is ID of one of the ports.

- ProbeInputs(self):

  At the moment there are no outputs so this is exactly the same as ProbePorts.
  Returns tuple where each item is ID of one of the ports.

- ProbeOutputs(self):

  At the moment there are no outputs so the list is empty.
  Returns tuple where each item is ID of one of the ports.

- GetConnectorType(self, port_id):

  Connector type name of the port (e.g. “HDMI”, “DP”)
  Returns string with the connector name.

- IsConflict(self, port_id_a, port_id_b):

  Check if two ports are in conflict i.e. if the can or cannot be plugged at the same time.
  Returns True if ports are in conflict, otherwise False.

- GetMutuallyExclusivePorts(self, port_id):

  Gets list of all ports that cannot be plugged at the same time as the provided port.
  Returns tuple where each item is ID of one of the ports.

- GetPortName(self, port_id):

  Gets a human friendly name of the port. Shouldn’t be used by tests logic but can be useful for logging.
  Returns string with the port name.

- GetChildren(self, port_id):

  Gets a list of children ports of the provided port. Children ports are similar to ports but cannot be used with Plug, Unplug and all HPD methods. Instead the PlugWithChildren function can be used to plug a child port. Unplugging the parent port will unplug the child too.
  Returns tuple where each item is ID of one of the children.

- IsMst(self, port_id):

  Check if port is part of the MST chain. It can be either a child or a parent.
  Returns True if the port is MST, otherwise False.

- HasAudioSupport(self, port_id):

  Check if the port has audio. None port has that at the moment.
  Returns True if the port has audio support, otherwise False.

- HasVideoSupport(self, port_id):

  Check if the port has video.
  Returns True if the port has video support, otherwise False.

- WaitVideoInputStable(self, port_id, timeout=None):

  Wait until there is a stable video stream received on the port. Note that if timeout is None, this
  will wait forever blocking any interaction with chameleond.
  Returns True if video input is stable, otherwise False.

- CreateEdid(self, edid):

  Create EDID from given bytes. Returns the ID of the EDID that can be used in other EDID methods.

- DestroyEdid(self, edid_id):

  Removes EDID from internal database. The ID shouldn’t be used anymore.
  Raise ChameleondError when default (0) EDID ID is passed.
  Raise KeyError when unknown EDID ID is used.

- ReadEdid(self, port_id):

  Read EDID that will be/was used at the moment of plugging the port.
  Returns xmlrpclib.Binary object with EDID as a data.

- ApplyEdid(self, port_id, edid_id):

  Set EDID for the port. The EDID will be used on plugging the port.

- IsPlugged(self, port_id):

  Check if the port is plugged and is emitting HPD. Note that a port without cable in the physical connector can be still plugged at the same time.
  Returns True if port is plugged, otherwise False.

- Plug(self, port_id):

  Plug the port. Start emitting HPD. EDID has to be set first to the port. Note plugging MST port using this function will result in plugging just one stream.
  Raise ChameleondError when used with child port or conflicting port is already plugged.

- PlugWithChildren(self, port_id, children_ids):

  Plug the port and its children specified on the list.
  Raise ChameleondError when used with child port as port_id, conflicting port is already plugged or
  any child in the list is not child of the specified port.

- Unplug(self, port_id):

  Unplug the port i.e. HPD is no longer emitted, EDID is cleared. Children of the port are also unplugged.
  Raise ChameleondError when used with child port.

- UnplugHPD(self, port_id):

  Deassert HPD without clearing EDID.

- FireHpdPulse(self, port_id, deassert_interval_usec, assert_interval_usec=None, repeat_count=1, end_level=1):

  Performs multiple HPD unplugs and plugs.

- FireMixedHpdPulses(self, port_id, widths_msec):

  Performs multiple HPD pulses with specified duration.

- ScheduleHpdToggle(self, port_id, delay_ms, rising_edge):

  Sets HPD to the opposite value to rising_edge and after specified delay sets HPD to the value of rising_edge. After setting the initial HPD value, the function returns, so the user may do something else.
  Raise ChameleondError("There's another HPD scheduled.") when called again before previous HPD
  scheduled action is executed.

- DumpPixels(self, port_id, x=None, y=None, width=None, height=None):

  Get one frame from the specified port. Note that cropping is not supported. Note2 it will clear previously captured frames.
  Returns xmlrpclib.Binary object with pixels of the frame as a data.
  Raise NotImplementedError when frame cropping arguments are used.
  Raise v3.V4L.Timeout on FPGA ports when frame is not received within 5 seconds.

- CaptureVideo(self, port_id, total_frame, x=None, y=None, width=None, height=None):

  Capture specified number of frames from the specified port. Note that cropping is not supported. Note2 it will clear previously captured frames.
  Raise NotImplementedError when frame cropping arguments are used.
  Raise v3.V4L.Timeout on FPGA ports when frame is not received within 5 seconds.

- GetCapturedResolution(self):

  Get resolution of the last captured frame.
  Returns tuple where the first item is width in pixels and the second item is height in pixels.
  Raise IndexError expection when no frame was captured.

- ReadCapturedFrame(self, frame_index):

  Get binary data of the specified frame that was collected after the last CaptureVideo call.
  Returns xmlrpclib.Binary object with pixels of the frame as a data.
  Raise IndexError expection when non existing frame_index is used.

- DetectResolution(self, port_id):

  Get resolution of the video stream that is received at the moment.
  Returns tuple where the first item is width in pixels and the second item is height in pixels.

- GetVideoParams(self, port_id):

  Get timings of the video stream that is received at the moment.
  Returns dictionary containing following keys (if one is omitted then it is unknown):
    clock (float): pixel clock in MHz
    htotal (int)
    hactive (int)
    hsync_width (int): width from start edge to end edge
    hsync_offset (int): offset from start edge to active edge
    hsync_polarity (int): 0 for negative, 1 for positive
    vtotal (int)
    vactive (int)
    vsync_width (int): width from start edge to end edge
    vsync_offset (int): offset from start edge to active edge
    vsync_polarity (int): 0 for negative, 1 for positive
    bpc (int): bits per component
    interlaced (bool)
  Raise OSError (Errno 67) when there is no video stream on FPGA port.

- GetMacAddress(self):

  Get MAC address of the chameleon.
  Returns string with the MAC address.

- GetCapturedFrameMetadata(self, frame_index):

  Get metadata of the specified frame that was collected after the last CaptureVideo call. Metadata includes timestamp generated by the kernel upon receiving the frame.
  Returns dictionary containing following keys (if one is omitted then it is unknown):
    width (int): width of the frame in pixels
    height (int): height of the frame in pixels
    timestamp (float): time when kernel received the frame in seconds
    port_id (int): Video port from which the frame was captured
    sequence (int): Sequence number of the frame
    size (int): Size of the frame in bytes
  Raise IndexError expection when non existing frame_index is used.
