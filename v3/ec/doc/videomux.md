# Video Mux Routing

The Chameleon v3 has two HDMI and two DisplayPort connectors. The video
signals for each of these connectors can be routed through a sequence of
demuxes and muxes to connect the port to the FPGA's Multi-Gigabit Transceivers
(MGTs) or to an IT68051 HDMI receiver. Note that the DisplayPort signals pass
through an MCDP2900 DisplayPort to HDMI converter if they are being routed to
the IT68051 HDMI receiver.

The signal routing from connector to FPGA and HDMI receiver can be seen
in this diagram. The control signals for the demuxes and muxes are shown
by each demux/mux.

![Video Mux Routing](images/videomux.png "Video Mux Routing")

Note that the ports are numbered externally as ports 1 and 2 (with HDMI1 and
DP1 being closest to the USB-C connectors), but that the routing to the
IT68051 receiver is HDMI1/DP1 to port **1**, while HDMI2/DP2 are routed to
port **0**.

The table below shows the routing for DP1 and DP2, with the reference
designators for the muxes and demuxes shown in the same order.
For example, to route DP1 to the IT68051, set the select line on U3 (which is
`DP1_PS8468_SW`) to 0, set the select line on U18 (which is
`GP213_IT68051P1_CH_SEL`) to 0, and don't bother with the select line on U11.

```
U3/U22      U18/U31     U11/U14     DP1/DP2 connection
------      -------     -------     ------------------
0           0           x           IT68051
1           x           0           FPGA
```

This table shows the routing for HDMI1 and HDMI2, with the reference
designators for the demuxes and muxes shown in the same order.
For example, to route HDMI2 to the FPGA, set the select line on U29 (which
is `HDMI2_GP213_CH_SEL`) to 1, don't bother with U31, and set the select line
on U14 (which is `SOMP2_MODE_SEL`) to 1.

```
U10/U29     U18/U31     U11/U14     HDMI1/HDMI2 connection
------      -------     -------     ----------------------
0           1           x           IT68051
1           x           1           FPGA
```

Note that U3 and U22 play no part in the HDMI signal routing, while U10 and U29
play no part in the DisplayPort signal routing.

Only one of HDMI1 and DP1 can be connected to the FPGA. The other can be
connected to the IT68051, or it can be left unconnected. The same restriction
applies to HDMI2 and DP2.

## Shell Commands

The `videomux` shell command offers a way to read and set the state of the
muxes and demuxes. `videomux get` will read the select signals for all 8
of the chips that involved in demuxing and muxing the signals and report
them as raw 0 and 1. It will then interpret those signals to show the routing
for the DisplayPort and HDMI connections to the HDMI receiver and the
FPGA MGTs:
```
$ videomux get
U3:0 U10:1 U11:1 U18:0 U22:0 U29:1 U31:0 U14:1
DP1: HDMI RX
DP2: HDMI RX
HDMI1: FPGA
HDMI2: FPGA
```

To set the muxes and demuxes, use the `videomux` command, specify the port
as `dp1`, `dp2`, `hdmi1`, or `hdmi2`, and the destination of `fpga` or `rx`
(the IT68051  HDMI receiver). So, for example:
```
$ videomux dp1 fpga
Connect DP1 to FPGA
$ videomux get
U3:1 U10:1 U11:0 U18:0 U22:0 U29:1 U31:0 U14:1
DP1: FPGA
DP2: HDMI RX
HDMI1: n/c
HDMI2: FPGA
```
