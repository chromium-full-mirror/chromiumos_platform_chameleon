/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "io.h"

LOG_MODULE_REGISTER(main);

void main(void)
{
	int ret;

	ret = gpio_set_level(power_good_led, 1);
	if (ret < 0) {
		LOG_ERR("Failed to turn on POWER_GOOD, ret = %d.\n", ret);
	}
}
