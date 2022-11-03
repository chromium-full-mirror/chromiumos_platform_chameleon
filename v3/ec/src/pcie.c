/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Interrupt handler for the PCIE_PERST pin to update SOM_PCIE_PERST_L when
 * PCIE_PERST changes.
 *
 * Note that PCIE_PERST is active-high, and there is an external 10K pull-up.
 * When the PERST_L signal from the PCIe connector is low (or undriven),
 * PCIE_PERST will be high, and we should drive SOM_PCIE_PERST_L low.
 * When the PERST_L signal from the PCIe connector is high, PCIE_PERST will
 * be low, and we should drive SOM_PCIE_PERST_L high.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/__assert.h>
#include "io.h"

LOG_MODULE_REGISTER(pcie);

static struct gpio_callback perst_cb_data;

/**
 * @brief ISR handler for PCIE_PERST changes
 *
 * When the ISR runs, read the value of PCIE_PERST and write the
 * complement to SOM_PCIE_PERST_L.
 *
 * @param dev Part of the Zephyr ISR API. Unused.
 * @param cb Part of the Zephyr ISR API. Unused.
 * @param pins Part of the Zephyr ISR API. Unused.
 */
static void perst_cb(const struct device *dev, struct gpio_callback *cb,
		     uint32_t pins)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(cb);
	ARG_UNUSED(pins);

	gpio_set_level(som_pcie_perst_l, !gpio_get_level(pcie_perst));
}

/**
 * @brief Initialize the PCIE_PERST ISR
 *
 * @param ptr Unused argument, required by SYS_INIT
 * @retval 0
 * No error
 * @retval Non-zero
 * Error code
 */
static int pcie_init(const struct device *ptr)
{
	ARG_UNUSED(ptr);

	int ret;

	/* Reconfigure SOM_PCIE_PERST_L for open-drain */
	ret = gpio_pin_configure(gpio_get_device(som_pcie_perst_l),
				 gpio_get_pin(som_pcie_perst_l),
				 GPIO_OUTPUT_HIGH | GPIO_OPEN_DRAIN);
	if (ret != 0) {
		LOG_ERR("Error %d: failed to configure SOM_PCIE_PERST_L for open-drain\n",
			ret);
		return ret;
	}

	/* Set SOM_PCIE_PERST_L to complement PCIE_PERST as an initial
	 * condition, so that if the value never changes and we don't get an
	 * interrupt, the value is still correct.
         */
	gpio_set_level(som_pcie_perst_l, !gpio_get_level(pcie_perst));

	/* Configure PCIE_PERST interrupt on a either edge. */
	ret = gpio_pin_interrupt_configure(gpio_get_device(pcie_perst),
					   gpio_get_pin(pcie_perst),
					   GPIO_INT_EDGE_BOTH);
	if (ret != 0) {
		LOG_ERR("Error %d: failed to configure interrupt on PCIE_PERST\n",
			ret);
		return ret;
	}
	gpio_init_callback(&perst_cb_data, perst_cb,
			   BIT(gpio_get_pin(pcie_perst)));
	ret = gpio_add_callback(gpio_get_device(pcie_perst), &perst_cb_data);
	if (ret != 0) {
		LOG_ERR("Error %d: failed to add callback on PCIE_PERST\n",
			ret);
		return ret;
	}

	return 0;
}
SYS_INIT(pcie_init, APPLICATION, 85);