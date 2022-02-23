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
#include <logging/log.h>
#include <shell/shell.h>
#include <sys/__assert.h>

#include "io.h"

LOG_MODULE_REGISTER(io);

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
	GPIO(fpga, fpga_prot),
	GPIO(fpga, fpga_comm0),
	GPIO(misc, tp126),
	GPIO(misc, tp125),
	GPIO(misc, board_version_2),
	GPIO(misc, board_version_1),
	GPIO(misc, board_version_0),
	GPIO(misc, si5338c_int),
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
	GPIO(it68051, it68051_en),
	GPIO(it68051, it68051p0_pwr_det),
	GPIO(it68051, it68051p1_pwr_det),
	GPIO(it68051, it68051_rst_l),
	GPIO(it68051, gp213_it68051p1_hpd),
	GPIO(it68051, i2c2_int_l),
	GPIO(hotplug, dp1_auxp_det),
	GPIO(hotplug, dp1_auxn_det),
	GPIO(hotplug, dp2_auxp_det),
	GPIO(hotplug, dp2_auxn_det),
	GPIO(hotplug, hdmi1_pp3300),
	GPIO(hotplug, hdmi2_pp3300),
	GPIO(hotplug, dp1_mcu_hpd),
	GPIO(hotplug, dp2_mcu_hpd),
	GPIO(hotplug, dp_in_pwr_en),
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
	GPIO(dp_cfg, dp1_out_sw),
	GPIO(dp_cfg, dp1_out_pd_l),
	GPIO(dp_cfg, dp1_out_mode),
	GPIO(dp_cfg, dp2_out_sw),
	GPIO(dp_cfg, dp2_out_pd_l),
	GPIO(dp_cfg, dp2_out_mode),
	GPIO(pcie, pcie_perst_l),
	GPIO(pcie, pcie_wake_l),
	GPIO(pcie, pcie_rsvd1),
	GPIO(pcie, pcie_rsvd2),
	GPIO(pcie, pcie_rsvd3),
	GPIO(pcie, pcie_rsvd4),
	GPIO(pcie, som_a34),
	GPIO(pcie, som_a21),
	GPIO(pcie, som_a98),
	GPIO(pcie, som_a104),
};

/*
 * Shell commands for reading and setting GPIOs. See README.md for details.
 *
 * See also https://docs.zephyrproject.org/latest/reference/shell/index.html#dynamic-commands
 */
#define MAX_CMD_LEN (31u)

/* buffer holding dynamicly created user commands */
static char dynamic_cmd_buffer[ARRAY_SIZE(gpios)][MAX_CMD_LEN + 1];
/* commands counter */
static const uint8_t DYNAMIC_CMD_CNT = ARRAY_SIZE(gpios);

typedef int cmp_t(const void *, const void *);
extern void qsort(void *a, size_t n, size_t es, cmp_t *cmp);

/* function required by qsort */
static int string_cmp(const void *p_a, const void *p_b)
{
	return strcmp((const char *)p_a, (const char *)p_b);
}

/**
 * @brief Initialize GPIOs and shell commands to set/get
 *
 * Walk the array of GPIOs and look up each device name (e.g. "GPIOB"). Store
 * the `const struct device *` into the struct for that GPIO. It would be
 * nice to do this at compile time, but `device_get_binding` is a runtime
 * call.
 *
 * Also copy the GPIO names into another array and sort them alphabetically.
 * We'll use that array to set up dynamic shell commands to get and set GPIOs.
 *
 * As the Zephyr shell sees it, the name ("TP125") of the GPIO in the command
 * `io get TP125` is actually a sub-command. We can use Zephyr's dynamic shell
 * command to build up a list of sub-commands that we can re-use with multiple
 * command handlers. Note that the sub-command list must be in sorted order,
 * so we first fill the sub-command array and then sort it with `qsort`.
 *
 * @note If there were only one command that had all the GPIO names, and the
 * GPIO name was the last item, we could use SHELL_SUBCMD_DICT_SET_CREATE,
 * which specifies a list of text names and integer values. A dictionary
 * command does not offer a way to specify a further sub-command, and the
 * entries in the dictionary can only be used with a single command; attempts
 * to declare multiple commands with the same list results in duplicate
 * symbol errors.
 *
 * @param ptr	Required by the API, but not used
 * @retval 0	Success
 */
static int io_init_devices(const struct device *ptr)
{
	ARG_UNUSED(ptr);
	for (int idx = 0; idx < ARRAY_SIZE(gpios); ++idx) {
		/*
		 * Store the GPIO name in the list that will be used for
		 * dynamic shell commands.
		 */
		strncpy(dynamic_cmd_buffer[idx], gpios[idx].label, MAX_CMD_LEN);

		/* Look up the device by name. */
		gpios[idx].dev = device_get_binding(gpios[idx].dev_name);
		if (!gpios[idx].dev) {
			LOG_ERR("io_init_devices: "
				"device_get_binding(%s) failed!\n",
				gpios[idx].dev_name);
			continue;
		}

		/* Configure the GPIO pin. */
		int ret = gpio_pin_configure(gpios[idx].dev, gpios[idx].pin,
					     gpios[idx].flags);
		if (ret != 0) {
			LOG_ERR("io_init_devices: "
				"gpio_pin_configure(%s(*%p), %d(\"%s\"), 0x%x) "
				"failed, ret = %d\n",
				gpios[idx].dev_name, gpios[idx].dev,
				gpios[idx].pin, gpios[idx].label,
				gpios[idx].flags, ret);
		}
	}

	/* Zephyr dynamic shell commands require a sorted list. */
	qsort(dynamic_cmd_buffer, DYNAMIC_CMD_CNT,
	      sizeof(dynamic_cmd_buffer[0]), string_cmp);

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

/*
 * @brief Look up an enum by text name
 *
 * Search the GPIO names to find a match.
 *
 * @note The gpios[] array is *not* sorted, so we have to do a linear search.
 * This is a known compromise so that we can use the order as written in
 * the code. Any compiled code that needs to refer to specific GPIOs can use
 * the enumeration values directly. so this inefficiency only affects shell
 * commands.
 *
 * @param name	The text name of the GPIO
 * @param pSignal	Pointer to where to store the found value
 * @retval 0	Found, value is in *pSignal
 * @retval -EINVAL	Not found
 */
static int gpio_find_by_name(const char *name, enum gpio_signal *pSignal)
{
	__ASSERT(pSignal != NULL, "Passed a NULL pointer to gpio_find_by_name");
	for (uint8_t idx = 0; idx < ARRAY_SIZE(gpios); idx++) {
		if (!strcmp(name, gpios[idx].label)) {
			*pSignal = (enum gpio_signal)idx;
			return 0;
		}
	}
	return -EINVAL;
}

/*
 *
 */
static int cmd_get(const struct shell *shell, size_t argc, char **argv)
{
	/*
	 * Initialize `signal` to something so compiler is happy. If
	 * `gpio_find_by_name` doesn't find the name, it won't set `signal`,
	 * but it also returns an error code, so we won't use `signal`
	 * anyway. But the compiler doesn't know that.
	 */
	enum gpio_signal signal = power_good_led;

	if (argc == 1) {
		/* No pin selected, do all */
		for (enum gpio_signal signal = 0;
		     signal < sizeof(gpios) / sizeof(gpios[0]); signal++) {
			int alignment;
			shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
				      "(%s.%d)%n", // %s = %d
				      gpios[signal].dev_name, gpios[signal].pin,
				      &alignment);
			shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
				      "%*s = %d\n", 40 - alignment,
				      gpios[signal].label,
				      gpio_get_level(signal));
		}
		return 0;
	}

	if (gpio_find_by_name(argv[1], &signal) != 0) {
		shell_error(shell, "%s: unknown parameter: %s", argv[0],
			    argv[1]);
		return -ENOEXEC;
	}

	int val = gpio_get_level(signal);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "%s = %d\n", argv[1],
		      val);
	return 0;
}

/*
 *
 */
static int cmd_set(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);

	enum gpio_signal signal = power_good_led;

	if (gpio_find_by_name(argv[-1], &signal) != 0) {
		shell_error(shell, "%s: uknown parameter: %s", argv[-2],
			    argv[-1]);
		return -ENOEXEC;
	}

	int value = 0;
	if (!strcmp(argv[0], "on")) {
		value = 1;
	} else if (!strcmp(argv[0], "1")) {
		value = 1;
	} else if (!strcmp(argv[0], "off")) {
		value = 0;
	} else if (!strcmp(argv[0], "0")) {
		value = 0;
	} else {
		shell_error(shell, "%s: uknown parameter: %s", argv[-2],
			    argv[0]);
		return -ENOEXEC;
	}

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "set %s to %d\n",
		      argv[-1], value);
	int ret = gpio_set_level(signal, value);

	if (ret != 0) {
		shell_error(shell, "gpio_set_level error %d", ret);
		return -ENOEXEC;
	}
	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(
	on_off, SHELL_CMD_ARG(on, NULL, "turn GPIO on", cmd_set, 1, 0),
	SHELL_CMD_ARG(off, NULL, "turn GPIO off", cmd_set, 1, 0),
	SHELL_CMD_ARG(1, NULL, "turn GPIO on", cmd_set, 1, 0),
	SHELL_CMD_ARG(0, NULL, "turn GPIO off", cmd_set, 1, 0),
	SHELL_SUBCMD_SET_END /* Array terminated. */
);

/*
 * @brief Fill in details for a sub-command on `set`
 *
 * The Dictionary shell handler calls this function to get the information
 * about each sub-command. When we run out of sub-commands, we fill in a
 * NULL pointer.
 *
 * @note This routine fills in the sub-command handler so that every
 * sub-command that is a GPIO name has a further "on/off" sub-command.
 *
 * @param idx	Index into the dynamic command array to get
 */
static void dynamic_cmd_set(size_t idx, struct shell_static_entry *entry)
{
	if (idx < DYNAMIC_CMD_CNT) {
		entry->syntax = dynamic_cmd_buffer[idx];
		entry->handler = NULL;
		entry->subcmd = &on_off;
		entry->help = NULL;
	} else {
		entry->syntax = NULL;
	}
}
SHELL_DYNAMIC_CMD_CREATE(set_io, dynamic_cmd_set);

/*
 * @brief Fill in details for a sub-command on `get`
 *
 * The Dictionary shell handler calls this function to get the information
 * about each sub-command. When we run out of sub-commands, we fill in a
 * NULL pointer.
 *
 * @param idx	Index into the dynamic command array to get
 */
static void dynamic_cmd_get(size_t idx, struct shell_static_entry *entry)
{
	if (idx < DYNAMIC_CMD_CNT) {
		entry->syntax = dynamic_cmd_buffer[idx];
		entry->handler = NULL;
		entry->subcmd = NULL;
		entry->help = NULL;
	} else {
		entry->syntax = NULL;
	}
}
SHELL_DYNAMIC_CMD_CREATE(get_io, dynamic_cmd_get);

SHELL_STATIC_SUBCMD_SET_CREATE(io_cmds,
			       SHELL_CMD(get, &get_io, "get IO value", cmd_get),
			       SHELL_CMD(set, &set_io, "set IO value", NULL),
			       SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_CMD_REGISTER(io, &io_cmds, "Control IO pins", NULL);
