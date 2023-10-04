/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Portions based on code in various iTE6805_*.[ch]
 *  Copyright (c) 2023 ITE Tech. Inc.
 *  SPDX-License-Identifier: BSD-3-Clause
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/logging/log.h>
#include <stdlib.h>
#include "it68051.h"
#include "it68051_edid.h"
#include "it68051_i2c.h"

LOG_MODULE_DECLARE(it68051);

static uint32_t rclk_value;
static uint8_t cec_timeunit;

/**
 * @brief Initialize the CAOF
 *
 * I don't know what a CAOF is, but we have to initialize it, and ITE
 * provided the code.
 *
 * Based on code in iTE6805_Init_CAOF in iTE6805_DRV.c.
 */
static void it68051_init_caof(void)
{
	LOG_DBG("iTE6805_Init_CAOF");
	uint8_t reg08, reg0d;
	uint8_t port0_status;
	uint8_t port1_status;
	uint8_t port0_int;
	uint8_t port1_int;
	uint8_t waitcnt, failcnt;

	it68051_chgbank(3);
	it68051_hdmi_write(0x3A, 0x80, 0x00); /* Reg_CAOFTrg low */
	it68051_hdmi_write(0xA0, 0x80, 0x80);
	it68051_hdmi_write(0xA1, 0x80, 0x80);
	it68051_hdmi_write(0xA2, 0x80, 0x80);
	it68051_hdmi_write(0xA4, 0x08, 0x08); /*IT6805Bx change */

	it68051_hdmi_write(0x3B, 0xC0, 0x00); /* Reg_ENSOF, Reg_ENCAOF */
	/* set Reg_PHSELEN high for read back sof value registers */
	it68051_hdmi_write(0xA7, 0x10, 0x10);
	it68051_hdmi_write(0x48, 0x80, 0x80);
	it68051_chgbank(0);
	/* Disable MHL AutoPWD */
	it68051_hdmi_write(0x29, 0x01, 0x01);
	/* Inverse COF CLK of Port0, CAOFRST */
	it68051_hdmi_write(0x2A, 0x41, 0x41);
	k_msleep(10);
	it68051_hdmi_write(0x2A, 0x40, 0x00);
	/* IPLL RST */
	it68051_hdmi_write(0x24, 0x04, 0x04);
	/* Disable AFE PWD */
	it68051_hdmi_write(0x25, 0xff, 0x00);
	it68051_hdmi_write(0x26, 0xff, 0x00);
	it68051_hdmi_write(0x27, 0xff, 0x00);
	it68051_hdmi_write(0x28, 0xff, 0x00);
	/*disable PLLBufRst */
	it68051_hdmi_write(0x3C, 0x10, 0x00);
	/*---------------------------------------- */
	/* Port 1 */
	it68051_chgbank(7);
	it68051_hdmi_write(0x3A, 0x80, 0x00); /* Reg_CAOFTrg low */
	it68051_hdmi_write(0xA0, 0x80, 0x80);
	it68051_hdmi_write(0xA1, 0x80, 0x80);
	it68051_hdmi_write(0xA2, 0x80, 0x80);
	it68051_hdmi_write(0xA4, 0x08, 0x08); /*IT6805Bx change */

	it68051_hdmi_write(0x3B, 0xC0, 0x00); /* Reg_ENSOF, Reg_ENCAOF */
	/* set Reg_PHSELEN high for read back sof value registers */
	it68051_hdmi_write(0xA7, 0x10, 0x10);
	it68051_hdmi_write(0x48, 0x80, 0x80);

	it68051_chgbank(0);
	/* CAOF RST, inverse CAOF CLK */
	it68051_hdmi_write(0x32, 0x41, 0x41);
	k_msleep(10);
	it68051_hdmi_write(0x32, 0x40, 0x00);
	/* IPLL RST */
	it68051_hdmi_write(0x2C, 0x04, 0x04);
	/* Disable AFE PWD */
	it68051_hdmi_write(0x2D, 0xff, 0x00);
	it68051_hdmi_write(0x2E, 0xff, 0x00);
	it68051_hdmi_write(0x2F, 0xff, 0x00);
	it68051_hdmi_write(0x30, 0xff, 0x00);
	it68051_chgbank(4);
	/*disable PLLBufRst */
	it68051_hdmi_write(0x3C, 0x10, 0x00);
	/*---------------------------------------- */
	/* Port 0 */
	it68051_chgbank(3);
	it68051_hdmi_write(0x3A, 0x80, 0x80); /* Reg_CAOFTrg high */
	/* Port 1 */
	it68051_chgbank(7);
	it68051_hdmi_write(0x3A, 0x80, 0x80); /* Reg_CAOFTrg high */

	/* wait for INT Done */
	it68051_chgbank(0);
	reg08 = it68051_hdmi_read(0x08) & 0x30;
	reg0d = it68051_hdmi_read(0x0D) & 0x30;
	waitcnt = 0;
	failcnt = 0;
	while (reg08 == 0x00 || reg0d == 0x00) {
		reg08 = it68051_hdmi_read(0x08) & 0x30;
		reg0d = it68051_hdmi_read(0x0D) & 0x30;
		LOG_DBG("Wait for CAOF Done!!!!!!");
		LOG_DBG(" reg08= %x,  reg0d=%x .......................",
			(int)it68051_hdmi_read(0x08),
			(int)it68051_hdmi_read(0x0D));
		if (waitcnt > 4) {
			LOG_WRN("CAOF Fail to Finish!!");
			if (reg08 == 0x00) {
				it68051_hdmi_write(0x2A, 0x40, 0x40);
				k_msleep(10);
				it68051_hdmi_write(0x2A, 0x40, 0x00);
			}
			if (reg0d == 0x00) {
				it68051_hdmi_write(0x32, 0x40, 0x40);
				k_msleep(10);
				it68051_hdmi_write(0x32, 0x40, 0x00);
			}
			waitcnt = 0;
			failcnt++;
		}
		if (failcnt > 5) {
			LOG_WRN("CAOF Fail !!");
			if (reg08 == 0x00) {
				it68051_chgbank(3);
				it68051_hdmi_write(0x3A, 0x80, 0x00);
				it68051_chgbank(0);
				it68051_hdmi_write(0x2A, 0x40, 0x40);
				k_msleep(10);
				it68051_hdmi_write(0x2A, 0x40, 0x00);
			}
			if (reg0d == 0x00) {
				it68051_chgbank(7);
				it68051_hdmi_write(0x3A, 0x80, 0x00);
				it68051_chgbank(0);
				it68051_hdmi_write(0x32, 0x40, 0x40);
				k_msleep(10);
				it68051_hdmi_write(0x32, 0x40, 0x00);
			}
			break;
		}
		k_msleep(10);
		waitcnt++;
	}
	it68051_chgbank(3);
	port0_status = (it68051_hdmi_read(0x5A) << 4) +
		       (it68051_hdmi_read(0x59) & 0x0F);
	port0_int = it68051_hdmi_read(0x59) & 0xC0;
	it68051_chgbank(7);
	port1_status = (it68051_hdmi_read(0x5A) << 4) +
		       (it68051_hdmi_read(0x59) & 0x0F);
	port1_int = it68051_hdmi_read(0x59) & 0xC0;
	LOG_DBG("Port 0 CAOF Int =%x , CAOF Status=%3x", port0_int,
		port0_status);
	LOG_DBG("Port 1 CAOF Int =%x , CAOF Status=%3x", port1_int,
		port1_status);

	/* De-assert Port 0 */
	it68051_chgbank(0);
	it68051_hdmi_write(0x08, 0x30, 0x30);
	it68051_hdmi_write(0x0D, 0x30, 0x30);
	/* Enable MHL AutoPWD */
	it68051_hdmi_write(0x29, 0x01, 0x00);
	/* IPLL RST low */
	it68051_hdmi_write(0x24, 0x04, 0x00);
	/*Enable PLLBufRst */
	it68051_hdmi_write(0x3C, 0x10, 0x10);
	/* De-assert Port 1 */
	/* Port 1 IPLL RST low */
	it68051_hdmi_write(0x2C, 0x04, 0x00);
	/* Port 1 Enable PLLBufRst */
	it68051_chgbank(4);
	it68051_hdmi_write(0x3C, 0x10, 0x10);

	it68051_chgbank(3);
	it68051_hdmi_write(0x3A, 0x80, 0x00); /* Reg_CAOFTrg low */
	it68051_hdmi_write(0xA0, 0x80, 0x00);
	it68051_hdmi_write(0xA1, 0x80, 0x00);
	it68051_hdmi_write(0xA2, 0x80, 0x00);
	it68051_chgbank(7);
	it68051_hdmi_write(0x3A, 0x80, 0x00); /* Reg_CAOFTrg low */
	it68051_hdmi_write(0xA0, 0x80, 0x00);
	it68051_hdmi_write(0xA1, 0x80, 0x00);
	it68051_hdmi_write(0xA2, 0x80, 0x00);
	it68051_chgbank(0);
}

/**
 * @brief Read the OCLK
 *
 * Based on code in iTE6805_OCLK_Load in iTE6805_DRV.c
 *
 * @return OCLK value
 */
static uint32_t it68051_oclk_load(void)
{
	LOG_DBG("iTE6805_OCLK_Load");
	uint8_t read_block;
	uint32_t freq;
	uint8_t buff[4];

	it68051_chgbank(0);
	it68051_hdmi_write(0xF8, 0xff, 0xC3);
	it68051_hdmi_write(0xF8, 0xff, 0xA5);
	/* reg34[0] to prevent HW gatting something. */
	it68051_hdmi_write(0x34, 0xff, 0x00);

	it68051_chgbank(1);
	it68051_hdmi_write(0x5F, 0xff, 0x04);
	it68051_hdmi_write(0x5F, 0xff, 0x05);
	it68051_hdmi_write(0x58, 0xff, 0x12);
	it68051_hdmi_write(0x58, 0xff, 0x02);
	it68051_hdmi_write(0x57, 0xff, 0x01);

	it68051_hdmi_write(0x50, 0xff, 0x00);
	it68051_hdmi_write(0x51, 0xff, 0x00);
	it68051_hdmi_write(0x54, 0xff, 0x04);
	buff[0] = it68051_hdmi_read(0x61);
	buff[1] = it68051_hdmi_read(0x62);

	it68051_hdmi_write(0x50, 0xff, 0x00);
	it68051_hdmi_write(0x51, 0xff, 0x01);
	it68051_hdmi_write(0x54, 0xff, 0x04);
	buff[2] = it68051_hdmi_read(0x61);
	buff[3] = it68051_hdmi_read(0x62);

	if (buff[0] == 0xFF && buff[1] == 0xFF && buff[2] == 0x00 &&
	    buff[3] == 0x00) {
		read_block = 0x04;
	} else {
		read_block = 0x00;
	}

	it68051_hdmi_write(0x50, 0xff, read_block);
	it68051_hdmi_write(0x51, 0xff, 0xb0);
	it68051_hdmi_write(0x54, 0xff, 0x04);
	buff[0] = it68051_hdmi_read(0x61);
	buff[1] = it68051_hdmi_read(0x62);
	it68051_hdmi_write(0x50, 0xff, read_block);
	it68051_hdmi_write(0x51, 0xff, 0xb1);
	it68051_hdmi_write(0x54, 0xff, 0x04); /* trigger read. */
	buff[2] = it68051_hdmi_read(0x61);
	buff[3] = it68051_hdmi_read(0x62);

	LOG_DBG("read 0x61=0x%02X", (int)buff[0]);
	LOG_DBG("read 0x62=0x%02X", (int)buff[1]);
	LOG_DBG("read 0x61=0x%02X", (int)buff[2]);
	LOG_DBG("read 0x62=0x%02X", (int)buff[3]);
	freq = (uint32_t)buff[0];
	freq += ((uint32_t)buff[1]) << 8;
	freq += ((uint32_t)buff[2]) << 16;

	if ((buff[3] & 0xC0) == 0xC0) {
		freq /= 100;
	}

	if ((freq > 70000) || (freq < 25000)) {
		LOG_DBG(" Readback value invalid: 0x%08X, use typical value.",
			freq);
		freq = 39000;
	} else {
		LOG_DBG(" Readback value valid: 0x%08X (%dKHz)", freq, freq);
	}

	it68051_hdmi_write(0x5F, 0xff, 0x00);
	it68051_chgbank(0);
	it68051_hdmi_write(0xF8, 0xff, 0x00);

	return (uint32_t)freq;
}

/**
 * @brief Calibrate OCLK
 *
 * Based on code in iTE6805_OCLK_Cal in iTE6805_DRV.c
 */

static void it68051_oclk_cal(void)
{
	LOG_DBG("iTE6805_OCLK_Cal");
	uint32_t t1usint, t1usflt;
	uint32_t oscclk, cpoclk;
	uint8_t xp;
	uint32_t wclk_valid_num;
	uint32_t wclk_high_num, wclk_high_num_b, wclk_high_num_c;
	uint32_t temp;
	uint32_t wclk_high_ext;

	cpoclk = it68051_oclk_load();
	LOG_DBG("cpoclk=%d.%03d MHz", cpoclk / 1000, cpoclk % 1000);

	it68051_chgbank(3);
	it68051_hdmi_write(0xAA, 0x1f, 0x0C);
	it68051_chgbank(0);

	oscclk = cpoclk; /* assume after 3AA adjust, it must be 41000 */
	rclk_value = oscclk / 2; /* 20 MHz */

	cec_timeunit = (uint8_t)(rclk_value / 160);
	/*
	 * use RCLK/160 instead  of OCLK/320,
	 * because timeunit last step came to RCLK
	 */
	LOG_DBG("cec_timeunit (T100us) = %X", (int)cec_timeunit);

	temp = rclk_value;
	rclk_value = rclk_value + rclk_value / 10; /* 20170327 MHL CTS */
	LOG_DBG("rclk_value=%d.%02d MHz", rclk_value / 1000,
		(rclk_value % 1000) / 10);
	t1usint = rclk_value / 1000;
	t1usflt = (rclk_value % 1000) * 256 / 1000;
	it68051_hdmi_write(0x91, 0x3F, t1usint & 0x3F);
	it68051_hdmi_write(0x92, 0xff, t1usflt);
	LOG_DBG("1us Timer reg91=%02x, reg92=%02x", it68051_hdmi_read(0x91),
		it68051_hdmi_read(0x92));
	rclk_value = temp; /* 20170327 MHL CTS add for CTS (RCLK*=1.1) */

	/*
	 * 2017/11/24 add for B0/B1 chip by Emily mail
	 * ( B1 Software change: SCDC RR relative register )
	 */
	xp = rclk_value / 100; /* 40us hold */
	if (it68051_get_chip_id() == 0xB0) {
		it68051_chgbank(3);
		/* to adjust stop/start hold time */
		it68051_hdmi_write(0xFA, 0xff, xp);
	}
	if (it68051_get_chip_id() == 0xB1) {
		it68051_chgbank(1);
		it68051_hdmi_write(0xFD, 0xff, xp);
		/* bus free wait time when rr test dly<4 ms */
		it68051_hdmi_write(0xFE, 0x20, 0x00);
		/* 1msto timer (D[3:0]* 80us) <0xC0 */
		it68051_hdmi_write(0xFE, 0x0F, 0x0C);
		/*  use internal 10ms timer */
		it68051_hdmi_write(0xFE, 0x10, 0x10);
		it68051_hdmi_write(0xFE, 0x80, 0x80); /*  use RR_period */
	}
	it68051_chgbank(0);

	/* IT6805Bx/Ax change for Reg0x44h, Reg0x45h, Reg0x46h and Reg0x47h */
	wclk_valid_num = oscclk / 312;
	it68051_hdmi_write(0x45, 0xff, wclk_valid_num);

	wclk_high_num = wclk_valid_num / 5;
	it68051_hdmi_write(0x44, 0xff, wclk_high_num);

	wclk_high_num_b = oscclk / 2320; /* 2320.185 */
	wclk_high_num_c = oscclk / 5312; /* 5312.084 */
	temp = (((wclk_high_num_b * 100) % 100) / 50);
	wclk_high_ext = (int)(temp);
	it68051_hdmi_write(0x46, 0xff,
			   (wclk_high_ext << 6) + ((int)wclk_high_num_b));

	temp = ((wclk_high_num_c * 100) % 100) / 25;
	wclk_high_ext = (int)(temp);
	it68051_hdmi_write(0x47, 0xff,
			   (wclk_high_ext << 6) + ((int)wclk_high_num_c));

	it68051_chgbank(0);
	LOG_DBG("reg 0x91=0x%02X", it68051_hdmi_read(0x91));
	LOG_DBG("reg 0x92=0x%02X", it68051_hdmi_read(0x92));
	LOG_DBG("reg 0x44=0x%02X", it68051_hdmi_read(0x44));
	LOG_DBG("reg 0x45=0x%02X", it68051_hdmi_read(0x45));
	LOG_DBG("reg 0x46=0x%02X", it68051_hdmi_read(0x46));
	LOG_DBG("reg 0x47=0x%02X", it68051_hdmi_read(0x47));
}

/*
 * Register value initialization for IT68051, based loosely on sample code
 * provided by ITE in iTE6805_I2C_RDWR.h and iTE6805_INI_Table.h
 */

struct it68051_reg {
	uint8_t addr;
	uint8_t mask;
	uint8_t value;
};

struct it68051_reg const it68051_init_table[] = {
	/* clang-format off */
	{ 0x0F, 0xFF, 0x00 },
	{ 0x22, 0xFF, 0x08 },
	{ 0x22, 0xFF, 0x17 },
	{ 0x23, 0xFF, 0x1F },
	{ 0x2B, 0xFF, 0x1F },
	{ 0x24, 0xFF, 0xF8 },
	{ 0x22, 0xFF, 0x10 },
	{ 0x23, 0xFF, 0xA0 },
	{ 0x2B, 0xFF, 0xA0 },
	{ 0x24, 0xFF, 0x00 },
	{ 0x34, 0xFF, 0x00 },

	{ 0x0F, 0xFF, 0x03 },
	{ 0xAA, 0xFF, 0xEC },
	{ 0xAC, 0xFF, 0x40 },

	{ 0x0F, 0xFF, 0x00 },
	{ 0x3A, 0xFF, 0x89 },
	{ 0x49, 0xFF, 0xE1 },
	{ 0x43, 0xFF, 0x01 },

	{ 0x0F, 0xFF, 0x04 },
	{ 0x43, 0xFF, 0x01 },
	{ 0x3A, 0xFF, 0x89 },

	{ 0x0F, 0xFF, 0x03 },
	{ 0xA8, 0xFF, 0x0B },

	{ 0x0F, 0xFF, 0x00 },
	{ 0x4F, 0xFF, 0x84 },
	{ 0x44, 0xFF, 0x19 },
	{ 0x46, 0xFF, 0x15 },
	{ 0x47, 0xFF, 0x88 },
	{ 0xD9, 0xFF, 0x00 },
	{ 0xF0, 0xFF, 0x78 },
	{ 0xF1, 0xFF, 0x10 },

	{ 0x0F, 0xFF, 0x03 },
	{ 0x3A, 0xFF, 0x02 },

	{ 0x0F, 0xFF, 0x00 },
	{ 0x28, 0xFF, 0x88 },
	{ 0x6E, 0xFF, 0x80 },
	{ 0x77, 0xFF, 0x87 },
	{ 0x7B, 0xFF, 0x00 },
	{ 0x86, 0xFF, 0x00 },

	{ 0x0F, 0xFF, 0x00 },
	{ 0x36, 0xFF, 0x06 },
	{ 0x8F, 0xFF, 0x41 },

	{ 0x0F, 0xFF, 0x01 },
	{ 0xC0, 0xFF, 0x42 },
	{ 0xC4, 0x70, 0x30 },
	{ 0xC4, 0x80, 0x00 },
	{ 0xC5, 0xFF, 0x00 },
	{ 0xC6, 0xFF, 0x00 },
	{ 0xC7, 0xFF, 0x00 },
	{ 0xC8, 0xFF, 0x00 },
	{ 0xC9, 0xFF, 0x99 },
	{ 0xCA, 0xFF, 0x99 },

	{ 0x0F, 0xFF, 0x00 },
	{ 0x86, 0x0C, 0x08 },
	{ 0x81, 0x80, 0x80 },

	{ 0x0F, 0x07, 0x01 },
	{ 0x10, 0xFF, 0x00 },
	{ 0x11, 0xFF, 0x00 },
	{ 0x12, 0xFF, 0x00 },
	{ 0x13, 0xFF, 0x00 },
	{ 0x28, 0xFF, 0x00 },
	{ 0x29, 0xFF, 0x00 },
	{ 0x2A, 0xFF, 0x00 },
	{ 0x2B, 0xFF, 0x00 },
	{ 0x2C, 0xFF, 0x00 },
	{ 0xC0, 0xC0, 0x40 },

	{ 0x0F, 0x07, 0x03 },
	{ 0xE3, 0xFF, 0x07 },
	{ 0x27, 0xFF, 0x9F },
	{ 0x28, 0xFF, 0x9F },
	{ 0x29, 0xFF, 0x9F },
	{ 0xA7, 0x40, 0x40 },

	{ 0x0F, 0x07, 0x07 },
	{ 0xE3, 0xFF, 0x07 },
	{ 0x27, 0xFF, 0x9F },
	{ 0x28, 0xFF, 0x9F },
	{ 0x29, 0xFF, 0x9F },
	{ 0xA7, 0x40, 0x40 },

	{ 0x0F, 0x07, 0x00 },
	{ 0x21, 0x04, 0x00 },
	{ 0x4A, 0xFF, 0xC8 },
	{ 0xF8, 0xFF, 0xC3 },
	{ 0xF8, 0xFF, 0xA5 },

	{ 0x0F, 0x07, 0x01 },
	{ 0x5F, 0xFF, 0x04 },
	{ 0x58, 0xFF, 0x12 },
	{ 0x58, 0xFF, 0x02 },
	{ 0x5F, 0xFF, 0x00 },

	{ 0x0F, 0x07, 0x00 },
	{ 0xF8, 0xFF, 0xFF },

	{ 0x0F, 0x07, 0x03 },
	{ 0xA6, 0xFF, 0x8C },
	{ 0x0F, 0x07, 0x07 },
	{ 0xA6, 0xFF, 0x8C },

	{ 0x0F, 0x07, 0x05 },
	{ 0x20, 0x03, 0x01 },

	{ 0x0F, 0x07, 0x04 },
	{ 0x3C, 0x20, 0x00 },

	{ 0x0F, 0x07, 0x00 },
	{ 0x91, 0x40, 0x40 },

	{ 0x0F, 0x07, 0x03 },
	{ 0xF0, 0xFF, 0xC0 },

	{ 0x0F, 0x07, 0x00 },
	{ 0x21, 0x40, 0x40 },
	{ 0xCE, 0x30, 0x00 },

	{ 0x0F, 0x07, 0x04 },
	{ 0xCE, 0x30, 0x00 },
	{ 0x42, 0xE0, 0xC0 },

	{ 0x0F, 0x07, 0x00 },
	{ 0x42, 0xE0, 0xC0 },
	{ 0x7B, 0x10, 0x10 },
	{ 0x3C, 0x21, 0x00 },
	{ 0x3B, 0xFF, 0x23 },
	{ 0xF6, 0xFF, 0x08 },

	{ 0x0F, 0x07, 0x04 },
	{ 0x3C, 0x21, 0x00 },
	{ 0x3B, 0xFF, 0x23 },

	{ 0x0F, 0x07, 0x00 },
	{ 0x59, 0xFF, 0x00 },

	/* Three more registers set by the EVB and not in the sample code. */
	{ 0x2C, 0xFF, 0xA1 },
	{ 0x2D, 0xFF, 0x10 },
	{ 0xE8, 0xFF, 0x10 },

	/* END sentinel; the init loop stops when addr == 0xFF. */
	{ 0xFF, 0xFF, 0xFF },
	/* clang-format on */
};

int it68051_init(void)
{
	LOG_DBG("hdimrx_write_init");
	uint16_t cnt = 0;

	while (it68051_init_table[cnt].addr != 0xFF) {
		it68051_hdmi_write(it68051_init_table[cnt].addr,
				   it68051_init_table[cnt].mask,
				   it68051_init_table[cnt].value);
		cnt++;
	}

	it68051_init_caof();
	it68051_chgbank(0);
	/* 0714 MHL CTS need set 0x28 to 0x88 */
	it68051_hdmi_write(0x28, 0xff, 0x88);

	it68051_set_video_tristate(1);
	it68051_oclk_cal();

	it68051_set_hpd(PORT2, false);
	it68051_set_hpd(PORT1, false);
	it68051_edid_select(DEFAULT_EDID_IDX);
	it68051_edid_init();

	it68051_set_ttl_video_path(TTL_DDR, TTL_SEP_SYNC, COLOR_FORMAT_RGB);
	it68051_set_pixel_mode(MODE_DUAL);

	it68051_port_select(PORT2);

	return 0;
}

uint32_t it68051_get_rclk_value(void)
{
	return rclk_value;
}
