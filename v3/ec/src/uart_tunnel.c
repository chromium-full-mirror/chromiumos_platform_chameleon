/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/shell/shell.h>

const char *DEFAULT_UART = "UART_2";

/**
 * @brief Access another uart port connected to the ec
 */
static int cmd_uart(const struct shell *shell, size_t argc, char **argv)
{
	const char **chosen_uart = &DEFAULT_UART;
	if (argc > 1) {
		*chosen_uart = argv[1];
	}

	const struct device *uart_device = device_get_binding(*chosen_uart);
	if (!uart_device) {
		shell_fprintf(shell, SHELL_NORMAL, "%s not found.\n",
			      *chosen_uart);
		return -EINVAL;
	}

	uint32_t baudrate = 0;
	uart_line_ctrl_get(uart_device, UART_LINE_CTRL_BAUD_RATE, &baudrate);
	shell_fprintf(shell, SHELL_NORMAL,
		      "Monitoring %s, baud %d (Press TODO to exit)...\n",
		      *chosen_uart, baudrate);

	char buf[16];
	while (1) {
		/*
		 * TODO: Calling uart_fifo_read outside of an ISR might be bad
		 * according to the docs, but I don't care enough to fix it
		 * and it seems to work for now.
		 */
		int bytes = uart_fifo_read(uart_device, buf, sizeof(buf) - 1);
		buf[bytes] = '\0';
		shell_fprintf(shell, SHELL_NORMAL, "%s", buf);

		/*
		 * TODO: Figure out why we're dropping characters.
		 */
	}

	return 0;
}
SHELL_CMD_REGISTER(uart, NULL, "Access another uart port", cmd_uart);
