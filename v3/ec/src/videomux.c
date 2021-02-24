/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include <device.h>
#include <devicetree.h>
#include <drivers/gpio.h>
#include <shell/shell.h>
#include "io.h"
#include "videomux.h"

int videomux_select(enum video_source_t src, enum video_dest_t dest)
{
	/* Check `sel` for validity. */
	if ((dest != HDMI_RECEIVER) && (dest != FPGA_MGT)) {
		return -EINVAL;
	}

	switch (src) {
	case DP1:
		if (dest == HDMI_RECEIVER) {
			gpio_set_level(dp1_ps8468_sw, 0);
			gpio_set_level(gp213_it68051p1_ch_sel, 0);
		} else {
			gpio_set_level(dp1_ps8468_sw, 1);
			gpio_set_level(somp1_mode_sel, 0);
		}
		break;
	case DP2:
		if (dest == HDMI_RECEIVER) {
			gpio_set_level(dp2_ps8468_sw, 0);
			gpio_set_level(gp213_it68051p0_ch_sel, 0);
		} else {
			gpio_set_level(dp2_ps8468_sw, 1);
			gpio_set_level(somp2_mode_sel, 0);
		}
		break;
	case HDMI1:
		if (dest == HDMI_RECEIVER) {
			gpio_set_level(hdmi1_gp213_ch_sel, 0);
			gpio_set_level(gp213_it68051p1_ch_sel, 1);
		} else {
			gpio_set_level(hdmi1_gp213_ch_sel, 1);
			gpio_set_level(somp1_mode_sel, 1);
		}
		break;
	case HDMI2:
		if (dest == HDMI_RECEIVER) {
			gpio_set_level(hdmi2_gp213_ch_sel, 0);
			gpio_set_level(gp213_it68051p0_ch_sel, 1);
		} else {
			gpio_set_level(hdmi2_gp213_ch_sel, 1);
			gpio_set_level(somp2_mode_sel, 1);
		}
		break;
	default:
		return -EINVAL;
		break;
	}
	return 0;
}

/**
 * @brief Show status of videomux settings
 *
 * Dump out what each mux control line is set to, and then interpret those
 * values according to the table:
 *
 * U3/U22  U18/U31 U11/U14 DP
 * ------  ------- ------- ----
 * 0       0       x       IT68051
 * 1       x       0       FPGA
 * others                  n/c
 *
 * U10/U29 U18/U31 U11/U14 HDMI
 * ------  ------- ------- ----
 * 0       1       x       IT68051
 * 1       x       1       FPGA
 * others                  n/c
 *
 */
static int cmd_videomux_get(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	uint8_t rx1_mux = gpio_get_level(gp213_it68051p1_ch_sel);
	uint8_t dp1_demux = gpio_get_level(dp1_ps8468_sw);
	uint8_t hdmi1_demux = gpio_get_level(hdmi1_gp213_ch_sel);
	uint8_t fpga1_mux = gpio_get_level(somp1_mode_sel);

	uint8_t rx2_mux = gpio_get_level(gp213_it68051p0_ch_sel);
	uint8_t dp2_demux = gpio_get_level(dp2_ps8468_sw);
	uint8_t hdmi2_demux = gpio_get_level(hdmi2_gp213_ch_sel);
	uint8_t fpga2_mux = gpio_get_level(somp2_mode_sel);

	shell_fprintf(
		shell, SHELL_NORMAL,
		"U3:%d U10:%d U11:%d U18:%d U22:%d U29:%d U31:%d U14:%d\n",
		dp1_demux, hdmi1_demux, fpga1_mux, rx1_mux, dp2_demux,
		hdmi2_demux, rx2_mux, fpga2_mux);

	shell_fprintf(shell, SHELL_NORMAL, "DP1: ");
	if ((dp1_demux == 0) && (rx1_mux == 0)) {
		shell_fprintf(shell, SHELL_NORMAL, "HDMI RX\n");
	} else if ((dp1_demux == 1) && (fpga1_mux == 0)) {
		shell_fprintf(shell, SHELL_NORMAL, "FPGA\n");
	} else {
		shell_fprintf(shell, SHELL_NORMAL, "n/c\n");
	}

	shell_fprintf(shell, SHELL_NORMAL, "DP2: ");
	if ((dp2_demux == 0) && (rx2_mux == 0)) {
		shell_fprintf(shell, SHELL_NORMAL, "HDMI RX\n");
	} else if ((dp2_demux == 1) && (fpga2_mux == 0)) {
		shell_fprintf(shell, SHELL_NORMAL, "FPGA\n");
	} else {
		shell_fprintf(shell, SHELL_NORMAL, "n/c\n");
	}

	shell_fprintf(shell, SHELL_NORMAL, "HDMI1: ");
	if ((hdmi1_demux == 0) && (rx1_mux == 1)) {
		shell_fprintf(shell, SHELL_NORMAL, "HDMI RX\n");
	} else if ((hdmi1_demux == 1) && (fpga1_mux == 1)) {
		shell_fprintf(shell, SHELL_NORMAL, "FPGA\n");
	} else {
		shell_fprintf(shell, SHELL_NORMAL, "n/c\n");
	}

	shell_fprintf(shell, SHELL_NORMAL, "HDMI2: ");
	if ((hdmi2_demux == 0) && (rx2_mux == 1)) {
		shell_fprintf(shell, SHELL_NORMAL, "HDMI RX\n");
	} else if ((hdmi2_demux == 1) && (fpga2_mux == 1)) {
		shell_fprintf(shell, SHELL_NORMAL, "FPGA\n");
	} else {
		shell_fprintf(shell, SHELL_NORMAL, "n/c\n");
	}

	return 0;
}

/**
 * @brief Initialize the videomux GPIOs
 *
 * @note Most of the GPIOs are initialized in the devicetree, but the
 * RESETN signals for the MCDP2900 need to be configured for open-drain,
 * which isn't supported in devicetree because it strips off the lower
 * 8 bits of the pin config.
 *
 * @param ptr Unused argument, required by SYS_INIT
 * @retval 0
 * No error
 * @retval Non-zero
 * Error code
 */
static int videomux_init(const struct device *ptr)
{
	ARG_UNUSED(ptr);

	int ret;

	ret = gpio_pin_configure(gpio_get_device(dp1_hdmi_rst_l),
				 gpio_get_pin(dp1_hdmi_rst_l),
				 GPIO_OUTPUT_HIGH | GPIO_OPEN_DRAIN);
	if (ret != 0) {
		printk("Error %d: failed to configure dp1_hdmi_rst_l for open-drain\n",
		       ret);
		return ret;
	}

	ret = gpio_pin_configure(gpio_get_device(dp2_hdmi_rst_l),
				 gpio_get_pin(dp2_hdmi_rst_l),
				 GPIO_OUTPUT_HIGH | GPIO_OPEN_DRAIN);
	if (ret != 0) {
		printk("Error %d: failed to configure dp2_hdmi_rst_l for open-drain\n",
		       ret);
		return ret;
	}

	return 0;
}
SYS_INIT(videomux_init, APPLICATION, 75);

/**
 * @brief Route one of the ports to one of the destinations
 *
 * The port name is in argv[-1] and will be "hdmi1", "hdmi2", "dp1", or "dp2".
 * The destination is in argv[0] and will be "fpga" or "rx".
 * The shell shouldn't call this function if one of the parameters is incorrect,
 * but we'll add an extra validity check just in case.
 */
static int cmd_videomux_set(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);

	/*
	 * Because of how the Zephyr shell stores sub-commands, argv[0] will
	 * be the last sub-command, so "rx" or "fpga", and argv[-1] will be
	 * the sub-command before that, so "hdmi1", "hdmi2", "dp1" or "dp2".
	 * Indexing argv[] by a negative number just feels wrong, but the
	 * alternative is to have 8 different shell handlers.
	 */
	enum video_source_t src;
	enum video_dest_t dest;

	if (!strcmp(argv[-1], "hdmi1")) {
		src = HDMI1;
		shell_fprintf(shell, SHELL_NORMAL, "Connect HDMI1");
	} else if (!strcmp(argv[-1], "hdmi2")) {
		src = HDMI2;
		shell_fprintf(shell, SHELL_NORMAL, "Connect HDMI2");
	} else if (!strcmp(argv[-1], "dp1")) {
		src = DP1;
		shell_fprintf(shell, SHELL_NORMAL, "Connect DP1");
	} else if (!strcmp(argv[-1], "dp2")) {
		src = DP2;
		shell_fprintf(shell, SHELL_NORMAL, "Connect DP2");
	} else {
		printk("Invalid source: '%s'\n", argv[-1]);
		return -EINVAL;
	}

	if (!strcmp(argv[0], "rx")) {
		dest = HDMI_RECEIVER;
		shell_fprintf(shell, SHELL_NORMAL, " to receiver\n");
	} else if (!strcmp(argv[0], "fpga")) {
		dest = FPGA_MGT;
		shell_fprintf(shell, SHELL_NORMAL, " to FPGA\n");
	} else {
		printk("Invalid destination: '%s'\n", argv[0]);
		return -EINVAL;
	}

	return videomux_select(src, dest);
}

// clang-format off
SHELL_STATIC_SUBCMD_SET_CREATE(
	dp1_cmds, SHELL_CMD(fpga, NULL, "Route DP1 to FPGA", cmd_videomux_set),
	SHELL_CMD(rx, NULL, "Route DP1 to receiver", cmd_videomux_set),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(
	dp2_cmds, SHELL_CMD(fpga, NULL, "Route DP2 to FPGA", cmd_videomux_set),
	SHELL_CMD(rx, NULL, "Route DP2 to receiver", cmd_videomux_set),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(hdmi1_cmds,
	SHELL_CMD(fpga, NULL, "Route HDMI1 to FPGA", cmd_videomux_set),
	SHELL_CMD(rx, NULL, "Route HDMI1 to receiver", cmd_videomux_set),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(hdmi2_cmds,
	SHELL_CMD(fpga, NULL, "Route HDMI2 to FPGA", cmd_videomux_set),
	SHELL_CMD(rx, NULL, "Route HDMI2 to receiver", cmd_videomux_set),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(
	videomux_cmds,
	SHELL_CMD(get, NULL, "Show status of video mux", cmd_videomux_get),
	SHELL_CMD(dp1, &dp1_cmds, "Route DisplayPort 1", NULL),
	SHELL_CMD(dp2, &dp2_cmds, "Route DisplayPort 2", NULL),
	SHELL_CMD(hdmi1, &hdmi1_cmds, "Route HDMI 1", NULL),
	SHELL_CMD(hdmi2, &hdmi2_cmds, "Route HDMI 2", NULL),
	SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_CMD_REGISTER(videomux, &videomux_cmds, "Control the video mux", NULL);
// clang-format on
