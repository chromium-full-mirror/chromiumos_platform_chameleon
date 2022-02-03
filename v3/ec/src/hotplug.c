/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include <device.h>
#include <devicetree.h>
#include <stdlib.h>
#include <drivers/gpio.h>
#include <drivers/i2c.h>
#include <shell/shell.h>
#include <sys/__assert.h>
#include "io.h"

static int cmd_get(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_NORMAL,
		      "DP1_AUXP_DET = %d, DP1_AUXN_DET = %d\n",
		      gpio_get_level(dp1_auxp_det),
		      gpio_get_level(dp1_auxn_det));
	shell_fprintf(shell, SHELL_NORMAL,
		      "DP2_AUXP_DET = %d, DP2_AUXN_DET = %d\n",
		      gpio_get_level(dp2_auxp_det),
		      gpio_get_level(dp2_auxn_det));
	shell_fprintf(shell, SHELL_NORMAL, "HDMI1_PP3300 = %d\n",
		      gpio_get_level(hdmi1_pp3300));
	shell_fprintf(shell, SHELL_NORMAL, "HDMI2_PP3300 = %d\n",
		      gpio_get_level(hdmi2_pp3300));
	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(hpd_cmds,
			       SHELL_CMD(get, NULL, "get HPD/presence pins",
					 cmd_get),
			       SHELL_SUBCMD_SET_END);
SHELL_CMD_REGISTER(hpd, &hpd_cmds, "hotplug detect (HPD) pins", NULL);
