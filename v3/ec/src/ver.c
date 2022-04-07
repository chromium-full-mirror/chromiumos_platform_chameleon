/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include <device.h>
#include <shell/shell.h>
#include <sys/printk.h>

#include "version.h"

/**
 * @brief Get the build version
 */
static int cmd_ver(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
		      "EC = %s\n", EC_VER);
	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
		      "ITE = %s\n", ITE_VER);
	return 0;
}
SHELL_CMD_REGISTER(ver, NULL, "get build version", cmd_ver);

/**
 * @brief Prints the git hashes for the build
 *
 * @param ptr Unused argument, required by SYS_INIT
 * @retval 0
 * No error
 * @retval Non-zero
 * Error code
 */
static int version_init(const struct device *ptr)
{
	ARG_UNUSED(ptr);

	printk("\n");
	printk("v3/ec build %s\n", EC_VER);
	printk("private/ite build %s\n", ITE_VER);

	return 0;
}
SYS_INIT(version_init, POST_KERNEL, 1);
