/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2024 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * This script is based on V4L2 video capture example. Original license message
 * is in next comment block below.
 *
 * Program is used to test ChameleonV3 kernel driver. It is able to calculate
 * CRC of frames (note that calculating CRC may take more time than gap between
 * frames, so some of them may be missed).
 * The Program can recognize pattern of eight colour bars that are moving to
 * the left pixel by pixel. It can detect if stream is consistent and if no
 * frame is missed.
 */

/*
 *  V4L2 video capture example
 *
 *  This program can be used and distributed without restrictions.
 *
 *      This program is provided with the V4L2 API
 * see https://linuxtv.org/docs.php for more information
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include <time.h>
#include <zlib.h>

#include <getopt.h>             /* getopt_long() */

#include <fcntl.h>              /* low-level i/o */
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/ioctl.h>

#include <linux/videodev2.h>

#define CLEAR(x) memset(&(x), 0, sizeof(x))

enum io_method {
	IO_METHOD_READ,
	IO_METHOD_MMAP,
	IO_METHOD_USERPTR,
};

struct buffer {
	void   *start;
	size_t  length;
};

static char            *dev_name;
static enum io_method   io = IO_METHOD_MMAP;
static int              fd = -1;
struct buffer          *buffers;
static unsigned int     n_buffers;
static int              out_buf;
static int              do_crc;
static int              do_color_bar;
static int              pixel_format;
static int              frame_count = 70;
static int              error_count = -1;
static int              random_count;

static int              img_w;
static int              img_h;
static int              img_pixels;

static void errno_exit(const char *s)
{
	fprintf(stderr, "%s error %d, %s\n", s, errno, strerror(errno));
	exit(EXIT_FAILURE);
}

static int xioctl(int fh, int request, void *arg)
{
	int r;

	do {
		r = ioctl(fh, request, arg);
	} while (r == -1 && errno == EINTR);

	return r;
}

struct color {
	uint8_t r;
	uint8_t g;
	uint8_t b;
};

/* Colors of bars */
static struct color bars[8] = {
	{ 0xff, 0xff, 0xff, },
	{ 0xff, 0xff, 0x00, },
	{ 0x00, 0xff, 0xff, },
	{ 0x00, 0xff, 0x00, },
	{ 0xff, 0x00, 0xff, },
	{ 0xff, 0x00, 0x00, },
	{ 0x00, 0x00, 0xff, },
	{ 0x00, 0x00, 0x00, },
};

enum process_status {
	EXPECTED_FRAME = 0,
	UNEXPECTED_FRAME,
	EXPECTED_FRAME_WITH_SUMMARY,
};

struct pattern_context {
	/* Previous length of the first color bar */
	int prev_fb_len;
	/* Previous color index of the first bar */
	int prev_fb_color;
	/* Number of received frames */
	unsigned int frame_count;
	/* Number of missed frames */
	unsigned int frame_missed;
	/* Number of not expected frames */
	unsigned int frame_err_count;
};

static inline int cmp_color_with_img(const uint8_t *img, int idx,
				     const struct color *col, int pixfmt)
{
	switch (pixfmt) {
	case V4L2_PIX_FMT_RGB24:
		return col->r == img[idx * 3] &&
		       col->g == img[idx * 3 + 1] &&
		       col->b == img[idx * 3 + 2];
		break;
	case V4L2_PIX_FMT_BGRX32:
		return col->r == img[idx * 4 + 2] &&
		       col->g == img[idx * 4 + 1] &&
		       col->b == img[idx * 4];
		break;
	default:
		/* Shouldn't happen. Pixel format is validated before. */
		fprintf(stderr, "Unsupported pixel format 0x%x\n", pixfmt);
		exit(EXIT_FAILURE);
	}
}

static inline int cmp_colors(const struct color *a, const struct color *b)
{
	return a->r == b->r && a->g == b->g && a->b == b->b;
}

static inline void get_color_from_img(const uint8_t *img, int idx,
				      struct color *col, int pixfmt)
{
	switch (pixfmt) {
	case V4L2_PIX_FMT_RGB24:
		col->r = img[idx * 3];
		col->g = img[idx * 3 + 1];
		col->b = img[idx * 3 + 2];
		break;
	case V4L2_PIX_FMT_BGRX32:
		col->r = img[idx * 4 + 2];
		col->g = img[idx * 4 + 1];
		col->b = img[idx * 4];
		break;
	default:
		/* Shouldn't happen. Pixel format is validated before. */
		fprintf(stderr, "Unsupported pixel format 0x%x\n", pixfmt);
		exit(EXIT_FAILURE);
	}
}

static enum process_status check_motion_pattern(
	const void *p, int size, struct pattern_context *ctx)
{
	/* First bar properties */
	int fb_len;
	struct color fb_c;
	int fb_c_idx;
	const uint8_t *img = p;
	enum process_status err = EXPECTED_FRAME;
	int random;
	/* Width of one full color bar in pixels */
	int bar_w = img_w / 8;

	ctx->frame_count++;

	/* Get first bar color */
	get_color_from_img(img, 0, &fb_c, pixel_format);
	/* Look for place where color changes */
	for (fb_len = 1;
	     fb_len < img_w &&
	     cmp_color_with_img(img, fb_len, &fb_c, pixel_format);
	     fb_len++)
		;

	/* Check which color of bar do we have */
	for (fb_c_idx = 0;
	     fb_c_idx < 8 && !cmp_colors(&fb_c, &bars[fb_c_idx]);
	     fb_c_idx++)
		;

	if (fb_c_idx >= 8) {
		/* Unexpected frame */
		ctx->frame_err_count++;
		fprintf(stderr,
			"\nUnexpected bar color [#%02x%02x%02x] width %d\n",
			fb_c.r, fb_c.g, fb_c.b, fb_len);

		return UNEXPECTED_FRAME;
	}

	if (ctx->prev_fb_len == fb_len + 1 || ctx->frame_count == 1) {
		/**
		 * This is the first frame or width of the first bar is
		 * expected
		 */
		if (fb_c_idx != ctx->prev_fb_color && ctx->frame_count != 1) {
			/**
			 * This isn't the first frame and color of the first bar
			 * is unexpected (different than in previous frame).
			 */
			fprintf(stderr,
				"\nUnexpected bar color [#%02x%02x%02x] width %d\n",
				fb_c.r, fb_c.g, fb_c.b, fb_len);
			fprintf(stderr, "Expected bar color [#%02x%02x%02x]\n",
				bars[ctx->prev_fb_color].r,
				bars[ctx->prev_fb_color].g,
				bars[ctx->prev_fb_color].b);
			err = UNEXPECTED_FRAME;
		}
	} else if (fb_len == bar_w) {
		/**
		 * The first bar has maximal width. Expect color change or wrap
		 * around to the first frame with white bar.
		 */
		if (ctx->prev_fb_len == 1 &&
		    fb_c_idx == (ctx->prev_fb_color + 1) % 8) {
			/* Expected color change */
		} else if (fb_c_idx == 0) {
			/* Wrap around back to the first frame with white bar */
			fprintf(stderr,
				"\nExpected bar color [#%02x%02x%02x] wrap\n",
				fb_c.r, fb_c.g, fb_c.b, fb_len);
			err = EXPECTED_FRAME_WITH_SUMMARY;
		} else {
			/**
			 * The first bar is not white (indication of wrap
			 * around) and is not expected next color
			 */
			fprintf(stderr,
				"\nUnexpected bar color [#%02x%02x%02x] width %d\n",
				fb_c.r, fb_c.g, fb_c.b, fb_len);
			fprintf(stderr,
				"Expected bar color [#%02x%02x%02x] or white\n",
				bars[(ctx->prev_fb_color + 1) % 8].r,
				bars[(ctx->prev_fb_color + 1) % 8].g,
				bars[(ctx->prev_fb_color + 1) % 8].b);
			err = UNEXPECTED_FRAME;
		}
	} else {
		/* Unexpected frame */
		if (ctx->prev_fb_color == fb_c_idx)
			/* We can count how many frames where missed */
			ctx->frame_missed += ctx->prev_fb_len - (fb_len + 1);
		fprintf(stderr,
			"\nExpected bar width %d, got %d [#%02x%02x%02x]\n",
			ctx->prev_fb_len - 1, fb_len, fb_c.r, fb_c.g, fb_c.b);
		fprintf(stderr, "Expected bar color [#%02x%02x%02x]\n",
			bars[ctx->prev_fb_color].r,
			bars[ctx->prev_fb_color].g,
			bars[ctx->prev_fb_color].b);
		err = UNEXPECTED_FRAME;
	}

	for (random = random_count; random > 0; random--) {
		int idx = rand() % img_pixels;
		/**
		 * Calculate expected color of the pixel at the idx. Calculate
		 * offset from the first frame (white bar with max width)
		 * by adding current offset (bar_w - fb_len), dividing it
		 * by number of pixels per color bar (bar_w) and adding current
		 * first bar color. Modulo 8 is there, because colors alternate
		 * in sequence.
		 */
		int expect_c = ((idx + bar_w - fb_len) / bar_w + fb_c_idx) % 8;

		if (!cmp_color_with_img(img, idx, &bars[expect_c],
					pixel_format)) {
			/* fb_c is no longer in use, save color there */
			get_color_from_img(img, idx, &fb_c, pixel_format);
			fprintf(stderr,
				"Expected pixel color [#%02x%02x%02x]\n",
				bars[expect_c].r, bars[expect_c].g,
				bars[expect_c].b);
			fprintf(stderr, "Got pixel color [#%02x%02x%02x]\n",
				fb_c.r, fb_c.g, fb_c.b);
			fprintf(stderr, "idx %d (%d x %d) expect_c %d\n",
				idx, idx % img_w, idx / img_w, expect_c);
			err = UNEXPECTED_FRAME;
		}
	}

	ctx->prev_fb_len = fb_len;
	ctx->prev_fb_color = fb_c_idx;
	if (err == UNEXPECTED_FRAME)
		ctx->frame_err_count++;

	return err;
}
static unsigned int calculate_crc(const void *p, int size)
{
	const unsigned char *img = p;
	unsigned int crc = crc32(0, NULL, 0);

	return crc32(crc, img, size);
}

static void save_frame_to_file(const char *name, const void *img, int img_len)
{
	FILE *f = fopen(name, "wb");

	if (f == NULL) {
		fprintf(stderr, "Cannot create file \"%s\"\n", name);
		return;
	}

	fwrite(img, 1, img_len, f);

	fclose(f);
}

static int create_frame_file_name(char *name, int name_len,
				  struct pattern_context *ctx)
{
	const char *pixel_format_name;
	time_t current_time;
	struct tm *time_info;
	int written;

	time(&current_time);
	time_info = localtime(&current_time);

	written = strftime(name, name_len, "%H-%M-%S", time_info);
	if (written == 0) {
		fprintf(stderr, "Cannot create file name\n");
		return 1;
	}

	switch (pixel_format) {
	case V4L2_PIX_FMT_RGB24:
		pixel_format_name = "RGB3";
		break;
	case V4L2_PIX_FMT_BGRX32:
		pixel_format_name = "XR24";
		break;
	default:
		pixel_format_name = "UNK";
		break;
	}

	written = snprintf(name + written, name_len - written,
			   "%dx%d-%s-count-%d-errors-%d", img_w, img_h,
			   pixel_format_name, ctx->frame_count,
			   ctx->frame_err_count);

	if (written < 0)
		return written;

	return 0;
}

static enum process_status process_image(const void *p, int size)
{
	static struct pattern_context ctx = {
		.prev_fb_len = -1,
		.prev_fb_color = -1,
		.frame_count = 0,
		.frame_err_count = 0,
		.frame_missed = 0,
	};
	enum process_status err;

	if (do_crc)
		fprintf(stdout, "0x%x\n", calculate_crc(p, size));

	if (do_color_bar) {
		err = check_motion_pattern(p, size, &ctx);
		if (err != EXPECTED_FRAME) {
			fprintf(stderr, "Frame count %d; Error count %d\n",
				ctx.frame_count, ctx.frame_err_count);
			fprintf(stderr, "Frame missed %d\n",
				ctx.frame_missed);
			if (out_buf && err == UNEXPECTED_FRAME) {
				char file_name[50];

				if (!create_frame_file_name(file_name,
							    sizeof(file_name),
							    &ctx))
					save_frame_to_file(file_name, p, size);
			}
			return err;
		}
	}

	fprintf(stderr, ".");

	return EXPECTED_FRAME;
}

static int read_frame(void)
{
	static struct timeval prev_frame = { 0 };
	struct v4l2_buffer buf;
	unsigned int i;
	enum process_status proc_err;
	const void *img;
	int img_len;

	switch (io) {
	case IO_METHOD_READ:
		if (read(fd, buffers[0].start, buffers[0].length) == -1) {
			switch (errno) {
			case EAGAIN:
				return 0;

			case EIO:
				/* Could ignore EIO, see spec. */

				/* fall through */

			default:
				errno_exit("read");
			}
		}

		img = buffers[0].start;
		img_len = buffers[0].length;
		break;

	case IO_METHOD_MMAP:
		CLEAR(buf);

		buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		buf.memory = V4L2_MEMORY_MMAP;

		if (xioctl(fd, VIDIOC_DQBUF, &buf) == -1) {
			switch (errno) {
			case EAGAIN:
				return 0;

			case EIO:
				/* Could ignore EIO, see spec. */

				/* fall through */

			default:
				errno_exit("VIDIOC_DQBUF");
			}
		}

		assert(buf.index < n_buffers);

		img = buffers[buf.index].start;
		img_len = buf.bytesused;
		break;

	case IO_METHOD_USERPTR:
		CLEAR(buf);

		buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		buf.memory = V4L2_MEMORY_USERPTR;

		if (xioctl(fd, VIDIOC_DQBUF, &buf) == -1) {
			switch (errno) {
			case EAGAIN:
				return 0;

			case EIO:
				/* Could ignore EIO, see spec. */

				/* fall through */

			default:
				errno_exit("VIDIOC_DQBUF");
			}
		}

		for (i = 0; i < n_buffers; ++i)
			if (buf.m.userptr == (unsigned long)buffers[i].start
			    && buf.length == buffers[i].length)
				break;

		assert(i < n_buffers);

		img = (void *)buf.m.userptr;
		img_len = buf.bytesused;
		break;
	}

	proc_err = process_image(img, img_len);
	if (proc_err != EXPECTED_FRAME) {
		/* Catch unexpected frames and expected frames with summary */
		fprintf(stderr,
			"time between frames %d us (timestamp %ds %dus, seq %d)\n",
			(buf.timestamp.tv_sec - prev_frame.tv_sec) * 1000000 +
			(buf.timestamp.tv_usec - prev_frame.tv_usec),
			buf.timestamp.tv_sec,
			buf.timestamp.tv_usec,
			buf.sequence
			);
		if (proc_err == UNEXPECTED_FRAME) {
			fprintf(stdout, "ERROR\n");
			if (error_count != -1) {
				if (error_count-- <= 0) {
					fprintf(stderr,
						"Maximum error number\n");
					exit(EXIT_FAILURE);
				}
			}
		}
	}

	prev_frame.tv_usec = buf.timestamp.tv_usec;
	prev_frame.tv_sec = buf.timestamp.tv_sec;

	/* Post processing operation */
	switch (io) {
	case IO_METHOD_READ:
		break;

	case IO_METHOD_MMAP:
		if (xioctl(fd, VIDIOC_QBUF, &buf) == -1)
			errno_exit("VIDIOC_QBUF");
		break;

	case IO_METHOD_USERPTR:
		if (xioctl(fd, VIDIOC_QBUF, &buf) == -1)
			errno_exit("VIDIOC_QBUF");
		break;
	}

	fflush(stderr);
	fflush(stdout);

	return 1;
}

static void mainloop(void)
{
	unsigned int count;

	count = frame_count;

	while (count-- > 0) {
		for (;;) {
			fd_set fds;
			struct timeval tv;
			int r;

			FD_ZERO(&fds);
			FD_SET(fd, &fds);

			/* Timeout. */
			tv.tv_sec = 2;
			tv.tv_usec = 0;

			r = select(fd + 1, &fds, NULL, NULL, &tv);

			if (r == -1) {
				if (errno == EINTR)
					continue;
				errno_exit("select");
			}

			if (r == 0) {
				fprintf(stderr, "select timeout\n");
				exit(EXIT_FAILURE);
			}

			if (read_frame())
				break;
			/* EAGAIN - continue select loop. */
		}
	}
}

static void stop_capturing(void)
{
	enum v4l2_buf_type type;

	switch (io) {
	case IO_METHOD_READ:
		/* Nothing to do. */
		break;

	case IO_METHOD_MMAP:
	case IO_METHOD_USERPTR:
		type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		if (xioctl(fd, VIDIOC_STREAMOFF, &type) == -1)
			errno_exit("VIDIOC_STREAMOFF");
		break;
	}
}

static void start_capturing(void)
{
	unsigned int i;
	enum v4l2_buf_type type;

	switch (io) {
	case IO_METHOD_READ:
		/* Nothing to do. */
		break;

	case IO_METHOD_MMAP:
		for (i = 0; i < n_buffers; ++i) {
			struct v4l2_buffer buf;

			CLEAR(buf);
			buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
			buf.memory = V4L2_MEMORY_MMAP;
			buf.index = i;

			if (xioctl(fd, VIDIOC_QBUF, &buf) == -1)
				errno_exit("VIDIOC_QBUF");
		}
		type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		if (xioctl(fd, VIDIOC_STREAMON, &type) == -1)
			errno_exit("VIDIOC_STREAMON");
		break;

	case IO_METHOD_USERPTR:
		for (i = 0; i < n_buffers; ++i) {
			struct v4l2_buffer buf;

			CLEAR(buf);
			buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
			buf.memory = V4L2_MEMORY_USERPTR;
			buf.index = i;
			buf.m.userptr = (unsigned long)buffers[i].start;
			buf.length = buffers[i].length;

			if (xioctl(fd, VIDIOC_QBUF, &buf) == -1)
				errno_exit("VIDIOC_QBUF");
		}
		type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		if (xioctl(fd, VIDIOC_STREAMON, &type) == -1)
			errno_exit("VIDIOC_STREAMON");
		break;
	}
}

static void uninit_device(void)
{
	unsigned int i;

	switch (io) {
	case IO_METHOD_READ:
		free(buffers[0].start);
		break;

	case IO_METHOD_MMAP:
		for (i = 0; i < n_buffers; ++i)
			if (munmap(buffers[i].start, buffers[i].length) == -1)
				errno_exit("munmap");
		break;

	case IO_METHOD_USERPTR:
		for (i = 0; i < n_buffers; ++i)
			free(buffers[i].start);
		break;
	}

	free(buffers);
}

static void init_read(unsigned int buffer_size)
{
	buffers = calloc(1, sizeof(*buffers));

	if (!buffers) {
		fprintf(stderr, "Out of memory\n");
		exit(EXIT_FAILURE);
	}

	buffers[0].length = buffer_size;
	buffers[0].start = malloc(buffer_size);

	if (!buffers[0].start) {
		fprintf(stderr, "Out of memory\n");
		exit(EXIT_FAILURE);
	}
}

static void init_mmap(void)
{
	struct v4l2_requestbuffers req;

	CLEAR(req);

	req.count = 16;
	req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	req.memory = V4L2_MEMORY_MMAP;

	if (xioctl(fd, VIDIOC_REQBUFS, &req) == -1) {
		if (errno == EINVAL) {
			fprintf(stderr, "%s does not support memory mappingn",
				dev_name);
			exit(EXIT_FAILURE);
		} else {
			errno_exit("VIDIOC_REQBUFS");
		}
	}

	if (req.count < 2) {
		fprintf(stderr, "Insufficient buffer memory on %s\n",
			 dev_name);
		exit(EXIT_FAILURE);
	}

	buffers = calloc(req.count, sizeof(*buffers));

	if (!buffers) {
		fprintf(stderr, "Out of memory\n");
		exit(EXIT_FAILURE);
	}

	for (n_buffers = 0; n_buffers < req.count; ++n_buffers) {
		struct v4l2_buffer buf;

		CLEAR(buf);

		buf.type	= V4L2_BUF_TYPE_VIDEO_CAPTURE;
		buf.memory      = V4L2_MEMORY_MMAP;
		buf.index       = n_buffers;

		if (xioctl(fd, VIDIOC_QUERYBUF, &buf) == -1)
			errno_exit("VIDIOC_QUERYBUF");

		buffers[n_buffers].length = buf.length;
		buffers[n_buffers].start =
			mmap(NULL /* start anywhere */,
			      buf.length,
			      PROT_READ | PROT_WRITE /* required */,
			      MAP_SHARED /* recommended */,
			      fd, buf.m.offset);

		if (buffers[n_buffers].start == MAP_FAILED)
			errno_exit("mmap");
	}
}

static void init_userp(unsigned int buffer_size)
{
	struct v4l2_requestbuffers req;

	CLEAR(req);

	req.count  = 24;
	req.type   = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	req.memory = V4L2_MEMORY_USERPTR;

	if (xioctl(fd, VIDIOC_REQBUFS, &req) == -1) {
		if (errno == EINVAL) {
			fprintf(stderr,
				"%s does not support user pointer i/on",
				dev_name);
			exit(EXIT_FAILURE);
		} else {
			errno_exit("VIDIOC_REQBUFS");
		}
	}

	buffers = calloc(4, sizeof(*buffers));

	if (!buffers) {
		fprintf(stderr, "Out of memory\n");
		exit(EXIT_FAILURE);
	}

	for (n_buffers = 0; n_buffers < 4; ++n_buffers) {
		buffers[n_buffers].length = buffer_size;
		buffers[n_buffers].start = malloc(buffer_size);

		if (!buffers[n_buffers].start) {
			fprintf(stderr, "Out of memory\n");
			exit(EXIT_FAILURE);
		}
	}
}

static void init_device(void)
{
	struct v4l2_capability cap;
	struct v4l2_cropcap cropcap;
	struct v4l2_crop crop;
	struct v4l2_format fmt;
	unsigned int min;

	if (xioctl(fd, VIDIOC_QUERYCAP, &cap) == -1) {
		if (errno == EINVAL) {
			fprintf(stderr, "%s is no V4L2 device\n",
				 dev_name);
			exit(EXIT_FAILURE);
		} else {
			errno_exit("VIDIOC_QUERYCAP");
		}
	}

	if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
		fprintf(stderr, "%s is no video capture device\n",
			 dev_name);
		exit(EXIT_FAILURE);
	}

	switch (io) {
	case IO_METHOD_READ:
		if (!(cap.capabilities & V4L2_CAP_READWRITE)) {
			fprintf(stderr, "%s does not support read i/o\n",
				 dev_name);
			exit(EXIT_FAILURE);
		}
		break;

	case IO_METHOD_MMAP:
	case IO_METHOD_USERPTR:
		if (!(cap.capabilities & V4L2_CAP_STREAMING)) {
			fprintf(stderr, "%s does not support streaming i/o\n",
				 dev_name);
			exit(EXIT_FAILURE);
		}
		break;
	}


	/* Select video input, video standard and tune here. */


	CLEAR(cropcap);

	cropcap.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;

	if (xioctl(fd, VIDIOC_CROPCAP, &cropcap) == 0) {
		crop.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		crop.c = cropcap.defrect; /* reset to default */

		if (xioctl(fd, VIDIOC_S_CROP, &crop) == -1) {
			switch (errno) {
			case EINVAL:
				/* Cropping not supported. */
				break;
			default:
				/* Errors ignored. */
				break;
			}
		}
	} else {
		/* Errors ignored. */
	}


	CLEAR(fmt);

	fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	fmt.fmt.pix.width       = 640;
	fmt.fmt.pix.height      = 480;
	fmt.fmt.pix.pixelformat = pixel_format;
	fmt.fmt.pix.field       = V4L2_FIELD_INTERLACED;

	if (xioctl(fd, VIDIOC_S_FMT, &fmt) == -1)
		errno_exit("VIDIOC_S_FMT");

	/* Note VIDIOC_S_FMT may change width and height. */

	/* Buggy driver paranoia. */
	min = fmt.fmt.pix.width * 2;
	if (fmt.fmt.pix.bytesperline < min)
		fmt.fmt.pix.bytesperline = min;
	min = fmt.fmt.pix.bytesperline * fmt.fmt.pix.height;
	if (fmt.fmt.pix.sizeimage < min)
		fmt.fmt.pix.sizeimage = min;
	img_w = fmt.fmt.pix.width;
	img_h = fmt.fmt.pix.height;
	img_pixels = img_w * img_h;

	switch (io) {
	case IO_METHOD_READ:
		init_read(fmt.fmt.pix.sizeimage);
		break;

	case IO_METHOD_MMAP:
		init_mmap();
		break;

	case IO_METHOD_USERPTR:
		init_userp(fmt.fmt.pix.sizeimage);
		break;
	}
}

static void close_device(void)
{
	if (close(fd) == -1)
		errno_exit("close");

	fd = -1;
}

static void open_device(void)
{
	struct stat st;

	if (stat(dev_name, &st) == -1) {
		fprintf(stderr, "Cannot identify '%s': %d, %s\n",
			 dev_name, errno, strerror(errno));
		exit(EXIT_FAILURE);
	}

	if (!S_ISCHR(st.st_mode)) {
		fprintf(stderr, "%s is no devicen", dev_name);
		exit(EXIT_FAILURE);
	}

	fd = open(dev_name, O_RDWR /* required */ | O_NONBLOCK, 0);

	if (fd == -1) {
		fprintf(stderr, "Cannot open '%s': %d, %s\n",
			 dev_name, errno, strerror(errno));
		exit(EXIT_FAILURE);
	}
}

static void usage(FILE *fp, int argc, char **argv)
{
	fprintf(fp,
		 "Usage: %s [options]\n\n"
		 "Version 1.3\n"
		 "Options:\n"
		 "-d | --device name   Video device name [%s]\n"
		 "-h | --help          Print this message\n"
		 "-m | --mmap          Use memory mapped buffers [default]\n"
		 "-r | --read          Use read() calls\n"
		 "-u | --userp         Use application allocated buffers\n"
		 "-o | --output        Save error frame to file\n"
		 "-f | --format        Select format [RGB3|RX24]\n"
		 "-c | --count         Number of frames to grab [%i]\n"
		 "-C | --crc           Print frame zlib CRC32 to stdout\n"
		 "                     NOTE: Calculations take time and some\n"
		 "                           frames maybe missed\n"
		 "-e | --error         Number of wrong frames required\n"
		 "                     to stop program [%i]\n"
		 "-M | --motion	Expect color bars pattern stream.\n"
		 "                     Pattern has 8 vertical color bars\n"
		 "                     unifromly distributed across a screen.\n"
		 "                     In next frame, the first column on\n"
		 "                     the left is moved to the right.\n"
		 "-R | --random num    Check random pixels in motion pattern.\n"
		 "",
		 argv[0], dev_name, frame_count, error_count);
}

static const char short_options[] = "d:hmruof:c:Ce:MR:";

static const struct option
long_options[] = {
	{ "device", required_argument, NULL, 'd' },
	{ "help",   no_argument,       NULL, 'h' },
	{ "mmap",   no_argument,       NULL, 'm' },
	{ "read",   no_argument,       NULL, 'r' },
	{ "userp",  no_argument,       NULL, 'u' },
	{ "output", no_argument,       NULL, 'o' },
	{ "format", required_argument, NULL, 'f' },
	{ "count",  required_argument, NULL, 'c' },
	{ "crc",    no_argument,       NULL, 'C' },
	{ "error",  required_argument, NULL, 'e' },
	{ "motion", required_argument, NULL, 'M' },
	{ "random", required_argument, NULL, 'R' },
	{ 0, 0, 0, 0 }
};

int main(int argc, char **argv)
{
	dev_name = "/dev/video0";
	pixel_format = V4L2_PIX_FMT_RGB24;

	srand(time(NULL));

	for (;;) {
		int idx;
		int c;

		c = getopt_long(argc, argv,
				short_options, long_options, &idx);

		if (c == -1)
			break;

		switch (c) {
		case 0: /* getopt_long() flag */
			break;

		case 'd':
			dev_name = optarg;
			break;

		case 'h':
			usage(stdout, argc, argv);
			exit(EXIT_SUCCESS);

		case 'm':
			io = IO_METHOD_MMAP;
			break;

		case 'r':
			io = IO_METHOD_READ;
			break;

		case 'u':
			io = IO_METHOD_USERPTR;
			break;

		case 'o':
			out_buf++;
			break;

		case 'f':
			if (strcmp("RGB3", optarg) == 0) {
				pixel_format = V4L2_PIX_FMT_RGB24;
			} else if (strcmp("RX24", optarg) == 0) {
				pixel_format = V4L2_PIX_FMT_BGRX32;
			} else {
				fprintf(stderr, "Unknown pixel format \"%s\"\n",
					optarg);
				exit(EXIT_FAILURE);
			}
			break;

		case 'c':
			errno = 0;
			frame_count = strtol(optarg, NULL, 0);
			if (errno)
				errno_exit(optarg);
			break;

		case 'C':
			do_crc++;
			break;

		case 'e':
			errno = 0;
			error_count = strtol(optarg, NULL, 0);
			if (errno)
				errno_exit(optarg);
			break;

		case 'M':
			do_color_bar++;
			break;

		case 'R':
			errno = 0;
			random_count = strtol(optarg, NULL, 0);
			if (errno)
				errno_exit(optarg);
			break;

		default:
			usage(stderr, argc, argv);
			exit(EXIT_FAILURE);
		}
	}

	open_device();
	init_device();
	start_capturing();
	mainloop();
	stop_capturing();
	uninit_device();
	close_device();
	fprintf(stderr, "\n");
	return 0;
}
