/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include "hdlc.h"

pw::stream::SysIoWriter hdlc_writer;

K_MUTEX_DEFINE(hdlc_uart_mutex);
