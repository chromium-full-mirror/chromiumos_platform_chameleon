/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include <sys/printk.h>

#include "io.h"

void main(void)
{
	int ret;

	ret = gpio_set_level(power_good_led, 1);
	if (ret < 0) {
		printk("Failed to turn on POWER_GOOD, ret = %d.\n", ret);
	}
}
