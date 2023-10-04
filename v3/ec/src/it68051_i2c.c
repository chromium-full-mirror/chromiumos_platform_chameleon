/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Based on code in iTE6805_I2C_RDWR.[ch], which is
 *  Copyright (c) 2023 ITE Tech. Inc.
 *  SPDX-License-Identifier: BSD-3-Clause
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/__assert.h>
#include "it68051_i2c.h"

LOG_MODULE_DECLARE(it68051);

/* I2C controller for the IT68051 */
static const struct device *ite_i2c =
	DEVICE_DT_GET(DT_PARENT(DT_NODELABEL(it68051_hdmi)));

/* I2C addresses for sub-functional blocks. */
#define ITE_HDMI_DEVICE DT_REG_ADDR(DT_NODELABEL(it68051_hdmi))
#define ITE_EDID_DEVICE DT_REG_ADDR(DT_NODELABEL(it68051_edid))

/* Count of I2C read/write errors */
static uint32_t i2c_error_count;

void it68051_chgbank(uint16_t bank)
{
	LOG_DBG("chgbank(%d)", bank);
	it68051_hdmi_write(0x0F, 0x07, bank & 0x07);
}

int it68051_edid_ram_write(uint8_t addr, uint8_t count, const uint8_t *p_data)
{
	return i2c_burst_write(ite_i2c, ITE_EDID_DEVICE, addr, p_data, count);
}

int it68051_edid_ram_read(uint8_t addr, uint8_t count, uint8_t *p_data)
{
	return i2c_burst_read(ite_i2c, ITE_EDID_DEVICE, addr, p_data, count);
}

uint8_t it68051_hdmi_read(uint8_t addr)
{
	uint8_t val;

	int res = i2c_burst_read(ite_i2c, ITE_HDMI_DEVICE, addr, &val, 1);

	if (res != 0) {
		i2c_error_count++;
		LOG_ERR("0x%02X read %02X FAILED, res=%d", ITE_HDMI_DEVICE,
			addr, res);
	} else {
		LOG_DBG("0x%02X read %02X == %02X", ITE_HDMI_DEVICE, addr, val);
	}

	return val;
}

void it68051_hdmi_write(uint8_t addr, uint8_t mask, uint8_t val)
{
	int res;

	__ASSERT((val & ~mask) == 0,
		 "Bits are set in val that are not set in mask");
	if (mask == 0xFF) {
		LOG_DBG("0x%02X REG %02X := 0x%02X", ITE_HDMI_DEVICE, addr,
			val);
		res = i2c_burst_write(ite_i2c, ITE_HDMI_DEVICE, addr, &val, 1);
		if (res != 0) {
			i2c_error_count++;
			LOG_ERR("0x%02X REG %02X := 0x%02X FAILED, res=%d",
				ITE_HDMI_DEVICE, addr, val, res);
		}
	} else {
		/* Do a read-modify-write using I2C and bit-wise operations. */
		uint8_t curr_val = it68051_hdmi_read(addr);
		uint8_t new_val = (curr_val & (~mask)) | (val & mask);

		LOG_DBG("0x%02X REG %02X := 0x%02X", ITE_HDMI_DEVICE, addr,
			new_val);
		res = i2c_burst_write(ite_i2c, ITE_HDMI_DEVICE, addr, &new_val,
				      1);
		if (res != 0) {
			i2c_error_count++;
			LOG_ERR("0x%02X REG %02X := 0x%02X FAILED, res=%d",
				ITE_HDMI_DEVICE, addr, val, res);
		}
	}
}

void it68051_hdmi_write_block(uint8_t addr, uint8_t *data, uint8_t count)
{
	LOG_DBG("0x%02X hdmirxbwr, addr = 0x%02X", ITE_HDMI_DEVICE, addr);
	LOG_HEXDUMP_DBG(data, count, "data");
	i2c_burst_write(ite_i2c, ITE_HDMI_DEVICE, addr, data, count);
}

uint32_t it68051_get_i2c_error_count(void)
{
	return i2c_error_count;
}

void it68051_reset_i2c_error_count(void)
{
	i2c_error_count = 0;
}
