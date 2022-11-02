/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>
#include "io.h"
#include "source_presence.h"

bool get_dp1_present(void)
{
	int dp1_auxp = gpio_get_level(dp1_auxp_det);
	int dp1_auxn = gpio_get_level(dp1_auxn_det);

	return (dp1_auxp == 0) && (dp1_auxn == 1);
}

bool get_dp2_present(void)
{
	int dp2_auxp = gpio_get_level(dp2_auxp_det);
	int dp2_auxn = gpio_get_level(dp2_auxn_det);

	return (dp2_auxp == 0) && (dp2_auxn == 1);
}

static int cmd_source_presence(const struct shell *shell, size_t argc,
			       char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	int dp1_auxp = gpio_get_level(dp1_auxp_det);
	int dp1_auxn = gpio_get_level(dp1_auxn_det);
	int dp2_auxp = gpio_get_level(dp2_auxp_det);
	int dp2_auxn = gpio_get_level(dp2_auxn_det);

	shell_fprintf(shell, SHELL_NORMAL,
		      "DP1_AUXP_DET = %d, DP1_AUXN_DET = %d (%spresent)\n",
		      dp1_auxp, dp1_auxn, (get_dp1_present() ? "" : "not "));
	shell_fprintf(shell, SHELL_NORMAL,
		      "DP2_AUXP_DET = %d, DP2_AUXN_DET = %d (%spresent)\n",
		      dp2_auxp, dp2_auxn, (get_dp2_present() ? "" : "not "));
	shell_fprintf(shell, SHELL_NORMAL, "HDMI1_PP3300 = %d\n",
		      gpio_get_level(hdmi1_pp3300));
	shell_fprintf(shell, SHELL_NORMAL, "HDMI2_PP3300 = %d\n",
		      gpio_get_level(hdmi2_pp3300));
	return 0;
}

SHELL_CMD_REGISTER(source, NULL, "source presence detect", cmd_source_presence);
