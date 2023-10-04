/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Based on code in iTE6805_EDID.[ch] and iTE6805_EDID_Table.h
 *  Copyright (c) 2023 ITE Tech. Inc.
 *  SPDX-License-Identifier: BSD-3-Clause
 *
 * Functions for managing the IT68051 EDID RAM.
 */

#ifndef __IT68051_EDID_H
#define __IT68051_EDID_H

#include <zephyr/kernel.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Number of EDIDs that are available to select from the shell.
 */
#define EDID_COUNT 17

/*
 * Default EDID
 *
 * Be explicit about which EDID we want to use at start-up, instead of
 * using a magic number in the code.
 */
#define DEFAULT_EDID_IDX 8

/**
 * @brief Initialize the EDID RAM
 *
 * Based on code in iTE6805_EDID_Init in iTE6805_EDID.c
 */
void it68051_edid_init(void);

/**
 * @brief Set the active EDID
 *
 * The internal function `it68051_edid_init_ram` uses an index into
 * a table of EDIDs to determine which EDID to load into the IT68051.
 * This function changes that index. The caller is responsible for
 * turning off HPD, setting the index, calling `it68051_edid_init`
 * again, and then turning on HPD.
 *
 * @param idx Index into the EDID table for which one to select
 * @retval 0 success
 * @retval -EINVAL index was outside the range of the table
 */
int it68051_edid_select(int idx);

/**
 * @brief Initialize the EDID RAM block and related registers
 *
 * Based on code in iTE6805_EDID_RAMInitial in iTE6805_EDID.c
 *
 * @param p_edid pointer to 256-byte EDID data
 */
void it68051_edid_write_block(const uint8_t *p_edid);

/**
 * @brief Read the EDID RAM block
 *
 * Note that the caller is responsible for making sure that p_edid points
 * to at least 256 bytes of memory!
 *
 * @param p_edid pointer to where to put 256-byte EDID data
 */
void it68051_edid_read_block(uint8_t *p_edid);

#ifdef __cplusplus
}
#endif

#endif
