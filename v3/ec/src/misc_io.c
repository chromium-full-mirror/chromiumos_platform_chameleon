/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include <shell/shell.h>

#include "io.h"
#include "misc_io.h"

int misc_io_get_board_version(void)
{
	int version;
	int val;

	val = gpio_get_level(board_version_2);
	if (val < 0) {
		return val;
	}
	version = val << 2;

	val = gpio_get_level(board_version_1);
	if (val < 0) {
		return val;
	}
	version |= val << 1;

	val = gpio_get_level(board_version_0);
	if (val < 0) {
		return val;
	}
	version |= val;

	return version;
}

/**
 * @brief Get the board version from BOARD_VERSION[2:0]
 */
static int cmd_misc_io_get_ver(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	int val = misc_io_get_board_version();

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
		      "BOARD_VERSION[2:0] = %d\n", val);
	return 0;
}
SHELL_CMD_REGISTER(board, NULL, "get BOARD_VERSION[2:0]", cmd_misc_io_get_ver);
