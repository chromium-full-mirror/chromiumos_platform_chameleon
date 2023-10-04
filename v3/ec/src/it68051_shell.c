/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Shell commands for controlling the IT68051 HDMI Receiver.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/shell/shell.h>
#include <stdlib.h>

#include "io.h"
#include "it68051.h"
#include "it68051_edid.h"
#include "it68051_i2c.h"
#include "it68051_init.h"

LOG_MODULE_DECLARE(it68051);

/*
 * How many seconds to wait after turning off HPD before turning it
 * back on again, after changing the EDID.
 */
#define EDID_CHANGE_DELAY 5

/**
 * @brief Read the ID registers and display them
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 */
static int cmd_identify(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	it68051_chgbank(0);

	uint8_t vendor_id_0 = it68051_hdmi_read(0x00);
	uint8_t vendor_id_1 = it68051_hdmi_read(0x01);
	uint8_t device_id_0 = it68051_hdmi_read(0x02);
	uint8_t device_id_1 = it68051_hdmi_read(0x03);
	uint8_t chip_id = it68051_hdmi_read(0x04);

	/* Should be 54 49 */
	shell_fprintf(shell, SHELL_NORMAL, "Vendor ID = %02x %02x\n",
		      vendor_id_0, vendor_id_1);
	/* Should be 05 68 */
	shell_fprintf(shell, SHELL_NORMAL, "Device ID = %02x %02x\n",
		      device_id_0, device_id_1);
	shell_fprintf(shell, SHELL_NORMAL, "Chip ID = %02x\n", chip_id);

	return 0;
}

/**
 * @brief Re-initialize the IT68051
 *
 * If we put the chip into reset (using `io set` commands), when we take it
 * out of reset, we need to re-init the chip.
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 */
static int cmd_init(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	/* Release reset on the IT68051 */
	gpio_set_level(it68051_rst_l, 1);

	/* Initialize the IT68051. If that fails, return early. */
	int retval = it68051_init();

	if (retval != 0) {
		shell_fprintf(shell, SHELL_NORMAL,
			      "init_68051 failed, retval =%d\n", retval);
	}

	return retval;
}

/**
 * @brief Read the status registers and display them
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 */
static int cmd_status(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_NORMAL, "Link: %s\n",
		      it68051_get_link_active() ? "active" : "inactive");
	shell_fprintf(shell, SHELL_NORMAL, "IT68051 status registers\n");
	it68051_chgbank(0);
	for (uint8_t reg = 0x13; reg <= 0x1e; ++reg) {
		uint8_t val = it68051_hdmi_read(reg);

		shell_fprintf(shell, SHELL_NORMAL, "[0x%02x] = 0x%02x\n", reg,
			      val);
	}

	return 0;
}

/**
 * @brief Read the GPIOs and display them
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 */
static int cmd_gpio(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	shell_fprintf(shell, SHELL_NORMAL, "it68051p0_pwr_det = %d\n",
		      gpio_get_level(it68051p0_pwr_det));
	shell_fprintf(shell, SHELL_NORMAL, "it68051p1_pwr_det = %d\n",
		      gpio_get_level(it68051p1_pwr_det));
	shell_fprintf(shell, SHELL_NORMAL, "it68051_rst_l = %d\n",
		      gpio_get_level(it68051_rst_l));
	return 0;
}

/**
 * @brief Set the HPD output for the selected port
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. [-1] is the port, [0] is the
 * value to set.
 *
 * @retval 0 if successful.
 * @retval -EINVAL if parameters were invalid
 */
static int cmd_hpd(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);

	int port = 0;
	bool hpd = false;

	if (!strcmp(argv[-1], "port1")) {
		port = PORT1;
	} else if (!strcmp(argv[-1], "port2")) {
		port = PORT2;
	} else {
		shell_error(shell, "%s: unknown parameter: %s", __func__,
			    argv[-1]);
		return -EINVAL;
	}

	if (!strcmp(argv[0], "on")) {
		hpd = true;
	} else if (!strcmp(argv[0], "1")) {
		hpd = true;
	} else if (!strcmp(argv[0], "off")) {
		hpd = false;
	} else if (!strcmp(argv[0], "0")) {
		hpd = false;
	} else {
		shell_error(shell, "%s: unknown parameter: %s", __func__,
			    argv[0]);
		return -EINVAL;
	}

	it68051_set_hpd(port, hpd);
	return 0;
}

/**
 * @brief Select the active port
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. [0] is the port.
 *
 * @retval 0 if successful.
 * @retval -EINVAL if parameters were invalid
 */
static int cmd_select(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);

	int port = 0;

	if (!strcmp(argv[0], "port1")) {
		port = PORT1;
	} else if (!strcmp(argv[0], "port2")) {
		port = PORT2;
	} else {
		shell_error(shell, "%s: uknown parameter: %s", __func__,
			    argv[0]);
		return -EINVAL;
	}
	it68051_port_select(port);
	return 0;
}

/**
 * @brief Show the TTL Output Control registers
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 */
static int cmd_ttl_show(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	uint8_t addrs[] = { 0xBD, 0xC0, 0xC1, 0xC5, 0xC6 };
	uint8_t idx;
	uint8_t val;

	it68051_chgbank(1);
	for (idx = 0; idx < ARRAY_SIZE(addrs); idx++) {
		val = it68051_hdmi_read(addrs[idx]);
		shell_fprintf(shell, SHELL_NORMAL, "Reg 0x1%02x = 0x%02x\n",
			      addrs[idx], val);
	}
	it68051_chgbank(0);
	return 0;
}

/**
 * @brief Configure the TTL outputs for SDR or DDR
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 * @retval -EINVAL if parameters were invalid
 */
static int cmd_ttl_sdr_ddr(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);

	enum video_data_path sdr_ddr;

	if (!strcmp(argv[0], "sdr")) {
		sdr_ddr = TTL_SDR;
	} else if (!strcmp(argv[0], "ddr")) {
		sdr_ddr = TTL_DDR;
	} else {
		shell_error(shell, "%s: uknown parameter: %s", __func__,
			    argv[0]);
		return -EINVAL;
	}

	shell_fprintf(shell, SHELL_NORMAL, "Configure TTL for %s\n",
		      sdr_ddr == TTL_SDR ? "SDR" : "DDR");
	it68051_set_ttl_video_path(sdr_ddr, TTL_SEP_SYNC, COLOR_FORMAT_RGB);
	return 0;
}

/**
 * @brief Configure the TTL outputs for single- or dual-pixel mode
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 *
 * @retval 0 if successful.
 * @retval -EINVAL if parameters were invalid
 */
static int cmd_ttl_single_dual(const struct shell *shell, size_t argc,
			       char **argv)
{
	ARG_UNUSED(argc);

	enum pixel_mode mode;

	if (!strcmp(argv[0], "single")) {
		mode = MODE_SINGLE;
	} else if (!strcmp(argv[0], "dual")) {
		mode = MODE_DUAL;
	} else {
		shell_error(shell, "%s: uknown parameter: %s", __func__,
			    argv[0]);
		return -EINVAL;
	}

	shell_fprintf(shell, SHELL_NORMAL, "Configure TTL for %s-pixel\n",
		      mode == MODE_SINGLE ? "single" : "dual");
	it68051_set_pixel_mode(mode);
	return 0;
}

/**
 * @brief Read from an IT68051 register
 *
 * Allows reading from any register by handling the chgbank and read in
 * one function from the shell.
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command.
 * @param argv Arguments for this shell command.
 *
 * @retval 0 if successful.
 */
static int cmd_read(const struct shell *shell, size_t argc, char **argv)
{
	/* The register value is in argv[1]. */
	unsigned long int full_reg = strtoul(argv[1], NULL, 16);
	uint8_t reg = full_reg & 0xFF;
	uint8_t bank = (full_reg >> 8) & 0x07;

	it68051_chgbank(bank);
	uint8_t value = it68051_hdmi_read(reg);

	shell_fprintf(shell, SHELL_NORMAL, "0x%02x\n", value);
	return 0;
}

/**
 * @brief Write to an IT68051 register
 *
 * Allows writing to any register by handling the chgbank and write in
 * one function from the shell.
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command.
 * @param argv Arguments for this shell command.
 *
 * @retval 0 if successful.
 */
static int cmd_write(const struct shell *shell, size_t argc, char **argv)
{
	/* The register value is in argv[1]. */
	unsigned long int full_reg = strtoul(argv[1], NULL, 16);
	uint8_t reg = full_reg & 0xFF;
	uint8_t bank = (full_reg >> 8) & 0x07;
	/* Value to write is in argv[2]. */
	uint8_t value = (uint8_t)strtoul(argv[2], NULL, 16);

	it68051_chgbank(bank);
	it68051_hdmi_write(reg, 0xff, value);
	return 0;
}

/**
 * @brief Select an EDID
 *
 * Turn off HPD, re-load the EDID RAM with the selected EDID, then
 * turn on HPD again.
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command.
 * @param argv Arguments for this shell command.
 *
 * @retval 0 if successful.
 */
static int cmd_edid(const struct shell *shell, size_t argc, char **argv)
{
	/* The EDID index is in argv[1]. */
	int idx = atoi(argv[1]);

	if ((idx < 0) || (idx >= EDID_COUNT)) {
		shell_fprintf(
			shell, SHELL_NORMAL,
			"EDID index out of range; must be between 0 and %d\n",
			EDID_COUNT - 1);

		return -EINVAL;
	}

	/* Save HPD status and then turn off before writing the EDID */
	bool hpd_port2 = it68051_get_hpd(PORT2);
	bool hpd_port1 = it68051_get_hpd(PORT1);

	it68051_set_hpd(PORT2, false);
	it68051_set_hpd(PORT1, false);

	if (hpd_port2 || hpd_port1) {
		/* Wait 5 sec for the device to detect the monitor is gone. */
		shell_fprintf(shell, SHELL_NORMAL, "Wait for disconnect ");

		for (int delay = 0; delay < EDID_CHANGE_DELAY; delay++) {
			shell_fprintf(shell, SHELL_NORMAL, ".");
			k_msleep(1000);
		}
		shell_fprintf(shell, SHELL_NORMAL, "\n");
	}

	it68051_edid_select(idx);
	it68051_edid_init();

	it68051_set_hpd(PORT2, hpd_port2);
	it68051_set_hpd(PORT1, hpd_port1);
	return 0;
}

/**
 * @brief Convert an ASCII hex digit into an int
 *
 * @param ch ASCII hex character
 *
 * @retval int representing the value
 * @retval -1 if not a hex digit
 */
static int8_t ascii_hex_to_int(char ch)
{
	if ((ch >= '0') && (ch <= '9')) {
		return (ch - '0');
	} else if ((ch >= 'A') && (ch <= 'F')) {
		return (ch - 'A' + 10);
	} else if ((ch >= 'a') && (ch <= 'f')) {
		return (ch - 'a' + 10);
	} else {
		return 0;
	}
}

#define EDID_SIZE 256

/**
 * @brief Write a raw EDID to the EDID RAM
 *
 * Turn off HPD, re-load the EDID RAM with the binary data, then
 * turn on HPD again.
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command.
 * @param argv Arguments for this shell command.
 *
 * @retval 0 if successful.
 */
static int cmd_raw_edid(const struct shell *shell, size_t argc, char **argv)
{
	/*
	 * Decode the EDID data as an ASCII hex string in argv[1] into an
	 * array of bytes.
	 */
	uint8_t edid[EDID_SIZE];
	uint16_t idx;
	const char *hex = argv[1];

	for (idx = 0; idx < EDID_SIZE; idx++) {
		int8_t nib1 = ascii_hex_to_int(hex[idx * 2]);
		int8_t nib2 = ascii_hex_to_int(hex[idx * 2 + 1]);

		if ((nib1 < 0) || (nib2 < 0)) {
			LOG_ERR("Invalid hex data at idx %d, '%c%c'", idx * 2,
				hex[idx * 2], hex[idx * 2 + 1]);
			return -EINVAL;
		}
		edid[idx] = (nib1 << 4) | nib2;
	}

	/* Save HPD status and then turn off before writing the EDID */
	bool hpd_port2 = it68051_get_hpd(PORT2);
	bool hpd_port1 = it68051_get_hpd(PORT1);

	it68051_set_hpd(PORT2, false);
	it68051_set_hpd(PORT1, false);

	if (hpd_port2 || hpd_port1) {
		/* Wait 5 sec for the device to detect the monitor is gone. */
		shell_fprintf(shell, SHELL_NORMAL, "Wait for disconnect ");

		for (int delay = 0; delay < EDID_CHANGE_DELAY; delay++) {
			shell_fprintf(shell, SHELL_NORMAL, ".");
			k_msleep(1000);
		}
		shell_fprintf(shell, SHELL_NORMAL, "\n");
	}

	it68051_edid_write_block(edid);

	it68051_set_hpd(PORT2, hpd_port2);
	it68051_set_hpd(PORT1, hpd_port1);

	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(hpd_on_off,
			       SHELL_CMD(on, NULL, "Turn on", cmd_hpd),
			       SHELL_CMD(1, NULL, "Turn on", cmd_hpd),
			       SHELL_CMD(off, NULL, "Turn off", cmd_hpd),
			       SHELL_CMD(0, NULL, "Turn off", cmd_hpd),
			       SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_STATIC_SUBCMD_SET_CREATE(
	hpd_port1_port2,
	SHELL_CMD(port1, &hpd_on_off, "External port #1 (IT68051 P1)", NULL),
	SHELL_CMD(port2, &hpd_on_off, "External port #2 (IT68051 P0)", NULL),
	SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_STATIC_SUBCMD_SET_CREATE(
	select_port1_port2,
	SHELL_CMD(port1, NULL, "External port #1 (IT68051 P1)", cmd_select),
	SHELL_CMD(port2, NULL, "External port #2 (IT68051 P0)", cmd_select),
	SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_STATIC_SUBCMD_SET_CREATE(
	ttl_cmds,
	SHELL_CMD(show, NULL, "Show TTL output registers", cmd_ttl_show),
	SHELL_CMD(sdr, NULL, "Use single data rate pixel clock",
		  cmd_ttl_sdr_ddr),
	SHELL_CMD(ddr, NULL, "Use double data rate pixel clock",
		  cmd_ttl_sdr_ddr),
	SHELL_CMD(single, NULL, "Use single-pixel mode", cmd_ttl_single_dual),
	SHELL_CMD(dual, NULL, "Use dual-pixel mode", cmd_ttl_single_dual),
	SHELL_SUBCMD_SET_END /* Array terminated. */
);
SHELL_STATIC_SUBCMD_SET_CREATE(
	it68051_cmds, SHELL_CMD(id, NULL, "get chip ID", cmd_identify),
	SHELL_CMD(init, NULL, "init/re-init the chip", cmd_init),
	SHELL_CMD(status, NULL, "get status", cmd_status),
	SHELL_CMD(gpio, NULL, "dump GPIO values", cmd_gpio),
	SHELL_CMD(hpd, &hpd_port1_port2, "set Hot Plug Detect", NULL),
	SHELL_CMD(select, &select_port1_port2, "select port", NULL),
	SHELL_CMD(ttl, &ttl_cmds, "show TTL Output registers", NULL),
	SHELL_CMD_ARG(read, NULL, "read a register", cmd_read, 2, 0),
	SHELL_CMD_ARG(write, NULL, "write to register", cmd_write, 3, 0),
	SHELL_CMD_ARG(edid, NULL, "select an EDID", cmd_edid, 2, 0),
	SHELL_CMD_ARG(raw_edid, NULL, "write a complete EDID", cmd_raw_edid, 2,
		      0),
	SHELL_SUBCMD_SET_END);
SHELL_CMD_REGISTER(it68051, &it68051_cmds, "IT68051 commands", NULL);
