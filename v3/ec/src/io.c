/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include <device.h>
#include <devicetree.h>
#include <drivers/gpio.h>
#include <shell/shell.h>
#include <sys/__assert.h>
#include <sys/printk.h>

#include "io.h"

struct gpio_info {
	const char *const label;
	const char *const dev_name;
	const struct device *dev;
	gpio_pin_t pin;
	int flags;
};

#define GPIO(group, name)                                            \
	[name] = { DT_LABEL(DT_PATH(group, name)),                   \
		   DT_GPIO_LABEL(DT_PATH(group, name), gpios), NULL, \
		   DT_GPIO_PIN(DT_PATH(group, name), gpios),         \
		   DT_GPIO_FLAGS(DT_PATH(group, name), gpios) }

static struct gpio_info gpios[] = {
	GPIO(leds, power_good_led),
	GPIO(sd_mux, sd_mux_sel),
	GPIO(sd_mux, sd_mux_en_l),
	GPIO(sd_mux, usd_pwr_sel),
	GPIO(sd_mux, usd_pwr_en),
	GPIO(sd_mux, usd_cd_det),
	GPIO(sysmon, sysmon_sel),
	GPIO(fpga, pwr_en),
	GPIO(fpga, pwr_good),
	GPIO(fpga, boot_mode1),
	GPIO(fpga, boot_mode0),
	GPIO(fpga, por_l_load_l),
	GPIO(fpga, fpga_done),
	GPIO(misc, tp126),
	GPIO(misc, tp125),
	GPIO(misc, board_version_2),
	GPIO(misc, board_version_1),
	GPIO(misc, board_version_0),
	GPIO(i2c_switch, exp_reset),
	GPIO(i2c_switch, exp_irq),
	GPIO(videomux, gp213_it68051p1_ch_sel),
	GPIO(videomux, dp1_ps8468_sw),
	GPIO(videomux, hdmi1_gp213_ch_sel),
	GPIO(videomux, somp1_mode_sel),
	GPIO(videomux, gp213_it68051p0_ch_sel),
	GPIO(videomux, dp2_ps8468_sw),
	GPIO(videomux, hdmi2_gp213_ch_sel),
	GPIO(videomux, somp2_mode_sel),
	GPIO(videomux, dp1_ps8468_rst_l),
	GPIO(videomux, dp2_ps8468_rst_l),
	GPIO(videomux, dp1_hdmi_rst_l),
	GPIO(videomux, dp2_hdmi_rst_l),
	GPIO(it68051, it68051p0_pwr_det),
	GPIO(it68051, it68051p1_pwr_det),
	GPIO(it68051, it68051_rst_l),
	GPIO(it68051, it68051p0_ddc_bp_l),
	GPIO(it68051, it68051p1_ddc_bp_l),
	GPIO(it68051, gp213_it68051p1_hpd),
	GPIO(dp_cfg, dp1_ps8468_mode),
	GPIO(dp_cfg, dp1_ps8468_cfg0),
	GPIO(dp_cfg, dp1_ps8468_cfg1),
	GPIO(dp_cfg, dp1_ps8468_cfg2),
	GPIO(dp_cfg, dp1_ps8468_cfg3),
	GPIO(dp_cfg, dp1_ps8468_cfg4),
	GPIO(dp_cfg, dp1_ps8468_eq0),
	GPIO(dp_cfg, dp1_ps8468_eq1),
	GPIO(dp_cfg, dp2_ps8468_mode),
	GPIO(dp_cfg, dp2_ps8468_cfg0),
	GPIO(dp_cfg, dp2_ps8468_cfg1),
	GPIO(dp_cfg, dp2_ps8468_cfg2),
	GPIO(dp_cfg, dp2_ps8468_cfg3),
	GPIO(dp_cfg, dp2_ps8468_cfg4),
	GPIO(dp_cfg, dp2_ps8468_eq0),
	GPIO(dp_cfg, dp2_ps8468_eq1),
};
static int io_init_devices(const struct device *ptr)
{
	ARG_UNUSED(ptr);
	for (int idx = 0; idx < ARRAY_SIZE(gpios); ++idx) {
		gpios[idx].dev = device_get_binding(gpios[idx].dev_name);
		if (!gpios[idx].dev) {
			printk("io_init_devices: "
			       "device_get_binding(%s) failed!\n",
			       gpios[idx].dev_name);
			continue;
		}
		int ret = gpio_pin_configure(gpios[idx].dev, gpios[idx].pin,
					     gpios[idx].flags);
		if (ret != 0) {
			printk("io_init_devices: "
			       "gpio_pin_configure(%s(*%p), %d(\"%s\"), 0x%x) "
			       "failed, ret = %d\n",
			       gpios[idx].dev_name, gpios[idx].dev,
			       gpios[idx].pin, gpios[idx].label,
			       gpios[idx].flags, ret);
                }
	}
	return 0;
}
SYS_INIT(io_init_devices, APPLICATION, 1);

int gpio_get_level(enum gpio_signal signal)
{
	return gpio_pin_get(gpios[signal].dev, gpios[signal].pin);
}

int gpio_set_level(enum gpio_signal signal, int value)
{
	return gpio_pin_set(gpios[signal].dev, gpios[signal].pin, value);
}

const struct device *gpio_get_device(enum gpio_signal signal)
{
	return gpios[signal].dev;
}

gpio_pin_t gpio_get_pin(enum gpio_signal signal)
{
	return gpios[signal].pin;
}

/* TODO(pfagerburg) move to another module */
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

/* Shell commands for debugging/testing use. See README.md for details. */
/* TODO (pfagerburg) replace with generic "set [IO name] on|off" commands. */

/**
 * @brief Get value of TP126
 */
static int cmd_io_get_tp126(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	int val = gpio_get_level(tp126);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "TP126 = %d\n", val);
	return 0;
}

/**
 * @brief Get value of TP125
 */
static int cmd_io_get_tp125(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	int val = gpio_get_level(tp125);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "TP125 = %d\n", val);
	return 0;
}

/**
 * @brief Get the board version from BOARD_VERSION[2:0]
 */
static int cmd_io_get_ver(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	int val = misc_io_get_board_version();

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
		      "BOARD_VERSION[2:0] = %d\n", val);
	return 0;
}
SHELL_STATIC_SUBCMD_SET_CREATE(
	get_io, SHELL_CMD(tp126, NULL, "TP126", cmd_io_get_tp126),
	SHELL_CMD(tp125, NULL, "TP125", cmd_io_get_tp125),
	SHELL_CMD(ver, NULL, "BOARD_VERSION[2:0]", cmd_io_get_ver),
	SHELL_SUBCMD_SET_END);

/**
 * @brief Set TP126 to on
 */
static int cmd_io_set_tp126_on(const struct shell *shell, size_t argc,
			       char **argv)
{
	ARG_UNUSED(shell);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return gpio_set_level(tp126, 1);
}

/**
 * @brief Set TP126 to off
 */
static int cmd_io_set_tp126_off(const struct shell *shell, size_t argc,
				char **argv)
{
	ARG_UNUSED(shell);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return gpio_set_level(tp126, 0);
}

/**
 * @brief Set TP125 to on
 */
static int cmd_io_set_tp125_on(const struct shell *shell, size_t argc,
			       char **argv)
{
	ARG_UNUSED(shell);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return gpio_set_level(tp125, 1);
}

/**
 * @brief Set TP126 to off
 */
static int cmd_io_set_tp125_off(const struct shell *shell, size_t argc,
				char **argv)
{
	ARG_UNUSED(shell);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return gpio_set_level(tp125, 0);
}
SHELL_STATIC_SUBCMD_SET_CREATE(
	tp126_on_off, SHELL_CMD(on, NULL, "set TP126 on", cmd_io_set_tp126_on),
	SHELL_CMD(off, NULL, "set TP126 off", cmd_io_set_tp126_off),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(
	tp125_on_off, SHELL_CMD(on, NULL, "set TP125 on", cmd_io_set_tp125_on),
	SHELL_CMD(off, NULL, "set TP125 off", cmd_io_set_tp125_off),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(
	set_io, SHELL_CMD(tp126, &tp126_on_off, "set TP126", NULL),
	SHELL_CMD(tp125, &tp125_on_off, "set TP125", NULL),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(io_cmds,
			       SHELL_CMD(get, &get_io, "get IO value", NULL),
			       SHELL_CMD(set, &set_io, "set IO pin", NULL),
			       SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_CMD_REGISTER(io, &io_cmds, "Control IO pins", NULL);
