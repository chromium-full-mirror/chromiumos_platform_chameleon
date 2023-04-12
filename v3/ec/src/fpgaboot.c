/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <zephyr/shell/shell.h>
#include <zephyr/sys/__assert.h>
#include "io.h"
#include "fpgaboot.h"
#include "fpgaboot_sm.h"

LOG_MODULE_REGISTER(fpgaboot);

/**
 * FPGA state
 */
static enum fpga_state state;

/**
 * FPGA boot mode
 *
 * Needs to be saved so that we can force the pins low when power is off,
 * and then restore them to the previous setting when power is on again.
 */
static enum fpga_boot_mode saved_boot_mode;

int fpgaboot_set_boot_mode(enum fpga_boot_mode mode)
{
	saved_boot_mode = mode;
	switch (mode) {
	case FPGA_BOOT_EMMC:
		gpio_set_level(boot_mode1, 0);
		gpio_set_level(boot_mode0, 0);
		break;
	case FPGA_BOOT_QSPI:
		gpio_set_level(boot_mode1, 0);
		gpio_set_level(boot_mode0, 1);
		break;
	case FPGA_BOOT_SDIO:
		gpio_set_level(boot_mode1, 1);
		gpio_set_level(boot_mode0, 1);
		break;
	default:
		__ASSERT(false, "Unsupported fpga_boot_mode value");
		return -EINVAL;
	}

	return 0;
}

K_MSGQ_DEFINE(fpgaboot_msgq, sizeof(enum fpga_event), 10, 1);

int fpgaboot_power_on(void)
{
	enum fpga_event event = FPGABOOT_POWER_ON_REQ;

	return k_msgq_put(&fpgaboot_msgq, &event, K_NO_WAIT);
}

int fpgaboot_power_off(void)
{
	enum fpga_event event = FPGABOOT_POWER_OFF_REQ;

	return k_msgq_put(&fpgaboot_msgq, &event, K_NO_WAIT);
}

static struct gpio_callback pwr_good_cb_data;

static void pwr_good_cb(const struct device *dev, struct gpio_callback *cb,
			uint32_t pins)
{
	int val = gpio_get_level(pwr_good);
	enum fpga_event event = val ? FPGABOOT_SOM_PWR_GOOD_ASSERTED :
					    FPGABOOT_SOM_PWR_GOOD_DEASSERTED;

	k_msgq_put(&fpgaboot_msgq, &event, K_NO_WAIT);
}

static struct gpio_callback fpga_done_cb_data;

static void fpga_done_cb(const struct device *dev, struct gpio_callback *cb,
			 uint32_t pins)
{
	int val = gpio_get_level(fpga_done);
	enum fpga_event event = val ? FPGABOOT_SOM_FPGA_DONE_ASSERTED :
					    FPGABOOT_SOM_FPGA_DONE_DEASSERTED;

	k_msgq_put(&fpgaboot_msgq, &event, K_NO_WAIT);
}

/*
 * @brief Post a TIMER_EXPIRED event when the time expires
 *
 * @param timer_id Unused, required by signature
 */
static void fpgaboot_timeout(struct k_timer *timer_id)
{
	ARG_UNUSED(timer_id);

	enum fpga_event event = FPGABOOT_TIMER_EXPIRED;

	k_msgq_put(&fpgaboot_msgq, &event, K_NO_WAIT);
}

K_TIMER_DEFINE(fpgaboot_timer, fpgaboot_timeout, NULL);
/*
 * Values for waiting for FPGA events
 *
 * Both values are wild guesses unless/until characterized.
 * The SHORT_TIMER is to wait from PWR_EN to PWR_GOOD.
 * The LONG_TIME is to wait from releasing reset to seeing DONE.
 */
#define SHORT_TIMER K_MSEC(500)
#define LONG_TIMER K_SECONDS(60)

/**
 * @brief Execute the actions specified by the state machine
 *
 * The FPGA power/boot state machine returns a bitfield with possible
 * actions that need to be taken. This function does the actions.
 * The actions are defined in fpgaboot_sm.h starting at `FPGABOOT_ACTION_NONE`.
 *
 * @param actions Bitfield of actions to be taken
 */
static void fpgaboot_handle_actions(uint32_t actions)
{
	if (actions & FPGABOOT_ASSERT_SOM_PWR_EN) {
		__ASSERT(
			(actions & FPGABOOT_DEASSERT_SOM_PWR_EN) == 0,
			"Don't assert and de-assert SOM_PWR_EN at the same time!");
		/* Restore the bootmode pins to previous setting. */
		fpgaboot_set_boot_mode(saved_boot_mode);
		gpio_set_level(pwr_en, 1);
		/*Turn on the pull-ups on SOM_PWR_GOOD and SOM_FPGA_DONE. */
		gpio_pin_configure(gpio_get_device(pwr_good),
				   gpio_get_pin(pwr_good),
				   GPIO_INPUT | GPIO_PULL_UP);
		gpio_pin_configure(gpio_get_device(fpga_done),
				   gpio_get_pin(fpga_done),
				   GPIO_INPUT | GPIO_PULL_UP);

	}
	if (actions & FPGABOOT_DEASSERT_SOM_PWR_EN) {
		__ASSERT(
			(actions & FPGABOOT_ASSERT_SOM_PWR_EN) == 0,
			"Don't assert and de-assert SOM_PWR_EN at the same time!");
		gpio_set_level(pwr_en, 0);
		/*
		 * Force bootmode pins low to prevent driving unpowered pins
		 * on the FPGA module, but don't use `fpgaboot_set_boot_mode`
		 * because we don't want to update the saved boot mode.
		 */
		gpio_set_level(boot_mode1, 0);
		gpio_set_level(boot_mode0, 0);
		/*
		 * Also ensure the POR signal is driven low. Unlike the boot
		 * mode, it doesn't need to be restored at power on, as the
		 * state machine will handle it.
		 * In fact, this signal is probably already low because of
		 * the state machine, but there's no harm in making sure.
		 */
		gpio_set_level(por_l_load_l, 0);
		/*
		 * Turn off the pull-ups on SOM_PWR_GOOD and SOM_FPGA_DONE
		 * to prevent current leakage into the FPGA module.
		 */
		gpio_pin_configure(gpio_get_device(pwr_good),
				   gpio_get_pin(pwr_good),
				   GPIO_INPUT);
		gpio_pin_configure(gpio_get_device(fpga_done),
				   gpio_get_pin(fpga_done),
				   GPIO_INPUT);
	}
	/* NB: SOM_POR_L_LOAD_L is active low, so "assert" == "set to 0V" */
	if (actions & FPGABOOT_ASSERT_SOM_POR_L_LOAD_L) {
		__ASSERT(
			(actions & FPGABOOT_DEASSERT_SOM_POR_L_LOAD_L) == 0,
			"Don't assert and de-assert SOM_POR_L_LOAD_l at the same time!");
		gpio_set_level(por_l_load_l, 0);
	}
	if (actions & FPGABOOT_DEASSERT_SOM_POR_L_LOAD_L) {
		__ASSERT(
			(actions & FPGABOOT_ASSERT_SOM_POR_L_LOAD_L) == 0,
			"Don't assert and de-assert SOM_POR_L_LOAD_l at the same time!");
		gpio_set_level(por_l_load_l, 1);
	}
	if (actions & FPGABOOT_START_SHORT_TIMER) {
		k_timer_start(&fpgaboot_timer, SHORT_TIMER, K_NO_WAIT);
	}
	if (actions & FPGABOOT_START_LONG_TIMER) {
		k_timer_start(&fpgaboot_timer, LONG_TIMER, K_NO_WAIT);
	}
	if (actions & FPGABOOT_STOP_TIMER) {
		k_timer_stop(&fpgaboot_timer);
	}
}

/**
 * Define priotity for the fpgaboot task
 */
#define FPGABOOT_PRIORITY 10

/**
 * Define the size of the stack for the fpgaboot task.
 */
#define FPGABOOT_STACK_SIZE 500

/**
 * Zephyr macro to allocate the stack area.
 */
K_THREAD_STACK_DEFINE(fpgaboot_stack_area, FPGABOOT_STACK_SIZE);

/**
 * Internal data structure for tracking the fpgaboot task.
 */
static struct k_thread fpgaboot_thread_data;

/**
 * @brief Run the FPGA power/boot state machine
 *
 * This task controls the FPGA power/boot sequence. The task listens on a
 * message queue for events: requests from callers and messages from
 * interrupt handlers for GPIO inputs. When it gets an event from the queue,
 * it passes that to the state machine, and then takes the output `actions`
 * and does the things that the bitfields indicate should be done.

 * @param unused1 Required by the Zephyr thread API. Unused.
 * @param unused2 Required by the Zephyr thread API. Unused.
 * @param unused3 Required by the Zephyr thread API. Unused.
 */
static void fpgaboot_task(void *unused1, void *unused2, void *unused3)
{
	ARG_UNUSED(unused1);
	ARG_UNUSED(unused2);
	ARG_UNUSED(unused3);

	enum fpga_event event;
	uint32_t actions;

	k_thread_name_set(NULL, "fpgaboot_task");

	fpgaboot_init_state_machine(gpio_get_level(pwr_en),
				    gpio_get_level(pwr_good),
				    gpio_get_level(fpga_done), &state,
				    &actions);
	fpgaboot_handle_actions(actions);
	for (;;) {
		int ret = k_msgq_get(&fpgaboot_msgq, &event, K_FOREVER);

		if (ret == 0) {
			fpgaboot_run_state_machine(event, &state, &actions);
			fpgaboot_handle_actions(actions);
		}
	}
}

/**
 * @brief Initialize the FPGA GPIOs and start the state machine task
 *
 * @note Also sets the FPGA boot mode to SDIO.
 *
 * @retval 0
 * No error
 * @retval Non-zero
 * Error code
 */
static int fpgaboot_init(void)
{
	int ret;

	fpgaboot_set_boot_mode(FPGA_BOOT_SDIO);

	/* Configure pwr_good interrupt on change. */
	ret = gpio_pin_interrupt_configure(gpio_get_device(pwr_good),
					   gpio_get_pin(pwr_good),
					   GPIO_INT_EDGE_BOTH);
	if (ret != 0) {
		LOG_ERR("Error %d: failed to configure interrupt on PWR_GOOD\n",
			ret);
		return ret;
	}
	gpio_init_callback(&pwr_good_cb_data, pwr_good_cb,
			   BIT(gpio_get_pin(pwr_good)));
	gpio_add_callback(gpio_get_device(pwr_good), &pwr_good_cb_data);

	/* Configure fpga_done interrupt on change. */
	ret = gpio_pin_interrupt_configure(gpio_get_device(fpga_done),
					   gpio_get_pin(fpga_done),
					   GPIO_INT_EDGE_BOTH);
	if (ret != 0) {
		LOG_ERR("Error %d: failed to configure interrupt on FPGA_DONE\n",
			ret);
		return ret;
	}
	gpio_init_callback(&fpga_done_cb_data, fpga_done_cb,
			   BIT(gpio_get_pin(fpga_done)));
	gpio_add_callback(gpio_get_device(fpga_done), &fpga_done_cb_data);

	/* Create the fpgaboot task and start it. */
	k_thread_create(&fpgaboot_thread_data, fpgaboot_stack_area,
			K_THREAD_STACK_SIZEOF(fpgaboot_stack_area),
			fpgaboot_task, NULL, NULL, NULL, FPGABOOT_PRIORITY, 0,
			K_NO_WAIT);

	return 0;
}
SYS_INIT(fpgaboot_init, APPLICATION, 75);

/**
 * @brief Display the FPGA status
 */
static int cmd_status(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
		      "FPGA steady status: %s\n",
		      fpgaboot_is_steady_state(state) ? "true" : "false");
	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "BOOT_MODE = %d%d\n",
		      gpio_get_level(boot_mode1), gpio_get_level(boot_mode0));
	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "PWR_EN = %d\n",
		      gpio_get_level(pwr_en));
	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "PWR_GOOD = %d\n",
		      gpio_get_level(pwr_good));
	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "POR_L_LOAD_L = %d\n",
		      gpio_get_level(por_l_load_l));
	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "FPGA_DONE = %d\n",
		      gpio_get_level(fpga_done));
	return 0;
}

/**
 * @brief Turn on the FPGA
 */
static int cmd_on(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "FPGA power on ...\n");
	fpgaboot_power_on();
	return 0;
}

/**
 * @brief Turn off the FPGA
 */
static int cmd_off(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "FPGA power off ...\n");
	fpgaboot_power_off();
	return 0;
}

/**
 * @brief Set the FPGA boot mode
 */
static int cmd_boot(const struct shell *shell, enum fpga_boot_mode mode,
		    const char *mode_str)
{
	int ret;

	ret = fpgaboot_set_boot_mode(mode);
	if (ret == 0) {
		shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
			      "FPGA boot mode set to %s\n", mode_str);
	} else if (ret == -EBUSY) {
		shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
			      "FPGA is busy. Try again in a few seconds.\n");
	} else {
		shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT,
			      "Unknown error %d.\n", ret);
	}
	return ret;
}

/**
 * @brief Set the FPGA boot mode to eMMC
 */
static int cmd_boot_emmc(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return cmd_boot(shell, FPGA_BOOT_EMMC, "eMMC");
}

/**
 * @brief Set the FPGA boot mode to QSPI
 */
static int cmd_boot_qspi(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return cmd_boot(shell, FPGA_BOOT_QSPI, "QSPI");
}

/**
 * @brief Set the FPGA boot mode to SDIO
 */
static int cmd_boot_sdio(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	return cmd_boot(shell, FPGA_BOOT_SDIO, "SDIO");
}
SHELL_STATIC_SUBCMD_SET_CREATE(
	boot_mode,
	SHELL_CMD(emmc, NULL, "set FPGA to boot from eMMC", cmd_boot_emmc),
	SHELL_CMD(qspi, NULL, "set FPGA to boot from QSPI", cmd_boot_qspi),
	SHELL_CMD(sdio, NULL, "set FPGA to boot from SDIO", cmd_boot_sdio),
	SHELL_SUBCMD_SET_END);
SHELL_STATIC_SUBCMD_SET_CREATE(
	fpga_cmds, SHELL_CMD(status, NULL, "get status", cmd_status),
	SHELL_CMD(on, NULL, "power on and boot", cmd_on),
	SHELL_CMD(off, NULL, "power off", cmd_off),
	SHELL_CMD(bootmode, &boot_mode, "set FPGA boot mode", NULL),
	SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_CMD_REGISTER(fpga, &fpga_cmds, "FPGAcommands", NULL);
