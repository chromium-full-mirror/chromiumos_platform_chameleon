## V4L2 MJPEG Server

This program streams video from a V4L2 device using mmap, compresses
each frame using libjpeg, starts a server, and sends an HTTP multipart
MJPEG stream to each of its clients.

Only BGR32 format is supported right now.

## Building

First, install libjpeg. On chameleon, run `pacman -S libjpeg-turbo`
as root.

Then, run `make` to compile the program. A make utility and a C compiler
should already be installed on the chameleon rootfs.
