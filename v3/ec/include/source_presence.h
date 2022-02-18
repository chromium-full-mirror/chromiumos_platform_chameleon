/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef __SOURCE_PRESENCE_H
#define __SOURCE_PRESENCE_H

#include <zephyr.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Determing if DisplayPort 1 has a signal present
 *
 * Using the state of the AUX signals, determine if a DisplayPort source
 * is connected.
 * When AUXN==0 and AUXP==1, there is no source.
 * When AUXN==1 and AUXP==0, a source is connected.
 *
 * @retval true if DisplayPort source is connected
 * @retval false if there is no DisplayPort source
 */
bool get_dp1_present(void);

/**
 * @brief Determing if DisplayPort 2 has a signal present
 *
 * See get_dp1_present for details.
 *
 * @retval true if DisplayPort source is connected
 * @retval false if there is no DisplayPort source
 */

bool get_dp2_present(void);

#ifdef __cplusplus
}
#endif

#endif
