/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>

#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <poll.h>
#include <signal.h>
#include <time.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <linux/videodev2.h>
#include <jpeglib.h>

#define MAX_BUFS 4
#define MAX_CLIENTS 8
#define SRV_PORT 8080

struct buffer {
	unsigned char *mem;
	int index;
};

struct video {
	int fd;
	int width, height;
	int size;
	int nbufs;
	struct buffer bufs[MAX_BUFS];
};

struct server {
	int fd;
	int cli_fd[MAX_CLIENTS];
};

struct jpg {
	unsigned long size;
	unsigned char *mem;
};

#define status \
	"HTTP/1.0 200 OK\r\n"
#define boundary \
	"--jpgboundary\r\n"
#define multipart \
	"Content-Type: multipart/x-mixed-replace;boundary=" boundary "\r\n"
#define content_fmt \
	"Content-Type: image/jpeg\r\n" \
	"Content-Length: %ul\r\n" \
	"\r\n"

void error(char *msg)
{
	fprintf(stderr, "error: ");
	if (errno)
		perror(msg);
	else
		fprintf(stderr, "%s\n", msg);
	exit(1);
}

void encode(struct video *vid, struct buffer *buf, struct jpg *jpg)
{
	struct jpeg_compress_struct cinfo;
	struct jpeg_error_mgr jerr;
	JSAMPROW rows[1];

	jpg->mem = NULL;
	cinfo.err = jpeg_std_error(&jerr);

	jpeg_create_compress(&cinfo);
	cinfo.image_width  = vid->width;
	cinfo.image_height = vid->height;
	cinfo.input_components = 4;
	cinfo.in_color_space = JCS_EXT_BGRX;
	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, 100, TRUE);
	cinfo.comp_info[0].h_samp_factor = 1;
	cinfo.comp_info[0].v_samp_factor = 1;
	jpeg_mem_dest(&cinfo, &jpg->mem, &jpg->size);

	rows[0] = buf->mem;
	jpeg_start_compress(&cinfo, TRUE);
	while (cinfo.next_scanline < cinfo.image_height) {
		jpeg_write_scanlines(&cinfo, rows, 1);
		rows[0] += vid->width * 4;
	}
	jpeg_finish_compress(&cinfo);
	jpeg_destroy_compress(&cinfo);
}

int send_header(int fd)
{
	if (write(fd, status, strlen(status)) == -1)
		return -1;
	if (write(fd, multipart, strlen(multipart)) == -1)
		return -1;
	return 0;
}

int send_jpg(int fd, struct jpg *jpg)
{
	char content_buf[100];
	int content_len;
	content_len = sprintf(content_buf, content_fmt, jpg->size);

	if (write(fd, content_buf, content_len) == -1)
		return -1;
	if (write(fd, jpg->mem, jpg->size) == -1)
		return -1;
	if (write(fd, boundary, strlen(boundary)) == -1)
		return -1;
	if (write(fd, status, strlen(status)) == -1)
		return -1;
	return 0;
}

void ignore_sigpipe(void)
{
	struct sigaction sig = { .sa_handler = SIG_IGN };
	if (sigaction(SIGPIPE, &sig, NULL))
		error("sigaction");
}

void open_video(struct video *vid)
{
	struct v4l2_format fmt  = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };
	struct v4l2_buffer vbuf = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };
	struct v4l2_requestbuffers req = {
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
		.memory = V4L2_MEMORY_MMAP,
		.count = MAX_BUFS };
	int i;

	if ((vid->fd = open("/dev/video0", O_RDWR)) == -1)
		error("open");
	if (ioctl(vid->fd, VIDIOC_G_FMT, &fmt) == -1)
		error("vidioc_g_fmt");
	vid->width = fmt.fmt.pix.width;
	vid->height = fmt.fmt.pix.height;
	vid->size = vid->width * vid->height * 4;

	if (ioctl(vid->fd, VIDIOC_REQBUFS, &req) == -1)
		error("reqbufs");
	if (req.count == 0)
		error("no buffers");
	vid->nbufs = req.count;

	for (i = 0; i < vid->nbufs; i++) {
		vbuf.index = i;
		if (ioctl(vid->fd, VIDIOC_QUERYBUF, &vbuf) == -1)
			error("vidioc_querybuf");
		if (vbuf.length != vid->size)
			error("buffer size mismatch");
		vid->bufs[i].mem = mmap(NULL,
		    vbuf.length,
		    PROT_READ | PROT_WRITE,
		    MAP_SHARED,
		    vid->fd,
		    vbuf.m.offset);
		if (vid->bufs[i].mem == MAP_FAILED)
			error("mmap");
		vid->bufs[i].index = i;
	}
}

void enqueue(struct video *vid, struct buffer *buf)
{
	struct v4l2_buffer vbuf = {
		.index = buf->index,
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
		.memory = V4L2_MEMORY_MMAP };

	if (ioctl(vid->fd, VIDIOC_QBUF, &vbuf) == -1)
		error("vidioc_qbuf");
}

struct buffer *dequeue(struct video *vid)
{
	struct v4l2_buffer vbuf = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };
	struct buffer *buf;
	if (ioctl(vid->fd, VIDIOC_DQBUF, &vbuf) == -1)
		error("vidioc_dqbuf");
	if (vbuf.index >= vid->nbufs)
		error("vidioc_dqbuf: index out of range");
	buf = &vid->bufs[vbuf.index];
	return buf;
}

void start_video(struct video *vid)
{
	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	if (ioctl(vid->fd, VIDIOC_STREAMON, &type) == -1)
		error("streamon");
}

void start_server(struct server *srv)
{
	struct sockaddr_in addr;

	if ((srv->fd = socket(AF_INET, SOCK_STREAM, 0)) == -1)
		error("socket");

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = INADDR_ANY;
	addr.sin_port = htons(SRV_PORT);

	if (bind(srv->fd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
		error("bind");
	if (listen(srv->fd, 5) == -1)
		error("listen");
	memset(srv->cli_fd, 0, sizeof(srv->cli_fd));
}

void send_to_all(struct server *srv, struct jpg *jpg)
{
	int res;
	int i;

	for (i = 0; i < MAX_CLIENTS; i++) {
		if (srv->cli_fd[i])
			res = send_jpg(srv->cli_fd[i], jpg);
			if (res == -1)
				srv->cli_fd[i] = 0;
	}
}

void accept_client(struct server *srv)
{
	struct sockaddr_in addr;
	socklen_t addr_len;
	int fd;
	int i;

	for (i = 0; i < MAX_CLIENTS; i++)
		if (!srv->cli_fd[i])
			break;
	if (i == MAX_CLIENTS)
		return;

	addr_len = sizeof(addr);
	fd = accept(srv->fd, (struct sockaddr *)&addr, &addr_len);
	if (fd == -1)
		error("accept");
	if (send_header(fd) != -1)
		srv->cli_fd[i] = fd;
}

int main(void)
{
	struct video vid;
	struct server srv;
	struct buffer *buf;
	struct jpg jpg;
	struct pollfd fds[2];
	int i;

	ignore_sigpipe();
	open_video(&vid);

	for (i = 0; i < vid.nbufs; i++)
		enqueue(&vid, &vid.bufs[i]);

	start_video(&vid);
	start_server(&srv);

	fds[0].fd = vid.fd;
	fds[0].events = POLLIN;
	fds[1].fd = srv.fd;
	fds[1].events = POLLIN;

	while (1) {
		if (poll(fds, 2, -1) == -1)
			error("poll");
		if (fds[0].revents & POLLIN) {
			buf = dequeue(&vid);
			encode(&vid, buf, &jpg);
			enqueue(&vid, buf);
			send_to_all(&srv, &jpg);
			free(jpg.mem);
		}
		if (fds[1].revents & POLLIN)
			accept_client(&srv);
	}

	return 0;
}
