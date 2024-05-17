# Interact with chameleond
[TOC]

## Example clients
All available clients are described in the [readme inside the clients directory](../clients/README.md).

1. Navigate to `~/chromiumos/src/platform/chameleon` folder outside the chroot

2. `./v3/clients/screenshot --chameleon_host your_chameleon_ip --port_id 2`

    a) If your chameleon is in the office/lab, due to corporate firewall restrictions (see [go/corp-ssh-helper](http://go/corp-ssh-helper) and [go/chromeos-lab-duts-ssh](http://go/chromeos-lab-duts-ssh)), you need to use ssh tunneling

    b) In one terminal, `ssh -i ~/.ssh/testing_rsa cros@your_chameleon_ip -L 9992:localhost:9992`

    c) In a second terminal, `./v3/clients/screenshot --chameleon_host localhost --port_id 2`

## Manage chameleond daemon

Chameleond is managed by a systemd service.

Restart: `sudo systemctl restart chameleond`

Check logs: `journalctl -e -f -u chameleond`

## Interactive shell
The easiest way to start interacting with the chameleon is to use the [interactive
shell from the clients directory](../clients/README.md).

Following are some examples of basic usage of chameleon, using the interactive
shell.

### Generic flow
Chameleon v3 is using a `port identifier` (referred as port_id) which is a
`logical port` that joins both the physical connector (HDMI/DisplayPort) and decoder (ITE/FPGA).  
This allows to easily describe how user want to connect the Chameleon as video sink with
device that acts as a video source.  
The order of video ports is described as while the user is looking straight at
the connectors.

List of currently supported port identifiers are as follows:
* 0 - Left DisplayPort using ITE  
* 1 - Right DisplayPort using ITE  
* 2 - Left HDMI using ITE  
* 3 - Right HDMI using ITE  
* 4 - Left native DisplayPort with SST  
* 5 - Right native DisplayPort with MST (Stream 0 - root port)  
* 6 - Right native DisplayPort with MST (Stream 1)  
* 7 - Right native DisplayPort with MST (Stream 2)  
* 8 - Right native DisplayPort with MST (Stream 3)  

EDIDs are identified using the integer values. The chameleon provides default
EDID that uses the value of `0`.

The generic flow for using the chameleon is to (create and) apply edid to the
port, activate the port ("plug it"), capture the frame streamed to the chameleon
and disconnect the port ("unplug it").

### Get started
Below are examples of how to start using the chameleon to retrieve frames
from the devices connected to it.

#### Create custom EDID
EDIDs are identifiers sent from monitor to the host to help identify the monitor
and available resolutions. Chameleond provides default EDID with identifier of `0`
to allow the user to easily start testing the devices.  
The default EDID is copied from `4K_HP_Spectre32_DP.txt` from directory mentioned
in the note below. It advertises resolution of 3840x2160 on DisplayPort and
2048x1080 on HDMI and can be applied to any port.  
To create custom EDID, user has to provide it as argument to the `CreateEdid`
function. This function returns identifier of the newly created EDID that now
may be used as parameter to `ApplyEdid`.  
`ApplyEdid` function caches the value to be set at a moment of a next `Plug` call.
`Unplug` clears the cached EDID values and requires to set EDID again. The EDID
won't be changed when port is plugged.

**Note**: file with EDID consists of hex values in ASCII format with
additional new lines for readability. This example shows how to read them and
convert from ASCII format to binary one required by a `CreateEdid` function.

**Note**: Many files with EDIDs that can be used for tests may be found at the location:
https://chromium.googlesource.com/chromiumos/third_party/autotest/+/main/server/site_tests/display_EdidStress/test_data/edids

Example of how to read the EDID from hex encoded ASCII file using above mentioned
files available on the Chromium OS chroot/repo:

```
>>> from pathlib import Path
>>> EDID_DIR="chromiumos/src/third_party/autotest/files/server/site_tests/display_EdidStress/test_data/edids/daily"
>>> EDID_FILENAME="4K_DELL_UP3216Q_DP.txt"
>>> with open(Path.home() / EDID_DIR / EDID_FILENAME, "r") as file:
...     EDID=file.read()
>>> p.CreateEdid(bytes.fromhex(EDID))
1
>>> p.ApplyEdid(3, 1)
>>> p.Plug(3)
>>> p.IsPlugged(3)
True
>>> p.Unplug(3)
```

#### Detect resolution
One way to check if chameleon is receiving the frames correctly is to check
if it can detect correct resolution and detect its changes.  
Port 0 corresponds to left DisplayPort using ITE chip.  
To do that, the flow is as below. Different resolutions are received because
the DUT has changed the resolution of chameleon:
```
>>> p.ApplyEdid(0, 0)
>>> p.Plug(0)
>>> p.DetectResolution(0)
[1920, 1080]
>>> # Resolution changed on the DUT
>>> p.DetectResolution(0)
[3840, 2160]
>>> p.Unplug(0)
```

#### Capture single video frame
There is a helper function `WaitVideoInputStable` which waits until frames are
received on specified port. It should be used because DUT can take some time
until it starts sending frames to the chameleon.  
With only one parameter (port id) it waits for up to 5 seconds or until the port
starts receiving frames, whichever is first. If the call is interrupted,
whole chameleond may start being unresponsive unless the specified timeout
will pass. Due to that, it's recommended to not use too long timeout.  
If port doesn't receive any frame until set timeout, false will be returned.  
To capture single, current frame of the video stream, the easiest way is to
use the dedicated function called `DumpPixels`.

```
>>> p.ApplyEdid(4, 0)
>>> p.Plug(4)
>>> p.WaitVideoInputStable(4)
True
>>> p.DetectResolution(4)
[2560, 1440]
>>> with open("test.rgb", "wb") as f:
...     f.write(p.DumpPixels(4).data)
...
11059200
>>> p.Unplug(4)
```

Captured frame is dumped in raw format. To make it easy to preview with any
image editor, one may convert it to e.g. PNG format, using the command:  
`$ convert -size <width>x<height> -depth 8 <input> <output>`

For example, with resolution set as `2560x1440` and input file `test.rgb` and
output file as `test.png` the call should be:
`$ convert -size 2560x1440 -depth 8 test.rgb test.png`

After that, there will be a file named `test.png` which can be opened with command:  
`$ open test.png`

#### Capture multiple video frames
Flow for capturing frames on chameleon is to trigger capturing specific number
of frames, after capture has stopped, then retrieve these frames one by one
using frames sequence number.  
Chameleon caches captured frames and stores them until new capture is started.
There is no option to capture from multiple ports simultaneously and number of
frames cached on chameleon is limited by RAM size. Lower the resolution, more
frames can be captured during one call to `CaptureVideo` function.  
Caching frames allows to retrieve frame by frame and immediately make some
operations on them without the need to store all frames at once on the host side.

```
>>> p.ApplyEdid(4, 0)
>>> p.Plug(4)
>>> p.WaitVideoInputStable(4, 10)
>>> p.DetectResolution(4)
[2560, 1440]
>>> p.CaptureVideo(4, 30)
>>> p.GetCapturedFrameMetadata(29)
{'width': 2560, 'height': 1440, 'timestamp': 8387.567521, 'port_id': 4, 'sequence': 29, 'size': 11059200}
>>> for a in range(0, 30):
...     with open("test{}.rgb".format(a), "wb") as f:
...             f.write(p.ReadCapturedFrame(a).data)
...
11059200
[...]
11059200
>>>
```

**Note**: `CaptureVideo` function is blocking and returns when requested number
of frames is captured.

**Note**: Frame sequence number starts from 0. If we capture 30 frames, the
sequence numbers will be within 0 and 29, inclusive.

If user wants to capture more frames than there is available memory on the
chameleon, an RPC error will be returned and all frames discarded:
```
>>> p.CaptureVideo(4, 100)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/lib/python3.11/xmlrpc/client.py", line 1122, in __call__
    return self.__send(self.__name, args)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/xmlrpc/client.py", line 1464, in __request
    response = self.__transport.request(
               ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/xmlrpc/client.py", line 1166, in request
    return self.single_request(host, handler, request_body, verbose)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/xmlrpc/client.py", line 1182, in single_request
    return self.parse_response(resp)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.11/xmlrpc/client.py", line 1354, in parse_response
    return u.close()
           ^^^^^^^^^
  File "/usr/lib/python3.11/xmlrpc/client.py", line 668, in close
    raise Fault(**self._stack[0])
xmlrpc.client.Fault: <Fault 1: "<class 'OSError'>:[Errno 28] No space left on device">
>>>
```

#### Capture MST (Multi-Stream Transport) DisplayPort
To support the MST in the DisplayPort, chameleon has the contradistinction
between pluggable logical port, called root port and with ports representing the
additional streams, called child of root port.  
Stream 0 of MST is the root port and plugging it with the Plug function will
result in a single stream. To connect multiple streams, the user has to use the
new function `PlugWithChildren` with arguments of root port and array of children
ports identifiers. Root port can be plugged without children, making the port
a single stream, but children cannot be plugged without root port.  
All of the ports, root and children, can have different EDIDs. All EDIDs must
be set before calling the `PlugWithChildren` function.  
Hot plug detection for the whole MST chain is controlled by the connection state
of a root port.  
Calling the `Unplug` function on a root port makes all, the root and children
ports to be unplugged together.

EDIDs must be applied to all, root and children ports before calling the
`PlugWithChildren` function.

**Note**: if DUT shows less streams than plugged, that may mean the DUT is not
supporting such number of streams or that the total bandwidth of link is lower
than bandwidth required for all streams.

```
>>> p.ApplyEdid(5, 0)
>>> p.ApplyEdid(6, 0)
>>> p.PlugWithChildren(5, [6])
>>> p.WaitVideoInputStable(5, 10)
True
>>> p.WaitVideoInputStable(6, 10)
True
>>> with open("frame_mst0.rgb", "wb") as f:
...     f.write(p.DumpPixels(5).data)
...
6220800
>>> with open("frame_mst1.rgb", "wb") as f:
...     f.write(p.DumpPixels(6).data)
...
6220800
>>> p.IsPlugged(5)
True
>>> p.IsPlugged(6)
True
>>> p.Unplug(5)
>>> p.IsPlugged(5)
False
>>> p.IsPlugged(6)
False
>>>
```
