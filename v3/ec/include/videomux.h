/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef __VIDEOMUX_H
#define __VIDEOMUX_H

#include <zephyr.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The Chameleon v3 hardware has a series of muxes to route the HDMI or the
 * DisplayPort (after going through a DP/HDMI converter) signals to the
 * FPGA's MGTs or to an HDMI receiver (IT68051). There are two sets of
 * circuitry, one for each of the HDMI/DP combo jacks.
 *
 * The selections for the muxes are shown in the table below, along with the
 * reference designator on Proto0 hardware for the specific mux.
 *
 * For routing the DisplayPort signals, the following table applies. The
 * select pins on U3, U18, and U11 route the DP1 signals, while the select
 * pins on U22, U31, and U14 route the DP2 signals. Note that U10 and U29 are
 * not involved in routing the DP signals.
 *
 *  SW on       GPU_SEL on  GPU_SEL on
 *  PS8468      CBTL06GP213 CBTL06DP213
 *  demux       mux         mux
 *  U3          U18         U11         DP1
 *  U22         U31         U14         DP2
 *  ----------- ----------- ----------- -------
 *  0           0           don't care  IT68051
 *  1           don't care  0           FPGA
 *  all others........................  n/c
 *
 * For routing the HDMI signals, the following table applies. The select pins
 * on U10, U18, and U11 route the HDMI1 signals, while the select pins on
 * U29, U31, and U14 route the HDMI2 signals. Note that U3 and U22 are not
 * involved in routing the HDMI signals.
 *
 *  GPU_SEL on  GPU_SEL on  GPU_SEL on
 *  CBTL06GP213 CBTL06GP213 CBTL06DP213
 *  demux       mux         mux
 *  U10         U18         U11         HDMI1
 *  U29         U31         U14         HDMI2
 *  ----------- ----------- ----------- -------
 *  0           1           don't care  IT68051
 *  1           don't care  1           FPGA
 *  all others........................  n/c
 *
 * So, to connect the HDMI1 signal to the FPGA's MGTs and the DisplayPort1
 * signal to the HDMI receiver, set:
 *  1. GP213_IT68051P1_CH_SEL low (GPU_SEL on U18)
 *  2. DP1_PS8468_SW low (SW on U3)
 *  3. HDMI1_GP213_CH_SEL high (GPU_SEL on U10)
 *  4. SOMP1_MODE_SEL high (GPU_SEL on U11)
 */

enum video_source_t {
	DP1,
	DP2,
	HDMI1,
	HDMI2
};

enum video_dest_t {
	HDMI_RECEIVER,
	FPGA_MGT
};

/**
 * @brief Configure the muxes to route the vidoe signals
 *
 * @param src Source port to route, DP1, DP2, HDMI1, or HDMI2
 *
 * @param dest HDMI_RECIEVER to route the port's signals to the IT68051 HDMI
 * receiver, or FPGA to route the port's signals to the FPGA's MGTs.
 *
 * @retval
 * 0 Everything OK
 * @retval
 * -EINVAL Invalid port or selection
 */
int videomux_select(enum video_source_t src, enum video_dest_t dest);

#ifdef __cplusplus
}
#endif

#endif
