/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>
#include "io.h"
#include "source_presence.h"
#include "sysmon.h"

/**
 * @brief Maximum voltage on AUX+ when a cable is connected.
 *
 * In the DisplayPort spec, the AUX+ line has a pull up to 2.5-3.3V of
 * 1Mohm at the sink, and a pull down of 10kohm~105kohm at the source side.
 * In the ideal case the maximum voltage on AUX+ when connected will be
 * V(AUX+) = 3.3 * 105 / (105 + 1000) = 0.3136V
 *
 * If we assume 5% tolerance on the resistors, we may possibly end up with
 * 950kohm on the sink side and 110.25kohm on the source side. In this extreme
 * case, we end up with V(AUX+) = 3.3 * 110.25 / (110.25 + 950) = 0.3432V
 */
const float auxp_max = 0.3432;

bool get_dp1_present(void)
{
	float dp1_auxp = sysmon_get_val(DP1_AUXP_DET);

	return dp1_auxp < auxp_max;
}

bool get_dp2_present(void)
{
	float dp2_auxp = sysmon_get_val(DP2_AUXP_DET);

	return dp2_auxp < auxp_max;
}

static int cmd_source_presence(const struct shell *shell, size_t argc,
			       char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	float dp1_auxp = sysmon_get_val(DP1_AUXP_DET);
	float dp1_auxn = sysmon_get_val(DP1_AUXN_DET);
	float dp2_auxp = sysmon_get_val(DP2_AUXP_DET);
	float dp2_auxn = sysmon_get_val(DP2_AUXN_DET);

	shell_fprintf(shell, SHELL_NORMAL,
		      "DP1_AUXP_DET = %f, DP1_AUXN_DET = %f (%spresent)\n",
		      dp1_auxp, dp1_auxn, (get_dp1_present() ? "" : "not "));
	shell_fprintf(shell, SHELL_NORMAL,
		      "DP2_AUXP_DET = %f, DP2_AUXN_DET = %f (%spresent)\n",
		      dp2_auxp, dp2_auxn, (get_dp2_present() ? "" : "not "));
	shell_fprintf(shell, SHELL_NORMAL, "HDMI1_PP3300 = %d\n",
		      gpio_get_level(hdmi1_pp3300));
	shell_fprintf(shell, SHELL_NORMAL, "HDMI2_PP3300 = %d\n",
		      gpio_get_level(hdmi2_pp3300));
	return 0;
}

SHELL_CMD_REGISTER(source, NULL, "source presence detect", cmd_source_presence);
