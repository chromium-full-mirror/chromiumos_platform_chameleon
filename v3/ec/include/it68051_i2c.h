/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Based on code in iTE6805_I2C_RDWR.[ch]
 *  Copyright (c) 2023 ITE Tech. Inc.
 *  SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __IT68051_I2C_H
#define __IT68051_I2C_H

#include <zephyr/kernel.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Write to the IT68051 bank select register
 *
 * Based on code in chgbank in iTE6805_DRV.c
 *
 * @param bank Bank number to select
 */
void it68051_chgbank(uint16_t bank);

/**
 * @brief Write to the EDID RAM
 *
 * Based on code in edid_ram_wr in iTE6805_I2C_RDWR.c
 *
 * @param addr address in the EDID RAM to write
 * @param count number of bytes to write
 * @param p_data pointer to the data to write
 * @retval 0 success
 * @retval non-zero error code from i2c_burst_write
 */
int it68051_edid_ram_write(uint8_t addr, uint8_t count, const uint8_t *p_data);

/**
 * @brief Read from the EDID RAM
 *
 * @param addr address in the EDID RAM to read
 * @param count number of bytes to read
 * @param p_data pointer to store the data
 * @retval 0 success
 * @retval non-zero error code from i2c_burst_read
 */
int it68051_edid_ram_read(uint8_t addr, uint8_t count, uint8_t *p_data);

/**
 * @brief Read an IT68051 register
 *
 * Based on code in hdmirxrd in iTE6805_I2C_RDWR.c
 *
 * TODO(pfagerburg): Add a parameter for the register bank. Cache the current
 * register bank, and if the new bank is different, call chgbank. Update all
 * code, including it68051_init, to include the bank number and remove any
 * explicit writes to the bank select register from the init table.
 *
 * @param addr Register address
 *
 * @return The value from the register
 */
uint8_t it68051_hdmi_read(uint8_t addr);

/**
 * @brief Write to an IT68051 register, possibly with a mask
 *
 * Write to a register in the IT68051. In the case of a mask, perform
 * a read/modify/write.
 *
 * Based on code in hdmirxset in iTE6805_I2C_RDWR.c
 *
 * TODO(pfagerburg): Add a parameter for the register bank. Cache the current
 * register bank, and if the new bank is different, call chgbank. Update all
 * code, including it68051_init, to include the bank number and remove any
 * explicit writes to the bank select register from the init table.
 *
 * @param addr Register address
 * @param mask Bits to write. 0xFF to write the entire byte, something
 * other than 0xFF to read the register, mask the bits, and write the
 * resulting value.
 * @param val Value to write
 */
void it68051_hdmi_write(uint8_t addr, uint8_t mask, uint8_t val);

/**
 * @brief Write a block of data starting at a specific register
 *
 * @param addr Register address to start
 * @param data Pointer to data to write
 * @param count Count of bytes to write
 */
void it68051_hdmi_write_block(uint8_t addr, uint8_t *data, uint8_t count);

/**
 * @brief Return a count of errors seen in i2c read/write
 *
 * The i2c routines for the IT68051 keep track of the number of times there
 * is an error returned.
 *
 * @return the count of errors
 */
uint32_t it68051_get_i2c_error_count(void);

/**
 * @brief Reset the i2c error counter
 */
void it68051_reset_i2c_error_count(void);

#ifdef __cplusplus
}
#endif

#endif
