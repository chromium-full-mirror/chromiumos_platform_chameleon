/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef __IO_H
#define __IO_H

#include <zephyr.h>
#include <drivers/gpio.h>

#ifdef __cplusplus
extern "C" {
#endif

enum gpio_signal {
	power_good_led,
	sd_mux_sel,
	sd_mux_en_l,
	usd_pwr_sel,
	usd_pwr_en,
	usd_cd_det,
	sysmon_sel,
	pwr_en,
	pwr_good,
	boot_mode1,
	boot_mode0,
	por_l_load_l,
	fpga_done,
	fpga_prot,
	fpga_comm0,
	tp126,
	tp125,
	board_version_2,
	board_version_1,
	board_version_0,
	exp_reset,
	exp_irq,
	gp213_it68051p1_ch_sel,
	dp1_ps8468_sw,
	hdmi1_gp213_ch_sel,
	somp1_mode_sel,
	gp213_it68051p0_ch_sel,
	dp2_ps8468_sw,
	hdmi2_gp213_ch_sel,
	somp2_mode_sel,
	dp1_ps8468_rst_l,
	dp2_ps8468_rst_l,
	dp1_hdmi_rst_l,
	dp2_hdmi_rst_l,
	it68051_en,
	it68051p0_pwr_det,
	it68051p1_pwr_det,
	it68051_rst_l,
	gp213_it68051p1_hpd,
	i2c2_int_l,
	dp1_auxp_det,
	dp1_auxn_det,
	dp2_auxp_det,
	dp2_auxn_det,
	hdmi1_pp3300,
	hdmi2_pp3300,
	dp1_mcu_hpd,
	dp2_mcu_hpd,
	dp_in_pwr_en,
	dp1_ps8468_mode,
	dp1_ps8468_cfg0,
	dp1_ps8468_cfg1,
	dp1_ps8468_cfg2,
	dp1_ps8468_cfg3,
	dp1_ps8468_cfg4,
	dp1_ps8468_eq0,
	dp1_ps8468_eq1,
	dp2_ps8468_mode,
	dp2_ps8468_cfg0,
	dp2_ps8468_cfg1,
	dp2_ps8468_cfg2,
	dp2_ps8468_cfg3,
	dp2_ps8468_cfg4,
	dp2_ps8468_eq0,
	dp2_ps8468_eq1,
};

/**
 * @brief Get the current value of a signal.
 *
 * @param signal	Signal to get
 * @return 0 if low, 1 if high.
 */
int gpio_get_level(enum gpio_signal signal);

/**
 * @brief Set the value of a signal.
 *
 * @param signal	Signal to set
 * @param value		New value for signal (0 = low, 1 = high)
 * @return 0 if successful, otherwise errno from gpio_pin_set
 */
int gpio_set_level(enum gpio_signal signal, int value);

/**
 * @brief Return the device pointer of a given GPIO signal.
 *
 * This allows code to use other Zephyr API calls such as configuring
 * for interrupts.
 *
 * @param signal    Signal to name
 * @returns device pointer for the GPIO
 */
const struct device *gpio_get_device(enum gpio_signal signal);

/**
 * Return the pin number of a given GPIO signal.
 *
 * This allows code to use other Zephyr API calls such as configuring
 * for interrupts.
 *
 * @param signal    Signal to name
 * @returns pin number for the GPIO
 */
gpio_pin_t gpio_get_pin(enum gpio_signal signal);

#ifdef __cplusplus
}
#endif

#endif
