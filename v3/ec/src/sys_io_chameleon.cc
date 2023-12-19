/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Uses some patterns from subsys/console/getchar.c
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/console/tty.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/logging/log.h>

#include "pw_sys_io/sys_io.h"

LOG_MODULE_REGISTER(sys_io);

/**
 * Device pointer for the UART
 */
static const struct device *uart_dev = DEVICE_DT_GET(DT_NODELABEL(usart2));

/**
 * TTY data structure
 */
static struct tty_serial tty;

/**
 * RX buffer size
 */
static const uint32_t RX_BUFSIZE = 1024;

/**
 * TX buffer size
 */
static const uint32_t TX_BUFSIZE = 1024;

/**
 * RX buffer
 */
static uint8_t rx_buf[RX_BUFSIZE];

/**
 * TX buffer
 */
static uint8_t tx_buf[TX_BUFSIZE];

/**
 * Subsys initialization flag
 */
bool initialized = false;

/**
 * @brief Initialize the UART device that sys_io needs
 *
 * @retval 0
 * No error
 */
static int sys_io_init(void)
{
	/*
	 * Make sure the UART device is ready. No need to configure it
	 * beyond that, because the values in the DTS are all good.
	 */
	if (!device_is_ready(uart_dev)) {
		LOG_ERR("%s is not ready", uart_dev->name);
		return -EINVAL;
	}

	int ret = tty_init(&tty, uart_dev);

	if (ret != 0) {
		LOG_ERR("tty_init failed, %d", ret);
		return ret;
	}

	/* Ensure device driver supports interrupt-driven data transfers. */
	const struct uart_driver_api *api =
		(const struct uart_driver_api *)uart_dev->api;
	if (!api->irq_callback_set) {
		LOG_ERR("%s does not support IRQ", uart_dev->name);
		return -ENOTSUP;
	}

	tty_set_tx_buf(&tty, tx_buf, TX_BUFSIZE);
	tty_set_rx_buf(&tty, rx_buf, RX_BUFSIZE);

	initialized = true;

	return 0;
}
SYS_INIT(sys_io_init, POST_KERNEL, 70);

namespace pw::sys_io
{
Status ReadByte(std::byte *b)
{
	if (!initialized) {
		return Status::Unavailable();
	}

	uint8_t buf;

	int ret = tty_read(&tty, &buf, 1);

	/* 0 means no input */
	if (ret == 0) {
		return Status::Unavailable();
	}
	/* Negative means an error */
	if (ret < 0) {
		return Status::DataLoss();
	}
	*b = (std::byte)buf;
	return OkStatus();
}

Status WriteByte(std::byte b)
{
	if (!initialized) {
		return Status::Unavailable();
	}

	int ret;
	uint8_t buf = (uint8_t)b;

	ret = tty_write(&tty, &buf, 1);
	if (ret < 0) {
		return Status::Unavailable();
	}
	return OkStatus();
}

} // namespace pw::sys_io
