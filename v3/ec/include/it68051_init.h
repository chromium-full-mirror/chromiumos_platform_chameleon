/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Based on code in iTE6805_DRV.c,  iTE6805_I2C_RDWR.h, and iTE6805_INI_Table.h
 *  Copyright (c) 2023 ITE Tech. Inc.
 *  SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __IT68051_INIT_H
#define __IT68051_INIT_H

#include <zephyr/kernel.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize the IT68051 with data provided by ITE.
 *
 * Based on code in iTE6805_Init_fsm in iTE6805_DRV.c
 *
 * @retval 0 success
 * @retval -ENODEV failed to get the I2C device to access the IT68051
 */
int it68051_init(void);

/**
 * @brief Get the RCLK value that it68051_oclk_cal() computed.
 *
 * @return RCLK value
 */
uint32_t it68051_get_rclk_value(void);

#ifdef __cplusplus
}
#endif

#endif
