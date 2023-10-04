/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Portions based on code in ITE's it68051 driver, which is
 *  Copyright (c) 2023 ITE Tech. Inc.
 *  SPDX-License-Identifier: BSD-3-Clause
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <stdlib.h>

#include "io.h"
#include "it68051.h"
#include "it68051_edid.h"
#include "it68051_i2c.h"
#include "it68051_init.h"

LOG_MODULE_DECLARE(it68051);

static const uint32_t I2C_ERROR_THRESH = 32;

enum video_state {
	VIDEO_OFF,
	UNPLUG,
	WAIT_SYNC,
	CHECK_SYNC,
	VID_STABLE,
};

static const char *const statev_name[] = { "VIDEO_OFF", "UNPLUG", "WAIT_SYNC",
					   "CHECK_SYNC", "VID_STABLE" };
enum audio_state {
	AUDIO_OFF,
	REQUEST_AUDIO,
	WAIT_FOR_READY,
	AUDIO_ON,
};

static const char *const statea_name[] = { "AUDIO_OFF", "REQUEST_AUDIO",
					   "WAIT_FOR_READY", "AUDIO_ON" };

static enum video_state statev = UNPLUG;
static enum audio_state statea = AUDIO_OFF;

static void it68051_video_change_state(enum video_state new_state);
static void it68051_audio_change_state(enum audio_state new_state);

/**
 * @brief "pre Frame data container" in vendor code
 *
 * Based on code in prevAVIDB and related items in iTE6805_SYS.c
 */
static uint8_t prev_avi_db[2] = { 0 };

static uint8_t prev_audio_b0;
static uint8_t prev_audio_b1;
static uint8_t prev_audio_b2;

#define TIMEOUT_SCDT_CHECK_COUNT 6
static uint8_t scdt_check_count;

#define TIMEOUT_AUDIO_CHECK_COUNT 3
static uint8_t audio_check_count;

#define TIMEOUT_AUDIO_MONITOR 2
static uint8_t audio_monitor_count;

#define MAX_AUDIO_SAMPLING_FREQ_ERROR_COUNT 15
static uint8_t audio_sampling_freq_error_count;

static uint8_t deskew_error_count;

/* need to restart IPLL lock */
#define MAX_IPLL_RELOCK_COUNT 6
static uint8_t ipll_relock_count;

static bool new_avi_info_frame;
static bool first_time_audio_monitor = true;
static bool hdcp_trigger_auto_eq_again = true;
static bool first_time_param_change;
static bool disable_new_aviif_when_param_change;
static bool first_time_vid_stable_done;

static uint8_t ecc_error_count;
#define MAX_VID_STABLE_COUNT 50
static uint8_t vid_stable_count;
static uint8_t ch0_symbol_lock_reset_count;
static uint8_t ch1_symbol_lock_reset_count;
static uint8_t ch2_symbol_lock_reset_count;

/* Fields from struct _iTE6805_DATA */
static enum avi_color_format aviif_input_color_format;
static enum avi_colorimetry aviif_colorimetry;
static enum avi_range_type_rgb aviif_rgb_quantization_range;
static enum avi_range_type_yuv aviif_yuv_quantization_range;
static uint8_t aviif_vic;
static uint8_t aviif_extended_colorimetry;

static bool vid_stable_done;
static bool downscale;
static enum pixel_mode next_pixel_mode;
static bool is_yuv420;

/**
 * @brief Define the matrix types for color space conversion
 *
 * Based on code in _CSCMtx_Type in iTE6805_CSC_Table.h
 */
enum csc_matrix_type {
	RGB2YUV_ITU601_16_235,
	RGB2YUV_ITU601_00_255,
	RGB2YUV_ITU709_16_235,
	RGB2YUV_ITU709_00_255,
	YUV2RGB_ITU601_16_235,
	YUV2RGB_ITU601_00_255,
	YUV2RGB_ITU709_16_235,
	YUV2RGB_ITU709_00_255,
	YUV2RGB_BT2020_00_255,
	RGB_00_255_RGB_16_235,
	RGB_16_235_RGB_00_255,
	CSC_MATRIX_TYPE_COUNT
};

/*
 * The IT68051 Color Space Converter uses 22 registers in its matrix, so
 * for each option we can pick, we need 22 values to write into the chip.
 */
#define CSC_MATRIX_SIZE 22

/**
 * @brief Color Space Conversion matrix
 *
 * Based on code in CSC_Matrix in iTE6805_CSC_Table.h, with the following
 * comments:
 *
 * all the 00_255 - 16_235 i.e. RGB
 * ex. RGB2YUV_ITU601_16_235=RGB(16-235) to ITU601
 * ex. YUV2RGB_ITU709_00_255=YUV(ITU709) to RGB(00-255)
 *
 * setting from REG170 to REG185
 */
static uint8_t csc_matrix[CSC_MATRIX_TYPE_COUNT][CSC_MATRIX_SIZE] = {
	[RGB2YUV_ITU601_16_235] = { 0x00, 0x80, 0x10, 0xB2, 0x04, 0x65,
				    0x02, 0xE9, 0x00, 0x93, 0x3C, 0x18,
				    0x04, 0x55, 0x3F, 0x49, 0x3D, 0x9F,
				    0x3E, 0x18, 0x04, 0x00 },
	[RGB2YUV_ITU601_00_255] = { 0x10, 0x80, 0x10, 0x09, 0x04, 0x0E,
				    0x02, 0xC9, 0x00, 0x0F, 0x3D, 0x84,
				    0x03, 0x6D, 0x3F, 0xAB, 0x3D, 0xD1,
				    0x3E, 0x84, 0x03, 0x00 },
	[RGB2YUV_ITU709_16_235] = { 0x00, 0x80, 0x10, 0xB8, 0x05, 0xB4,
				    0x01, 0x94, 0x00, 0x4A, 0x3C, 0x17,
				    0x04, 0x9F, 0x3F, 0xD9, 0x3C, 0x10,
				    0x3F, 0x17, 0x04, 0x00 },
	[RGB2YUV_ITU709_00_255] = { 0x10, 0x80, 0x10, 0xEA, 0x04, 0x77,
				    0x01, 0x7F, 0x00, 0xD0, 0x3C, 0x83,
				    0x03, 0xAD, 0x3F, 0x4B, 0x3D, 0x32,
				    0x3F, 0x83, 0x03, 0x00 },
	[YUV2RGB_ITU601_16_235] = { 0x00, 0x00, 0x00, 0x00, 0x08, 0x6B,
				    0x3A, 0x50, 0x3D, 0x00, 0x08, 0xF5,
				    0x0A, 0x02, 0x00, 0x00, 0x08, 0xFD,
				    0x3F, 0xDA, 0x0D, 0x00 },
	[YUV2RGB_ITU601_00_255] = { 0x04, 0x00, 0xA7, 0x4F, 0x09, 0x81,
				    0x39, 0xDD, 0x3C, 0x4F, 0x09, 0xC4,
				    0x0C, 0x01, 0x00, 0x4F, 0x09, 0xFD,
				    0x3F, 0x1F, 0x10, 0x00 },
	[YUV2RGB_ITU709_16_235] = { 0x00, 0x00, 0x00, 0x00, 0x08, 0x55,
				    0x3C, 0x88, 0x3E, 0x00, 0x08, 0x51,
				    0x0C, 0x00, 0x00, 0x00, 0x08, 0x00,
				    0x00, 0x84, 0x0E, 0x00 },
	[YUV2RGB_ITU709_00_255] = { 0x04, 0x00, 0xA7, 0x4F, 0x09, 0xBA,
				    0x3B, 0x4B, 0x3E, 0x4F, 0x09, 0x57,
				    0x0E, 0x02, 0x00, 0x4F, 0x09, 0xFE,
				    0x3F, 0xE8, 0x10, 0x00 },
	[YUV2RGB_BT2020_00_255] = { 0x04, 0x00, 0xA7, 0x4F, 0x09, 0xCC,
				    0x3A, 0x7E, 0x3E, 0x4F, 0x09, 0x69,
				    0x0D, 0x0B, 0x00, 0x4F, 0x09, 0xFE,
				    0x3F, 0x1D, 0x11, 0x00 },
	[RGB_00_255_RGB_16_235] = { 0x10, 0x10, 0x00, 0xe0, 0x06, 0x00,
				    0x00, 0x00, 0x00, 0x00, 0x00, 0xe0,
				    0x06, 0x00, 0x00, 0x00, 0x00, 0x00,
				    0x00, 0xe0, 0x06, 0x10 },
	[RGB_16_235_RGB_00_255] = { 0xED, 0xED, 0x00, 0x50, 0x09, 0x00,
				    0x00, 0x00, 0x00, 0x00, 0x00, 0x50,
				    0x09, 0x00, 0x00, 0x00, 0x00, 0x00,
				    0x00, 0x50, 0x09, 0xED }
};

/*
 * Audio sampling rates, as defined in the HDMI spec 2.0 p. 84
 */
#define AUDIO_SAMPLING_1024K 0x35
#define AUDIO_SAMPLING_768K 0x09
#define AUDIO_SAMPLING_512K 0x3B
#define AUDIO_SAMPLING_384K 0x05
#define AUDIO_SAMPLING_256K 0x1B
#define AUDIO_SAMPLING_192K 0x0E
#define AUDIO_SAMPLING_176P4K 0x0C
#define AUDIO_SAMPLING_128K 0x2B
#define AUDIO_SAMPLING_96K 0x0A
#define AUDIO_SAMPLING_88P2K 0x08
#define AUDIO_SAMPLING_64K 0x0B
#define AUDIO_SAMPLING_48K 0x02
#define AUDIO_SAMPLING_44P1K 0x00
#define AUDIO_SAMPLING_32K 0x03

/**
 * @brief Read an interrupt registers and clear the bits that were set.
 *
 * The IT68051 interrupt registers are W1C (write 1 to clear), so read the
 * value from the register, then write it back to acknowledge those
 * interrupts.
 *
 * @param reg_addr Interrupt register address
 * @param mask Interrupt bits to clear, usually 0xFF
 * @return value that was in the interrupt register before it was cleared
 */
static uint8_t read_and_clear_interrupt(uint8_t reg_addr, uint8_t mask)
{
	uint8_t val = it68051_hdmi_read(reg_addr);

	it68051_hdmi_write(reg_addr, mask, val & mask);
	return val;
}

/**
 * @brief Check if the HDMI RX clock is valid
 *
 * Uses the currently-selected port to determine which RX CLK to check.
 *
 * Based on code in iTE6805_Check_CLK_Vaild (misspelled) in iTE6805_DRV.c
 *
 * @return true if the RX clock is valid, false if not
 */
static bool it68051_clk_is_valid(void)
{
	bool is_valid;

	LOG_DBG("iTE6805_Check_CLK_Valid");
	it68051_chgbank(0);
	if (it68051_get_selected_port() == PORT2) {
		is_valid = it68051_hdmi_read(0x13) & BIT(3);
	} else {
		is_valid = it68051_hdmi_read(0x16) & BIT(3);
	}
	LOG_DBG("iTE6805_Check_CLK_Valid returns %s",
		is_valid ? "true" : "false");
	return is_valid;
}

/**
 * @brief Check if the HDMI RX clock is stable
 *
 * Not clear what the difference between "valid" and "stable" is.
 *
 * Uses the currently-selected port to determine which RX CLK to check.
 *
 * Based on code in iTE6805_Check_CLK_Stable in iTE6805_DRV.c
 *
 * @return true if the RX clock is stable, false if not
 */
static bool it68051_clk_is_stable(void)
{
	bool is_stable;

	LOG_DBG("iTE6805_Check_CLK_Stable");
	it68051_chgbank(0);
	if (it68051_get_selected_port() == PORT2) {
		is_stable = it68051_hdmi_read(0x13) & BIT(4);
	} else {
		is_stable = it68051_hdmi_read(0x16) & BIT(4);
	}
	LOG_DBG("iTE6805_Check_CLK_Stable returns %s",
		is_stable ? "true" : "false");
	return is_stable;
}

/**
 * @brief Check if port 0 is in MHL mode
 *
 * Based on code in iTE6805_Check_PORT0_IS_MHL_Mode in iTE6805_DRV.c
 *
 * @return true if the port is in MHL mode, false if not.
 */
static bool it68051_is_port0_mhl_mode(void)
{
	LOG_DBG("iTE6805_Check_PORT0_IS_MHL_Mode");
	it68051_chgbank(0);
	return it68051_hdmi_read(0x13) & BIT(6);
}

/**
 * @brief Check if the current port is in HDMI or DVI mode
 *
 * Uses the currently-selected port to determine which port to check.
 *
 * Based on code in iTE6805_Check_HDMI_OR_DVI_Mode in iTE6805_DRV.c
 *
 * @return true if the port is in HDMI more, false if in DVI mode
 */
static bool it68051_is_port_hdmi_mode(enum it68051_port port)
{
	LOG_DBG("iTE6805_Check_HDMI_OR_DVI_Mode(%d)", (int)port);
	it68051_chgbank(0);
	if (port == PORT2) {
		return it68051_hdmi_read(0x13) & BIT(1);
	} else if (port == PORT1) {
		return it68051_hdmi_read(0x16) & BIT(1);
	}
	return false;
}

/**
 * @brief Set the value for register 47 according to the TMDS
 *
 * Register 47 is one of the components of WCLK (WCLKHighNumC, specifically),
 * and it is set based on the TMDS clock speed.
 *
 * Based on code in iTE6805_Set_47_By_TMDS in iTE6805_DRV.c
 */
static void it68051_set_47_by_tmds(void)
{
	LOG_DBG("iTE6805_Set_47_By_TMDS");
	uint8_t ipll_hs1p48g, reg47h, reg43h, reg48h, ref_sum, temp;

	it68051_chgbank(0);

	reg43h = it68051_hdmi_read(0x43);
	reg47h = it68051_hdmi_read(0x47);
	reg48h = it68051_hdmi_read(0x48);

	/* See comments in it68051_get_vid_info for watchdog bits.
	 *
	 * Use a little bitwise arithmetic to check that zero or one bits
	 * are set. `(x & (x-1))` will be 0 if there are zero or one bits set.
	 * It will be non-zero if there are two or more bits set.
	 */
	uint8_t wdog_bits = reg43h & (BIT(7) | BIT(6) | BIT(5));

	if ((wdog_bits & (wdog_bits - 1)) != 0) {
		LOG_INF("Multiple WDOG_RX_CLK_PRE_DIV bits, reg43h = 0x%02x",
			reg43h);
	}

	if (reg43h & BIT(7)) {
		ref_sum = reg48h / 8;
	} else if (reg43h & BIT(6)) {
		ref_sum = reg48h / 4;
	} else if (reg43h & BIT(5)) {
		ref_sum = reg48h / 2;
	} else {
		ref_sum = reg48h;
	}

	if (it68051_get_selected_port() == PORT2) {
		ipll_hs1p48g = it68051_hdmi_read(0x14) & BIT(1);
	} else {
		ipll_hs1p48g = it68051_hdmi_read(0x17) & BIT(1);
	}
	temp = it68051_get_rclk_value() / 1000;
	LOG_DBG("ref_sum = %d", (int)ref_sum);
	LOG_DBG("rclk_value = %d", (int)temp);

	if (ref_sum < temp && ipll_hs1p48g == 0x00) {
		LOG_DBG("OverWrite IPLL/OPLL");
		reg47h = it68051_hdmi_read(0x47);
		it68051_hdmi_write(0x47, 0xFF, reg47h);
	}
}

/**
 * @brief Get the pixel clock speed
 *
 * Based on code in iTE6805_Get_PCLK in iTE6805_DRV.c
 *
 * @return pixel clock speed
 */
static uint32_t it68051_get_pclk(void)
{
	LOG_DBG("iTE6805_Get_PCLK");
	uint32_t rddata, i;
	uint32_t pclk, sump;

	sump = 0;
	it68051_chgbank(0);
	for (i = 0; i < 5; i++) {
		k_msleep(3);
		it68051_hdmi_write(0x9A, BIT(7), 0x00);
		rddata = ((uint32_t)(it68051_hdmi_read(0x9A) & 0x03) << 8) +
			 it68051_hdmi_read(0x99);
		it68051_hdmi_write(0x9A, BIT(7), BIT(7));
		sump += rddata;
	}
	/* 512=2*256 because of 1T 2 pixel, *5 = for repeat times */
	pclk = it68051_get_rclk_value() * 512 * 5 / sump;
	LOG_DBG("pclk = %d", pclk);
	return pclk;
}

/**
 * @brief Set the value for register 1B0 based on the pixel clock
 *
 * Based on code in iTE6805_Set_1B0_By_PixelClock in iTE6805_DRV.c
 */
static void it68051_set_1b0_by_pclk(void)
{
	LOG_DBG("iTE6805_Set_1B0_By_PixelClock");
	uint8_t temp;
	uint8_t pixel_repeat;
	uint32_t pclk;

	it68051_chgbank(0);
	temp = (it68051_hdmi_read(0x1B) & 0x30) >> 4;
	switch (temp) {
	case 0:
		pixel_repeat = 1;
		break;
	case 1:
		pixel_repeat = 2;
		break;
	case 3:
		pixel_repeat = 4;
		break;
	default:
		pixel_repeat = 1;
		break;
	}
	pclk = it68051_get_pclk();
	it68051_chgbank(1);
	if ((pclk / pixel_repeat) < 25000) {
		it68051_hdmi_write(0xB0, BIT(0), 0);
	} else {
		it68051_hdmi_write(0xB0, BIT(0), BIT(0));
	}

	if (it68051_get_pixel_mode() == MODE_SINGLE) {
		it68051_hdmi_write(0xB0, BIT(0), 0);
	}

	it68051_chgbank(0);
}

/**
 * @brief Calculate the TMDS clock
 *
 * Based on code in iTE6805_Get_TMDS in iTE6805_DRV.c
 *
 * @param count Number of readings to average
 * @return calculated TMDSCLK in Hz
 */
static uint32_t it68051_get_tmds(uint8_t count)
{
	LOG_DBG("iTE6805_Get_TMDS");
	uint32_t sumt = 0;
	uint8_t rddata = 0, i;
	uint32_t rclk_mult;
	uint32_t tmdsclk;

	if (it68051_get_selected_port() == PORT2) {
		it68051_chgbank(0);
	} else {
		it68051_chgbank(4);
	}

	for (i = 0; i < count; i++) {
		k_msleep(3);
		rddata = it68051_hdmi_read(0x48) + 1;
		sumt += rddata;
	}
	rddata = it68051_hdmi_read(0x43) & 0xE0;
	it68051_chgbank(0);

	/* Check the watchdog bits.
	 * Same comments apply here as in it68051_set_47_by_tmds.
	 */
	uint8_t wdog_bits = rddata & (BIT(7) | BIT(6) | BIT(5));

	if ((wdog_bits & (wdog_bits - 1)) != 0) {
		LOG_INF("Multiple WDOG_RX_CLK_PRE_DIV bits, reg43h = 0x%02x",
			rddata);
	}

	if (rddata & BIT(7)) {
		rclk_mult = 1024;
	} else if (rddata & BIT(6)) {
		rclk_mult = 512;
	} else if (rddata & BIT(5)) {
		rclk_mult = 256;
	} else {
		rclk_mult = 128;
	}

	tmdsclk = (it68051_get_rclk_value() * rclk_mult * i) / (sumt);

	LOG_DBG("tmdsclk = %u.%03uMHz", tmdsclk / 1000, tmdsclk % 1000);
	return tmdsclk;
}

void it68051_get_vid_info(struct vtiming *vt)
{
	LOG_DBG("iTE6805_Get_VID_Info");
	uint16_t h_sync_pol, v_sync_pol, interlaced;
	uint16_t h_total, h_active, hfp, hsyncw;
	uint16_t v_total, v_active, vfp, vsyncw;
	uint32_t frame_rate;

	/*
	 * 0x43 bit5 : P0_WDog RxCLK PreDiv2
	 * 0x43 bit6 : P0_WDog RxCLK PreDiv4
	 * 0x43 bit7 : P0_WDog RxCLK PreDiv8
	 * 0x443 bit5 : P1_WDog RxCLK PreDiv2
	 * 0x443 bit6 : P1_WDog RxCLK PreDiv4
	 * 0x443 bit7 : P1_WDog RxCLK PreDiv8
	 * 0x48	 P0_TMDSCLKSpeed 7:0 tmdsclk = RCLKVALUE*256/ TMDSCLKSpeed
	 * 0x448 P1_TMDSCLKSpeed 7:0 tmdsclk = RCLKVALUE*256/ TMDSCLKSpeed
	 */
	if (it68051_get_selected_port() == PORT2) {
		it68051_chgbank(0);
	} else {
		it68051_chgbank(4);
	}
	vt->tmdsclk = it68051_get_tmds(1);

	vt->pclk = it68051_get_pclk();

	interlaced = (it68051_hdmi_read(0x98) & 0x02) >> 1;
	h_total = ((it68051_hdmi_read(0x9C) & 0x3F) << 8) +
		  it68051_hdmi_read(0x9B);
	h_active = ((it68051_hdmi_read(0x9E) & 0x3F) << 8) +
		   it68051_hdmi_read(0x9D);
	hfp = ((it68051_hdmi_read(0xA1) & 0xF0) << 4) + it68051_hdmi_read(0xA0);
	hsyncw = ((it68051_hdmi_read(0xA1) & 0x01) << 8) +
		 it68051_hdmi_read(0x9F);

	v_total = ((it68051_hdmi_read(0xA3) & 0x3F) << 8) +
		  it68051_hdmi_read(0xA2);
	v_active = ((it68051_hdmi_read(0xA5) & 0x3F) << 8) +
		   it68051_hdmi_read(0xA4);
	vfp = ((it68051_hdmi_read(0xA8) & 0xF0) << 4) + it68051_hdmi_read(0xA7);
	vsyncw = ((it68051_hdmi_read(0xA8) & 0x01) << 8) +
		 it68051_hdmi_read(0xA6);

	if (it68051_get_selected_port() == PORT1) {
		it68051_chgbank(4);
		LOG_DBG("it68051_hdmi_read(0xAA) = 0x%02X",
			(int)it68051_hdmi_read(0xAA));
	}

	h_sync_pol = (it68051_hdmi_read(0xAA) & BIT(5)) >> 5;
	v_sync_pol = (it68051_hdmi_read(0xAA) & BIT(6)) >> 6;
	it68051_chgbank(0);

	vt->h_active = h_active;
	vt->h_total = h_total;
	vt->h_front_porch = hfp;
	vt->h_sync_width = hsyncw;
	vt->h_back_porch = (h_total - h_active - hfp - hsyncw);
	vt->v_active = v_active;
	vt->v_total = v_total;
	vt->v_front_porch = vfp;
	vt->v_sync_width = vsyncw;
	vt->v_back_porch = v_total - v_active - vfp - vsyncw;
	vt->scan_mode = (interlaced)&0x01;
	vt->v_polarity = (v_sync_pol)&0x01;
	vt->h_polarity = (h_sync_pol)&0x01;

	frame_rate = (uint32_t)(vt->pclk) * 1000;
	frame_rate /= vt->h_total;
	frame_rate /= vt->v_total;
	vt->frame_rate = frame_rate;
}

void it68051_get_aud_info(struct atiming *at)
{
	LOG_DBG("iTE6805_Show_AUD_Info");
	uint8_t dsd_fs, aud_fmt, aud_ch;

	it68051_chgbank(0);
	at->aud_3d_on = (it68051_hdmi_read(0xB0) & BIT(4)) != 0;
	at->mult_aud_on = (it68051_hdmi_read(0xB0) & BIT(5)) != 0;
	at->hbr_aud = (it68051_hdmi_read(0xB0) & BIT(6)) != 0;
	at->dsd_aud = (it68051_hdmi_read(0xB0) & BIT(7)) != 0;

	aud_ch = (it68051_hdmi_read(0xB1) & 0x3F);
	aud_fmt = ((it68051_hdmi_read(0xB5) & 0xC0) >> 2) +
		  (it68051_hdmi_read(0xB5) & 0x0F);

	it68051_chgbank(2);
	dsd_fs = (it68051_hdmi_read(0x46) & 0x1C) >> 2;
	it68051_chgbank(0);

	if (at->hbr_aud) {
		at->aud_ch = 2;
	} else {
		switch (aud_ch) {
		case 1:
			at->aud_ch = 2;
			break;
		case 3:
			at->aud_ch = 4;
			break;
		case 7:
			at->aud_ch = 6;
			break;
		case 15:
			at->aud_ch = 8;
			break;
		case 31:
			at->aud_ch = 10;
			break;
		case 63:
			at->aud_ch = 12;
			break;
		default:
			at->aud_ch = -1;
			break;
		}
	}

	if (at->dsd_aud) {
		switch (dsd_fs) {
		case 0:
			at->aud_fs = 0;
			break;
		case 1:
			at->aud_fs = 32000;
			break;
		case 2:
			at->aud_fs = 44100;
			break;
		case 3:
			at->aud_fs = 48000;
			break;
		case 4:
			at->aud_fs = 88200;
			break;
		case 5:
			at->aud_fs = 96000;
			break;
		case 6:
			at->aud_fs = 176400;
			break;
		case 7:
			at->aud_fs = 192000;
			break;
		default:
			at->aud_fs = -1;
			break;
		}
	} else {
		switch (aud_fmt) {
		case 3:
			at->aud_fs = 32000;
			break;
		case 0:
			at->aud_fs = 44100;
			break;
		case 2:
			at->aud_fs = 48000;
			break;
		case 11:
			at->aud_fs = 64000;
			break;
		case 8:
			at->aud_fs = 88200;
			break;
		case 10:
			at->aud_fs = 96000;
			break;
		case 43:
			at->aud_fs = 128000;
			break;
		case 12:
			at->aud_fs = 176400;
			break;
		case 14:
			at->aud_fs = 192000;
			break;
		case 27:
			at->aud_fs = 256000;
			break;
		case 13:
			at->aud_fs = 352800;
			break;
		case 5:
			at->aud_fs = 384000;
			break;
		case 59:
			at->aud_fs = 512000;
			break;
		case 45:
			at->aud_fs = 705600;
			break;
		case 9:
			at->aud_fs = 768000;
			break;
		case 53:
			at->aud_fs = 1024000;
			break;
		case 29:
			at->aud_fs = 1411200;
			break;
		case 21:
			at->aud_fs = 1536000;
			break;
		default:
			at->aud_fs = -1;
			break;
		}
	}
}

void it68051_get_aviif(struct aviif *info)
{
	info->aviif_input_color_format = aviif_input_color_format;
	info->aviif_colorimetry = aviif_colorimetry;
	info->aviif_rgb_quantization_range = aviif_rgb_quantization_range;
	info->aviif_yuv_quantization_range = aviif_yuv_quantization_range;
	info->aviif_vic = aviif_vic;
	info->aviif_extended_colorimetry = aviif_extended_colorimetry;
}

/**
 * @brief Display the video stream info for human consumption
 *
 * Uses `LOG_INF` so make sure `CONFIG_LOG_DEFAULT_LEVEL=3` in prj.conf
 *
 * Based on code in iTE6805_Show_VID_Info in iTE6805_DRV.c
 */
static void it68051_show_vid_info(void)
{
	LOG_DBG("iTE6805_Show_VID_Info");
	int voutstb, lvpclk_hs;
	struct vtiming vt;

	it68051_get_vid_info(&vt);

	it68051_chgbank(0);
	LOG_INF("-------Video Timing-------");
	if (it68051_hdmi_read(0x15) & 0x02) {
		LOG_INF("HDMI2 Scramble Enable !!");
	} else {
		LOG_INF("HDMI2 Scramble Disable !!");
	}
	if (it68051_hdmi_read(0x14) & 0x40) {
		LOG_INF("HDMI2 CLK Ratio 1/40 !!");
	} else {
		LOG_INF("HDMI CLK Ratio 1/10  !!");
	}

	voutstb = ((it68051_hdmi_read(0x19) & 0x02) >> 1);
	lvpclk_hs = ((it68051_hdmi_read(0x36) & 0x0C) >> 2);

	LOG_INF("tmdsclk = %u.%03uMHz", vt.tmdsclk / 1000, vt.tmdsclk % 1000);
	LOG_INF("pclk = %d.%03dMHz", vt.pclk / 1000, vt.pclk % 1000);

	/* h_sync_width,h_back_porch,h_active,h_front_porch
	 *
	 * If return to upper layer or show log,
	 * need to x = x*2 for YUV420 condition
	 */
	if (is_yuv420) {
		LOG_INF("h_active = %d", vt.h_active * 2);
		LOG_INF("h_total = %d", vt.h_total * 2);
	} else {
		LOG_INF("h_active = %d", vt.h_active);
		LOG_INF("h_total = %d", vt.h_total);
	}

	LOG_INF("v_active = %d", vt.v_active);
	LOG_INF("v_total = %d", vt.v_total);

	if (is_yuv420) {
		LOG_INF("h_front_porch = %d", vt.h_front_porch * 2);
		LOG_INF("h_sync_width = %d", vt.h_sync_width * 2);
		LOG_INF("h_back_porch = %d", vt.h_back_porch * 2);
	} else {
		LOG_INF("h_front_porch = %d", vt.h_front_porch);
		LOG_INF("h_sync_width = %d", vt.h_sync_width);
		LOG_INF("h_back_porch = %d", vt.h_back_porch);
	}

	LOG_INF("v_front_porch = %d", vt.v_front_porch);
	LOG_INF("v_sync_width = %d", vt.v_sync_width);
	LOG_INF("v_back_porch = %d", vt.v_back_porch);
	LOG_INF("frame_rate = %d", vt.frame_rate);

	if (vt.scan_mode == 0) {
		LOG_INF("scan_mode = Progressive");
	} else {
		LOG_INF("scan_mode = interlaced");
	}

	if (vt.v_polarity == 1) {
		LOG_INF("v_sync_pol = Positive");
	} else {
		LOG_INF("v_sync_pol = Negative");
	}

	if (vt.h_polarity == 1) {
		LOG_INF("h_sync_pol = Positive");
	} else {
		LOG_INF("h_sync_pol = Negative");
	}

	if (voutstb == 1) {
		LOG_INF("Video Output Detect Stable   LVPCLK_HS=%d", lvpclk_hs);
	} else {
		LOG_INF("Video Output Detect Non-Stable   LVPCLK_HS=%d",
			lvpclk_hs);
	}
}

/**
 * @brief Display the audio stream info for human consumption
 *
 * Uses `LOG_INF` so make sure `CONFIG_LOG_DEFAULT_LEVEL=3` in prj.conf
 *
 * Based on code in iTE6805_Show_AUD_Info in iTE6805_DRV.c
 */
static void it68051_show_aud_info(void)
{
	LOG_DBG("iTE6805_Show_AUD_Info");
	struct atiming at;

	it68051_get_aud_info(&at);

	LOG_INF("Audio Format:");

	if (at.aud_3d_on) {
		if (at.dsd_aud) {
			LOG_INF("One Bit 3D Audio");
		} else {
			LOG_INF("3D Audio");
		}
	} else if (at.mult_aud_on) {
		if (at.dsd_aud) {
			LOG_INF("One Bit Multi-Stream Audio");
		} else {
			LOG_INF("Multi-Stream Audio");
		}
	} else {
		if (at.dsd_aud) {
			LOG_INF("One Bit Audio");
		} else {
			LOG_INF("Audio Sample");
		}
	}

	if (at.hbr_aud) {
		LOG_INF("High BitRate Audio");
	}

	if (at.aud_ch == -1) {
		LOG_INF("AudCh Error !!!");
	} else {
		LOG_INF("AudCh=%dCh", at.aud_ch);
	}

	if (at.aud_fs == -1) {
		LOG_INF("AudFs=Error !!!");
	} else if (at.aud_fs == 0) {
		LOG_INF("AudFs=Refer to Stream Header");
	} else {
		int32_t KHz = at.aud_fs / 1000;
		int32_t Hz = (at.aud_fs % 1000) / 100;

		if (Hz == 0) {
			LOG_INF("AudFs=%d.%dK", KHz, Hz);
		} else {
			LOG_INF("AudFs=%dK", KHz);
		}
	}
}

void it68051_set_pixel_mode(enum pixel_mode mode)
{
	next_pixel_mode = mode;
}

bool it68051_get_link_active(void)
{
	return vid_stable_done;
}

/**
 * @brief Set registers to configure the video output mode
 *
 * Based on code in iTE68051_Video_Output_Setting in iTE6805_SYS.c and
 * iTE6805_Set_LVDS_Video_Path in iTE6805_DRV.c.
 * Greatly simplified because there are no jumpers to set 4K downscaling
 * like on the ITE EVB.
 */
static void it68051_video_output_setting(void)
{
	LOG_DBG("iTE68051_Video_Output_Setting");
	downscale = false;

	it68051_chgbank(0);
	/* set Dual Pixel output mode to Odd/Even Mode */
	it68051_hdmi_write(0x64, BIT(2), 0);
	/* setting LREnable need to reset REG64[1] */
	it68051_hdmi_write(0x64, BIT(1), BIT(1));
	it68051_hdmi_write(0x64, BIT(1), 0);

	/* reset Downscale */
	it68051_chgbank(5);
	it68051_hdmi_write(0x20, 0x40, 0x40);

	/* setting to single or dual-pixel mode */
	it68051_chgbank(1);
	it68051_hdmi_write(0xC0, BIT(0),
			   (next_pixel_mode == MODE_DUAL) ? 0x01 : 0x00);

	it68051_chgbank(5);
	it68051_hdmi_write(0xD1, BIT(0), 0); /* RegPixMap */
	it68051_hdmi_write(0xD1, 0x0C, BIT(2)); /* RegLVColDep (LVDS8BIT) */
	it68051_hdmi_write(0xDA, BIT(4), 0); /* RegSPENSSC */
	it68051_hdmi_write(0xD0, 0xFF, 0xF3); /* RegEnLVDS = 1 */

	it68051_chgbank(1);
	it68051_hdmi_write(0xBD, (BIT(5) | BIT(4)),
			   (next_pixel_mode == MODE_DUAL) ? BIT(4) : 0);
	it68051_chgbank(0);
}

/**
 * @brief Determine the color depth from the incoming video stream
 *
 * Based on code in iTE6805_Set_ColorDepth in iTE6805_DRV.c
 */
static void it68051_set_color_depth(void)
{
	LOG_DBG("iTE6805_Set_ColorDepth");
	it68051_chgbank(0);
	uint16_t color_depth = (it68051_hdmi_read(0x98) & 0xF0);

	LOG_DBG("Force set Output color_depth =");
	switch (color_depth) {
	case 0x00:
	case 0x40:
		LOG_DBG("8 b");
		it68051_hdmi_write(0x6B, 0x03, 0x00);
		break;
	case 0x50:
		LOG_DBG("10 b");
		it68051_hdmi_write(0x6B, 0x03, 0x01);
		break;
	case 0x60:
		LOG_DBG("12 b");
		it68051_hdmi_write(0x6B, 0x03, 0x02);
		break;
	default:
		it68051_hdmi_write(0x6B, 0x03, 0x00);
		LOG_DBG("8 b");
		break;
	}
}

/**
 * @brief Get a bunch of information from the AVI Info Frame
 *
 * Information gets stored in several global variables that other
 * functions will use.
 *
 * Based on code in iTE6805_Get_AVIInfoFrame_Info in iTE6805_DRV.c
 */
static void it68051_get_avi_info_frame_info(void)
{
	LOG_DBG("iTE6805_Get_AVIInfoFrame_Info");
	it68051_chgbank(2);
	/* clang-format off */
	aviif_input_color_format = (enum avi_color_format)
		((it68051_hdmi_read(0x15) & 0x60) >> 5);
	aviif_colorimetry = (enum avi_colorimetry)
		((it68051_hdmi_read(0x16) & 0xC0) >> 6);
	aviif_extended_colorimetry =
		(it68051_hdmi_read(0x17) & 0x70) >> 4;
	aviif_rgb_quantization_range = (enum avi_range_type_rgb)
		((it68051_hdmi_read(0x17) & 0x0C) >> 2);
	aviif_vic = it68051_hdmi_read(0x18) & 0x7F;
	aviif_yuv_quantization_range = (enum avi_range_type_yuv)
		((it68051_hdmi_read(0x19) & 0xC0) >> 6);
	/* clang-format on */
	it68051_chgbank(0);

	if (aviif_rgb_quantization_range == RGB_RANGE_DEPENDED_ON_VIC) {
		if (aviif_vic >= 2) {
			aviif_rgb_quantization_range = RGB_RANGE_LIMIT;
		} else {
			aviif_rgb_quantization_range = RGB_RANGE_FULL;
		}
	}

	is_yuv420 = aviif_input_color_format == COLOR_FORMAT_YUV420;
}

/**
 * @brief Display the AVI Info Frame info for human consumption
 *
 * Based on code in iTE6805_Show_AVIInfoFrame_Info in iTE6805_DRV.c
 */
static void it68051_show_avi_info_frame_info(void)
{
	LOG_DBG("iTE6805_Show_AVIInfoFrame_Info");
	LOG_INF("AVI Info Frame VIC = %d", (int)aviif_vic);
	LOG_INF("AVI Info Frame Input ColorFormat = %X",
		(int)aviif_input_color_format);
	switch (aviif_input_color_format) {
	case COLOR_FORMAT_RGB:
		LOG_INF("- RGB");
		break;
	case COLOR_FORMAT_YUV422:
		LOG_INF("- YUV422");
		break;
	case COLOR_FORMAT_YUV444:
		LOG_INF("- YUV444");
		break;
	case COLOR_FORMAT_YUV420:
		LOG_INF("- YUV420");
		break;
	default:
		break;
	}

	LOG_INF("AVI Info Frame Colorimetry = %X", (int)aviif_colorimetry);
	switch (aviif_colorimetry) {
	case COLORIMETRY_ITU601:
		LOG_INF(" - ITU601");
		break;
	case COLORIMETRY_ITU709:
		LOG_INF(" - ITU709");
		break;
	case COLORIMETRY_EXTEND:
		LOG_INF(" - Extend");
		break;
	default:
		LOG_INF(" - UNKNOWN");
		break;
	}

	LOG_INF("AVI Info Frame RGBQuantizationRange = %X",
		(int)aviif_rgb_quantization_range);
	switch (aviif_rgb_quantization_range) {
	case RGB_RANGE_DEPENDED_ON_VIC:
		LOG_INF(" - DEPENDED_ON_VIC");
		break;
	case RGB_RANGE_LIMIT:
		LOG_INF(" - RGB_RANGE_LIMIT");
		break;
	case RGB_RANGE_FULL:
		LOG_INF(" - RGB_RANGE_FULL");
		break;
	default:
		LOG_INF(" - UNKNOWN");
		break;
	}

	LOG_INF("AVI Info Frame YUVQuantizationRange = %X",
		(int)aviif_yuv_quantization_range);
	switch (aviif_yuv_quantization_range) {
	case YUV_RANGE_LIMIT:
		LOG_INF(" - YUV_RANGE_LIMIT");
		break;
	case YUV_RANGE_FULL:
		LOG_INF(" - YUV_RANGE_FULL");
		break;
	default:
		LOG_INF(" - UNKNOWN");
		break;
	}

	LOG_INF("AVI Info Frame ExtendedColorimetry = %X",
		(int)aviif_extended_colorimetry);
}

/**
 * @brief Enable the video output on the parallel bus
 *
 * Based on code in iTE6805_Enable_Video_Output in iTE6805_SYS.c
 */
static void it68051_enable_video_output(void)
{
	LOG_DBG("iTE6805_Enable_Video_Output");
	int8_t reg_rx_pixclk_speed;
	enum csc_matrix_type mat = CSC_MATRIX_TYPE_COUNT;

	/*
	 * REG6B[5:4]: Reg_ColMod_Set Input color mode set
	 * 00: RGB mode
	 * 01: YUV422 mode
	 * 10: YUV444 mode
	 * 11: YUV420 mode
	 */
	it68051_chgbank(0);
	if (it68051_is_port_hdmi_mode(it68051_get_selected_port())) {
		LOG_DBG("---- CSC HDMI mode ----");
		it68051_get_avi_info_frame_info();
		it68051_show_avi_info_frame_info();
		it68051_hdmi_write(0x6B, 0x30, aviif_input_color_format << 4);
		it68051_hdmi_write(0x6B, 0x01, 0x00);
	} else {
		LOG_DBG("---- CSC DVI mode ----");
		it68051_hdmi_write(0x6B, 0x30, 0x10);
		it68051_hdmi_write(0x6B, 0x01, 0x01);

		if (it68051_get_selected_port() == 1) {
			it68051_chgbank(4);
		}
		reg_rx_pixclk_speed = it68051_hdmi_read(0x48);
		it68051_chgbank(0);

		/* Set Colormetry for CSC , come from 6802 code */
		if (reg_rx_pixclk_speed < 0x34) {
			aviif_colorimetry = COLORIMETRY_ITU709;
		} else {
			aviif_colorimetry = COLORIMETRY_ITU601;
		}
	}

	it68051_chgbank(0);
	/* default bit4 = 0 = setting to full range */
	it68051_hdmi_write(0x6E, 0xFF, 0xA0);
	it68051_chgbank(1);
	it68051_hdmi_write(0x6E, 0xFF, 0x00);
	it68051_chgbank(0);
	/* Simplified the logic: we always want RGB output. */
	LOG_DBG("AVIInfoFrame_Input_ColorFormat = %d",
		(int)aviif_input_color_format);
	if (aviif_input_color_format == COLOR_FORMAT_YUV422 ||
	    aviif_input_color_format == COLOR_FORMAT_YUV444 ||
	    aviif_input_color_format == COLOR_FORMAT_YUV420) {
		LOG_DBG("---- input YUV to output RGB ----");
		/* input YUV to output RGB */
		/* CSC Sel 00: bypass CSC 10: RGB to YUV 11: YUV to RGB */
		it68051_hdmi_write(0x6C, 0x03, 0x03);
		if (aviif_colorimetry == COLORIMETRY_ITU709) {
			/* when 709 format always to RGB full range */
			mat = YUV2RGB_ITU709_00_255;
		} else if (aviif_colorimetry == COLORIMETRY_EXTEND &&
			   (aviif_extended_colorimetry == 0x05 ||
			    aviif_extended_colorimetry == 0x06)) {
			/* for BT.2020 CSC */
			mat = YUV2RGB_BT2020_00_255;
		} else {
			/* Colormetry_ITU601 */
			mat = YUV2RGB_ITU601_00_255;
		}
	} else { /* YUV to YUV    or   RGB to RGB */
		LOG_DBG("---- YUV to YUV or RGB to RGB ----");
		/* CSC Sel 00: bypass CSC 10: RGB to YUV 11: YUV to RGB */
		it68051_hdmi_write(0x6C, 0x03, 0x00);
	}

	if (mat != CSC_MATRIX_TYPE_COUNT) {
		LOG_DBG("--- CSC_TABLE != NULL ---");
		LOG_DBG("--- Using CSC_TABLE = %d ---", (int)mat);
		it68051_chgbank(1);
		it68051_hdmi_write_block(0x70, (uint8_t *)&csc_matrix[mat][0],
					 sizeof(csc_matrix[0]));
		it68051_chgbank(0);
	} else {
		it68051_chgbank(1);
		it68051_hdmi_write(0x85, 0xFF, 0x00);
		it68051_chgbank(0);
	}

	it68051_set_color_depth();
}

/**
 * @brief Enable the audio output on the I2S bus
 *
 * Based on code in iTE6805_Enable_Audio_Output in iTE6805_SYS.c
 */
void it68051_enable_audio_output(void)
{
	LOG_DBG("iTE6805_Enable_Audio_Output");
	uint16_t sw_sample_freq;
	uint8_t audio_ch_status;
	uint8_t force_sampling_frequency = AUDIO_SAMPLING_44P1K;
	bool reset_audio = false;
	uint32_t sum = 0;
	struct vtiming vt;

	it68051_get_vid_info(&vt);

	it68051_chgbank(0);

	/*
	 * RegForce_CTSMode : need to set to 1 for get the CTS in the PKT,
	 * 0 repersent nothing (HW using)
	 * so set to 1 to get CTS in the REG2C1/2C2/2C0
	 */
	it68051_hdmi_write(0x86, BIT(0), BIT(0));
	/* Read the registers for N and CTS values. */
	it68051_chgbank(2);
	vt.n = ((uint32_t)it68051_hdmi_read(0xBE) << 12) +
	       ((uint32_t)it68051_hdmi_read(0xBF) << 4) +
	       ((uint32_t)it68051_hdmi_read(0xC0) & 0x0F);
	vt.cts = it68051_hdmi_read(0xC0) >> 4;
	vt.cts += ((uint32_t)it68051_hdmi_read(0xC1)) << 12;
	vt.cts += ((uint32_t)it68051_hdmi_read(0xC2)) << 4;

	it68051_get_tmds(10);
	LOG_INF("N = %u", vt.n);
	LOG_INF("CTS = %u", vt.cts);
	LOG_INF("TMDSCLK = %u", vt.tmdsclk);
	it68051_chgbank(0);

	sum = (vt.n * (vt.tmdsclk));
	LOG_INF("sum = %u", sum);

	if (vt.cts == 0) {
		return;
	}
	sw_sample_freq = (uint16_t)(sum / (128 * vt.cts));
	LOG_INF("SW caulate sw_sample_freq = %d", (int)sw_sample_freq);

	if (sw_sample_freq > 25 && sw_sample_freq <= 38) {
		force_sampling_frequency = AUDIO_SAMPLING_32K;
	} else if (sw_sample_freq > 38 && sw_sample_freq <= 45) {
		force_sampling_frequency = AUDIO_SAMPLING_44P1K;
	} else if (sw_sample_freq > 45 && sw_sample_freq <= 58) {
		force_sampling_frequency = AUDIO_SAMPLING_48K;
	} else if (sw_sample_freq > 58 && sw_sample_freq <= 78) {
		force_sampling_frequency = AUDIO_SAMPLING_64K;
	} else if (sw_sample_freq > 78 && sw_sample_freq <= 92) {
		force_sampling_frequency = AUDIO_SAMPLING_88P2K;
	} else if (sw_sample_freq > 92 && sw_sample_freq <= 106) {
		force_sampling_frequency = AUDIO_SAMPLING_96K;
	} else if (sw_sample_freq > 106 && sw_sample_freq <= 166) {
		force_sampling_frequency = AUDIO_SAMPLING_128K;
	} else if (sw_sample_freq > 166 && sw_sample_freq <= 182) {
		force_sampling_frequency = AUDIO_SAMPLING_176P4K;
	} else if (sw_sample_freq > 182 && sw_sample_freq <= 202) {
		force_sampling_frequency = AUDIO_SAMPLING_192K;
	} else if (sw_sample_freq > 224 && sw_sample_freq <= 320) {
		force_sampling_frequency = AUDIO_SAMPLING_256K;
	} else if (sw_sample_freq > 320 && sw_sample_freq <= 448) {
		force_sampling_frequency = AUDIO_SAMPLING_384K;
	} else if (sw_sample_freq > 448 && sw_sample_freq <= 638) {
		force_sampling_frequency = AUDIO_SAMPLING_512K;
	} else if (sw_sample_freq > 638 && sw_sample_freq <= 894) {
		force_sampling_frequency = AUDIO_SAMPLING_768K;
	} else if (sw_sample_freq > 894 && sw_sample_freq <= 1324) {
		force_sampling_frequency = AUDIO_SAMPLING_1024K;
	}

	it68051_chgbank(0);
	/*
	 * in the hdmi2.0 page 84, need bit 24, 25, 26, 27, 30, 31
	 * audio_ch_status : Audio Channel status decoder value[31:24]
	 * and bit[24:27] = Audio Sampling Rate
	 */
	audio_ch_status = it68051_hdmi_read(0xB5) & 0x0F;

	audio_ch_status =
		(audio_ch_status | ((it68051_hdmi_read(0xB6) & 0xC0) >> 2));

	LOG_INF("audio_ch_status[24:27 - 30:31][bit0~bit5] = %x",
		(int)audio_ch_status);
	LOG_INF("iTE6805_DATA.Force_Sampling_Frequency %x",
		(int)(force_sampling_frequency));

	/*
	 * SW calculate Sampling Frequency equal to 60958-3 SPEC channel status,
	 * no need to enable Force FS mode
	 */
	if (audio_ch_status == force_sampling_frequency) {
		LOG_INF("audio_ch_status == force_sampling_frequency");
		if (it68051_hdmi_read(0x81) & BIT(6)) {
			/* If Already Force FS Mode, Need to reset Audio */
			reset_audio = true;
		}

		/* RegForce_FS : 0: Disable Force Audio FS mode */
		it68051_hdmi_write(0x81, BIT(6), 0x00);

		if (reset_audio) {
			it68051_reset_audio_logic();
		}
		audio_sampling_freq_error_count = 0;
		return;
	}

	audio_sampling_freq_error_count++;
	LOG_INF("Current_AudioSamplingFreq_ErrorCount=%d",
		(int)audio_sampling_freq_error_count);

	/* exceed max error count , enable Force Sampling Mode */
	if (audio_sampling_freq_error_count >
	    MAX_AUDIO_SAMPLING_FREQ_ERROR_COUNT) {
		/* RegForce_FS : Force Audio FS mode */
		it68051_hdmi_write(0x81, BIT(6), BIT(6));
		/* RegFS_Set[5:0] : Software set sampling frequency */
		it68051_hdmi_write(0x8A, 0x3F, force_sampling_frequency);

		audio_sampling_freq_error_count = 0;
		it68051_reset_audio_logic();
		LOG_INF("ForceAudio Mode");
	}
}

/**
 * @brief Handle a change in the PWR5V signal for the port
 *
 * If PWR5V has gone active, set HPD and look for video sync.
 * If PWR5V has gone inactive, clear HPD and go to the UNPLUG state
 *
 * Based on code in iTE6805_INT_5VPWR_Chg in iTE6805_SYS.c
 *
 * @param port Which port had the change in PWR5V
 */
static void it68051_int_5v_power_change(enum it68051_port port)
{
	LOG_DBG("iTE6805_INT_5VPWR_Chg");
	if (it68051_is_5v_active(port)) {
		LOG_INF("# Power 5V ON #");
		it68051_video_change_state(WAIT_SYNC);
		it68051_set_hpd(port, true);
	} else {
		LOG_INF("# Power 5V OFF #");
		it68051_set_hpd(port, false);
		it68051_video_change_state(UNPLUG);
	}
}

/**
 * @brief Handle a change in HDMI or DVI mode
 *
 * Based on code in iTE6805_INT_HDMI_DVI_Mode_Chg in iTE6805_SYS.c
 *
 * @param port Which port had the HDMI/DVI mode change
 */
static void it68051_int_hdmi_dvi_mode_change(enum it68051_port port)
{
	LOG_DBG("iTE6805_INT_HDMI_DVI_Mode_Chg");
	if (it68051_is_port_hdmi_mode(port)) {
		if (statev == VID_STABLE) {
			it68051_enable_video_output();
			it68051_audio_change_state(REQUEST_AUDIO);
		}
		LOG_DBG("# HDMI/DVI Mode : HDMI #");
	} else {
		it68051_audio_change_state(AUDIO_OFF);
		if (statev == VID_STABLE) {
			it68051_enable_video_output();
		}
		LOG_DBG("# HDMI/DVI Mode : DVI #");
	}
}

/**
 * @brief Handle interrupt conditions for port 0
 *
 * Based on code in iTE6805_hdmirx_port0_SYS_irq in iTE6805_SYS.c
 */
static void it68051_port0_sys_irq(void)
{
	LOG_DBG("iTE6805_hdmirx_port0_SYS_irq");
	uint8_t reg05h, reg06h, reg08h, reg09h;
	uint8_t reg13h, reg14h, reg15h;

	it68051_chgbank(0);
	reg05h = read_and_clear_interrupt(0x05, 0xFF);
	reg06h = read_and_clear_interrupt(0x06, 0xFF);
	reg08h = read_and_clear_interrupt(0x08, 0xFF);
	reg09h = read_and_clear_interrupt(0x09, 0xFF);

	reg13h = it68051_hdmi_read(0x13);
	reg14h = it68051_hdmi_read(0x14);
	reg15h = it68051_hdmi_read(0x15);

	if (reg05h != 0x00) {
		if (reg05h & BIT(4)) {
			if (it68051_clk_is_valid()) {
				it68051_int_hdmi_dvi_mode_change(PORT2);
			}
		}
		if (reg05h & BIT(5)) {
			LOG_DBG("# Port 0 ECC Error #");
		}
		if (reg05h & BIT(6)) {
			deskew_error_count += 1;
			LOG_DBG("# Port 0 Deskew Error # deskew_error_count=%d",
				(int)deskew_error_count);
		}

		if (reg05h & BIT(7)) {
			LOG_DBG("# Port 0 H2VSkew Fail #");
		}

		if (reg05h & BIT(2)) {
			LOG_DBG("# Port 0 Input Clock Change Detect #");
			ch0_symbol_lock_reset_count = 0;
			ch1_symbol_lock_reset_count = 0;
			ch2_symbol_lock_reset_count = 0;
			if (it68051_hdmi_read(0x13) & BIT(4)) {
				LOG_DBG("# Clock Stable		#");
			} else {
				LOG_DBG("# Clock NOT Stable	#");
			}
		}

		if (reg05h & BIT(1)) {
			ecc_error_count = 0;
			LOG_DBG("# Port 0 Rx CKOn Detect #");
		}

		if (reg05h & BIT(0)) {
			LOG_INF("# Port 0 5V state change INT #");
			it68051_int_5v_power_change(PORT2);
		}
	}

	if (reg06h != 0x00) {
		if (reg06h & BIT(7)) {
			LOG_DBG("# FSM Error  #");
		}

		if (!it68051_is_port0_mhl_mode()) {
			if (reg06h & BIT(6)) {
				LOG_DBG("# CH2 Symbol lock Rst #");
				ch2_symbol_lock_reset_count++;
			}

			if (reg06h & BIT(5)) {
				LOG_DBG("# CH1 Symbol lock Rst #");
				ch1_symbol_lock_reset_count++;
			}
		}

		if (reg06h & BIT(4)) {
			LOG_DBG("# CH0 Symbol lock Rst Count=%d #",
				(int)ch0_symbol_lock_reset_count);
			ch0_symbol_lock_reset_count++;
		}

		if (reg06h & BIT(3)) {
			LOG_DBG("# CH2 CDR FIFO Aut0-Rst #");
		}

		if (reg06h & BIT(2)) {
			LOG_DBG("# CH1 CDR FIFO Aut0-Rst #");
		}

		if (reg06h & BIT(1)) {
			LOG_DBG("# CH0 CDR FIFO Aut0-Rst #");
		}

		if (reg06h & BIT(0)) {
			LOG_DBG("# Symbol Lock State Change #");
			LOG_DBG("0x14 =  %x",
				(int)it68051_hdmi_read(0x14) & 0x38);

			if (reg13h & BIT(7)) {
				LOG_DBG("# Symbol Lock #");
			} else {
				LOG_DBG("# Symbol NOT Lock #");
				if (reg14h & BIT(5))
					LOG_DBG("# CH2 Symbol NOT Lock #");
				if (reg14h & BIT(4))
					LOG_DBG("# CH1 Symbol NOT Lock #");
				if (reg14h & BIT(3))
					LOG_DBG("# CH0 Symbol NOT Lock #");
			}
		}
	}

	if (reg08h != 0x00) {
		if (reg08h & BIT(0)) {
			LOG_INF("# SCDC CLK Ratio Change #");
			it68051_video_change_state(WAIT_SYNC);
			if (reg14h & BIT(6)) {
				LOG_DBG("SCDC CLK Ratio 1/40");
			} else {
				LOG_DBG("SCDC CLK Ratio 1/10");
			}
		}
		if (reg08h & BIT(1)) {
			LOG_DBG("# SCDC Scrambe Enable Change #");
			if (reg14h & BIT(7)) {
				LOG_DBG("SCDC SCR Enable Bit= 1");
			} else {
				LOG_DBG("SCDC SCR Enable Bit= 0");
			}
		}
		if (reg08h & BIT(2)) {
			LOG_DBG("# SCDC Scramble Status Change #");
			if (reg15h & BIT(1)) {
				LOG_DBG("#  SCDC Scarmable Status:  ON  #");
			} else {
				LOG_DBG("#  SCDC Scarmable Status: OFF  #");
			}
		}
		if (reg08h & BIT(3)) {
			LOG_DBG("# EDID Bus Hang #");
		}
		/* Reg 0x08 bit 7 is "Reserved" in the datasheet! */
		if (reg08h & 0x80) { /* HDMI2 Auto Det. */
			LOG_DBG("HDMI2 Det State=%x",
				(it68051_hdmi_read(0x15) & 0x3C) >> 2);
			it68051_hdmi_write(0x4C, 0x80, 0x80);
		}
	}

	if (reg09h != 0x00) {
		if (reg09h & BIT(0)) {
			ecc_error_count = 0;
			LOG_DBG("# Port 0 HDCP Authentication Start #");
		}
		if (reg09h & BIT(1)) {
			LOG_DBG("# Port 0 HDCP Authentication Done #");
		}
		if (reg09h & BIT(3)) {
			ecc_error_count = 0;
			LOG_DBG("# Port 0 HDCP Encryption Off #");
		}
	}
}

/**
 * @brief Handle interrupt conditions for port 1
 *
 * Based on code in iTE6805_hdmirx_port1_SYS_irq in iTE6805_SYS.c
 */
static void it68051_port1_sys_irq(void)
{
	LOG_DBG("it68051_port1_sys_irq");
	uint8_t reg0ah, reg0bh, reg0dh, reg0eh;
	uint8_t reg16h, reg17h, reg18h;

	it68051_chgbank(0);
	reg0ah = read_and_clear_interrupt(0x0A, 0xFF);
	reg0bh = read_and_clear_interrupt(0x0B, 0xFF);
	reg0dh = read_and_clear_interrupt(0x0D, 0xFF);
	reg0eh = read_and_clear_interrupt(0x0E, 0xFF);

	reg16h = it68051_hdmi_read(0x16);
	reg17h = it68051_hdmi_read(0x17);
	reg18h = it68051_hdmi_read(0x18);

	if (reg0ah != 0x00) {
		if (reg0ah & BIT(4)) {
			if (it68051_clk_is_valid()) {
				it68051_int_hdmi_dvi_mode_change(PORT1);
			}
		}
		if (reg0ah & BIT(5)) {
			LOG_DBG("# Port 1 ECC Error #");
		}
		if (reg0ah & BIT(6)) {
			deskew_error_count += 1;
			LOG_DBG("# Port 1 Deskew Error # deskew_error_count=%d",
				(int)deskew_error_count);
		}

		if (reg0ah & BIT(7)) {
			LOG_DBG("# Port 1 H2VSkew Fail #");
		}

		if (reg0ah & BIT(2)) {
			LOG_DBG("# Port 1 Input Clock Change Detect #");
			ch0_symbol_lock_reset_count = 0;
			ch1_symbol_lock_reset_count = 0;
			ch2_symbol_lock_reset_count = 0;
			if (it68051_hdmi_read(0x16) & BIT(4)) {
				LOG_DBG("# Clock Stable		#");
			} else {
				LOG_DBG("# Clock NOT Stable	#");
			}
		}

		if (reg0ah & BIT(1)) {
			ecc_error_count = 0;
			LOG_DBG("# Port 1 Rx CKOn Detect #");
		}

		if (reg0ah & BIT(0)) {
			LOG_INF("# Port 1 5V state change INT #");
			it68051_int_5v_power_change(PORT1);
		}
	}

	if (reg0bh != 0x00) {
		if (reg0bh & BIT(7)) {
			LOG_DBG("# FSM Error  #");
		}

		if (reg0bh & BIT(6)) {
			LOG_DBG("# CH2 Symbol lock Rst #");
			ch2_symbol_lock_reset_count++;
		}

		if (reg0bh & BIT(5)) {
			LOG_DBG("# CH1 Symbol lock Rst #");
			ch1_symbol_lock_reset_count++;
		}

		if (reg0bh & BIT(4)) {
			LOG_DBG("# CH0 Symbol lock Rst #");
			ch0_symbol_lock_reset_count++;
		}

		if (reg0bh & BIT(3)) {
			LOG_DBG("# CH2 CDR FIFO Aut0-Rst #");
		}

		if (reg0bh & BIT(2)) {
			LOG_DBG("# CH1 CDR FIFO Aut0-Rst #");
		}

		if (reg0bh & BIT(1)) {
			LOG_DBG("# CH0 CDR FIFO Aut0-Rst #");
		}

		if (reg0bh & BIT(0)) {
			LOG_DBG("# Symbol Lock State Change #");

			if (reg16h & BIT(7)) {
				LOG_DBG("# Symbol Lock #");
			} else {
				LOG_DBG("# Symbol NOT Lock #");
				if (reg17h & BIT(5))
					LOG_DBG("# CH2 Symbol NOT Lock #");
				if (reg17h & BIT(4))
					LOG_DBG("# CH1 Symbol NOT Lock #");
				if (reg17h & BIT(3))
					LOG_DBG("# CH0 Symbol NOT Lock #");
			}
		}
	}

	if (reg0dh != 0x00) {
		if (reg0dh & BIT(0)) {
			LOG_INF("# SCDC CLK Ratio Change #");
			it68051_video_change_state(WAIT_SYNC);
			if (reg17h & BIT(6)) {
				LOG_DBG("SCDC CLK Ratio 1/40");
			} else {
				LOG_DBG("SCDC CLK Ratio 1/10");
			}
		}
		if (reg0dh & BIT(1)) {
			LOG_DBG("# SCDC Scrambe Enable Change #");
			if (reg17h & BIT(7)) {
				LOG_DBG("SCDC SCR Enable Bit= 1");
			} else {
				LOG_DBG("SCDC SCR Enable Bit= 0");
			}
		}
		if (reg0dh & BIT(2)) {
			LOG_DBG("# SCDC Scramble Status Change #");
			if (reg18h & BIT(1)) {
				LOG_DBG("#  SCDC Scarmable Status:  ON  #");
			} else {
				LOG_DBG("#  SCDC Scarmable Status: OFF  #");
			}
		}
		if (reg0dh & BIT(3)) {
			LOG_DBG("# EDID Bus Hang #");
		}
		/* Reg 0x0D bit 7 is "Reserved" in the datasheet! */
		if (reg0dh & 0x80) { /* HDMI2 Auto Det */
			LOG_DBG("HDMI2 Det State=%x",
				(it68051_hdmi_read(0x15) & 0x3C) >> 2);
			it68051_hdmi_write(0x4C, 0x80, 0x80);
		}
	}

	if (reg0eh != 0x00) {
		if (reg0eh & BIT(0)) {
			ecc_error_count = 0;
			LOG_DBG("# Port 1 HDCP Authentication Start #");
		}
		if (reg0eh & BIT(1)) {
			LOG_DBG("# Port 1 HDCP Authentication Done #");
		}
		if (reg0eh & BIT(3)) {
			ecc_error_count = 0;
			LOG_DBG("# Port 1 HDCP Encryption Off #");
		}
	}
}

/**
 * @brief Check for sync detect
 *
 * Based on code in iTE6805_Check_SCDT in iTE6805_DRV.c
 *
 * @return true if sync detect, false if not
 */
static bool it68051_check_scdt(void)
{
	LOG_DBG("iTE6805_Check_SCDT");
	it68051_chgbank(0);
	return it68051_hdmi_read(0x19) & BIT(7);
}

/**
 * @brief Check for audio detect (AUDT)
 *
 * Based on code in iTE6805_Check_AUDT in iTE6805_DRV.c
 *
 * @return true if AUDT, false if not
 */
static bool it68051_check_audt(void)
{
	LOG_DBG("iTE6805_Check_AUDT");
	/*
	 * REG10[7] : Audio FIFO Error Interrupt
	 * REGB1[7] : Audio is On Flag
	 */
	it68051_chgbank(0);

	bool audio_fifo_error = (it68051_hdmi_read(0x10) & BIT(7)) != 0;
	bool audio_on = (it68051_hdmi_read(0xB1) & BIT(7)) != 0;

	return !audio_fifo_error && audio_on;
}

/**
 * @brief Handle a change in SCDT (sync detect)
 *
 * Based on code in iTE6805_INT_SCDT_Chg in iTE6805_SYS.c
 */
static void it68051_int_scdt_change(void)
{
	LOG_DBG("iTE6805_INT_SCDT_Chg");
	static bool last_scdt;

	if (last_scdt == it68051_check_scdt()) {
		LOG_INF("%s - no change in SCDT", __func__);
		return;
	}
	last_scdt = it68051_check_scdt();
	if (last_scdt) {
		it68051_chgbank(0);
		it68051_hdmi_write(0x40, 0x03, 0x00);
		LOG_INF("# SCDT ON #");
		it68051_video_change_state(CHECK_SYNC);
	} else {
		it68051_chgbank(0);
		it68051_hdmi_write(0x40, 0x03, 0x02);

		LOG_INF("# SCDT OFF #");
		it68051_video_change_state(WAIT_SYNC);
		it68051_audio_change_state(AUDIO_OFF);
	}
}

/**
 * @brief Handle interrupt conditions for the chip, not a specific port
 *
 * Based on code in iTE6805_hdmirx_common_irq in iTE6805_SYS.c
 */
static void it68051_common_irq(void)
{
	LOG_DBG("iTE6805_hdmirx_common_irq");
	uint8_t reg10h, reg11h, reg12h;
	uint8_t reg1ah, reg1bh, reg1dh, regd4h, regd5h;

	it68051_chgbank(0);
	reg10h = read_and_clear_interrupt(0x10, 0xFF);
	reg11h = read_and_clear_interrupt(0x11, 0xBF);
	reg12h = read_and_clear_interrupt(0x12, 0x7F);
	reg1dh = read_and_clear_interrupt(0x1D, 0xFF);
	regd4h = read_and_clear_interrupt(0xD4, 0xFF);
	regd5h = read_and_clear_interrupt(0xD5, 0xFF);

	if (reg10h & BIT(7)) {
		if (statev == VID_STABLE) {
			LOG_DBG("# Audio FIFO Error #");
			/*
			 * TODO(pfagerburg) reset audio logic
			 * and re-enable the audio output.
			 */
		}
	}

	if (reg10h & BIT(6)) {
		LOG_DBG("# Audio Auto Mute #");
	}

	if ((reg10h & BIT(5)) && vid_stable_done) {
		LOG_DBG("# PKT Left Mute #");
		it68051_set_av_mute(false);
	}

	if ((reg10h & BIT(4)) && vid_stable_done) {
		LOG_DBG("# Set Mute PKT Received #");
		it68051_set_av_mute(true);
	}

	if (reg10h & BIT(3)) {
		LOG_DBG("# Timer Counter Tntterrupt #");
	}

	if (reg10h & BIT(2)) {
		LOG_DBG("# Video Mode Changed #");
	}

	if (reg10h & BIT(1)) {
		LOG_DBG("# SCDT Change #");
		it68051_int_scdt_change();
	}

	if (reg10h & BIT(0)) {
		LOG_DBG("# Video Abnormal Interrupt #");
	}

	if (reg11h & BIT(5)) {
		LOG_DBG("# No Audio InfoFrame Received #");
	}

	if (reg11h & BIT(4)) {
		LOG_DBG("# No AVI InfoFrame Received #");
	}

	if (reg11h & BIT(3)) {
		LOG_DBG("# CD Detect #");
	}

	if (reg11h & BIT(1)) {
		it68051_hdmi_write(0x11, 0xFF, BIT(1));
		LOG_DBG("# ISRC2 Detect #");
	}

	if (reg11h & BIT(0)) {
		it68051_hdmi_write(0x11, 0xFF, BIT(0));
		LOG_DBG("# ISRC1 Detect #");
	}

	if (reg12h & BIT(7)) {
		it68051_chgbank(0);
		reg1ah = it68051_hdmi_read(0x1A);
		reg1bh = it68051_hdmi_read(0x1B) & 0x07;
		LOG_DBG("# Video Parameters Change #");
		LOG_DBG("# VidParaChange_Sts=reg1bh=0x%02X reg1ah=0x%02X",
			(int)reg1bh, (int)reg1ah);

		/*
		 * only parameter change need to clear INT here,
		 * or register 1A/1B can't be read after clear.
		 */
		it68051_hdmi_write(0x12, 0xFF, 0x80);
	}
	if (reg12h & BIT(6)) {
		LOG_DBG("# 3D audio Valid Change #");
	}

	if (reg12h & BIT(5)) {
		LOG_DBG("# New DRM PKT Received #");
	}

	if (reg12h & BIT(4)) {
		LOG_DBG("# New Audio PKT Received #");
	}

	if (reg12h & BIT(3)) {
		LOG_DBG("# New ACP PKT Received #");
	}

	if (reg12h & BIT(2)) {
		LOG_DBG("# New SPD PKT Received #");
	}

	if (reg12h & BIT(1)) {
		LOG_DBG("# New MPEG InfoFrame Received #");
	}

	if (reg12h & BIT(0)) {
		uint8_t avi_db[2];

		LOG_DBG("# New AVI InfoFrame Received #");
		it68051_chgbank(2);
		avi_db[0] = it68051_hdmi_read(0x14);
		avi_db[1] = it68051_hdmi_read(0x15);
		it68051_chgbank(0);

		/*
		 * some device may send different resolution  but video
		 * still stable, but it will send new AVI InfoFrame to
		 * tell you so need judge New AVI InfoFrame
		 */
		if (!vid_stable_done) {
			LOG_DBG("vid_stable_done!=true, Save AVI Infoframe.");
			LOG_DBG("avi_db[0] = %x", avi_db[0]);
			LOG_DBG("avi_db[0] = %x", avi_db[1]);
			LOG_DBG("prev_avi_db[0] = %x", prev_avi_db[0]);
			LOG_DBG("prev_avi_db[0] = %x", prev_avi_db[1]);
			prev_avi_db[0] = avi_db[0];
			prev_avi_db[1] = avi_db[1];
			disable_new_aviif_when_param_change = false;
		} else {
			if ((avi_db[0] != prev_avi_db[0]) ||
			    (avi_db[1] != prev_avi_db[1])) {
				prev_avi_db[0] = avi_db[0];
				prev_avi_db[1] = avi_db[1];
				if (disable_new_aviif_when_param_change) {
					disable_new_aviif_when_param_change =
						false;
					new_avi_info_frame = true;
				} else {
					LOG_DBG("avi_db[0] = %x", avi_db[0]);
					LOG_DBG("avi_db[0] = %x", avi_db[1]);
					LOG_DBG("prev_avi_db[0] = %x",
						prev_avi_db[0]);
					LOG_DBG("prev_avi_db[0] = %x",
						prev_avi_db[1]);

					LOG_DBG("# New AVI InfoFrame Recvd #");
					new_avi_info_frame = true;
				}
			}
		}
	}

	if (reg1dh & BIT(0)) {
		LOG_DBG("HDCP2 Authen Start");
	}
	if (reg1dh & BIT(1)) {
		LOG_DBG("HDCP2 Authen Done");
	}
	if (reg1dh & BIT(2)) {
		LOG_DBG("HDCP2 Off Detect");
	}
	if (reg1dh & BIT(3)) {
		LOG_DBG("HDCP Encryption Change");
		if (it68051_hdmi_read(0xD6) & BIT(3)) {
			LOG_DBG("HDCP Encryption ON!");
		} else
			LOG_DBG("HDCP Encryption OFF !");
	}
	if (reg1dh & BIT(4)) {
		if (regd4h & BIT(0)) {
			LOG_DBG("AKE_Init_Rcv");
		}
		if (regd4h & BIT(1)) {
			LOG_DBG("AKE_NoStr_Km_Rcv");
		}
		if (regd4h & BIT(2)) {
			LOG_DBG("AKE_Str_Km_Rcv");
		}
		if (regd4h & BIT(4)) {
			LOG_DBG("LC_Init_Rcv");
		}
		if (regd4h & BIT(5)) {
			LOG_DBG("SKE_Send_Eks_Rcv");
		}
		if (regd4h & BIT(6)) {
			LOG_DBG("Rpt_Send_Ack_Rcv");
		}
		if (regd4h & BIT(7)) {
			LOG_DBG("Rpt_Str_Manage_Rcv");
		}
		if (regd4h & BIT(4)) {
			LOG_DBG("RSA_Fail_pulse");
		}

		if (regd5h & BIT(0)) {
			LOG_DBG("HDCP2 Read CERT Done");
		}
		if (regd5h & BIT(1)) {
			LOG_DBG("HDCP2 Read H Done");
		}
		if (regd5h & BIT(2)) {
			LOG_DBG("HDCP2 Read Pair Done");
		}
		if (regd5h & BIT(3)) {
			LOG_DBG("HDCP2 Read L' Done");
		}
		if (regd5h & BIT(4)) {
			LOG_DBG("HDCP2 Read KSV and V'");
		}
		if (regd5h & BIT(5)) {
			LOG_DBG("Rpt_Send_Ack_Rcv");
		}
		if (regd5h & BIT(6)) {
			LOG_DBG("HDCP2 Message Read Error !!");
		}
		if (regd5h & BIT(7)) {
			LOG_DBG("ECC Re-Authen !!");
		}
	}
}

/**
 * @brief Change the video state machine to a new state
 *
 * This function basically does the "on-enter" for each state.
 *
 * Based on code in iTE6805_vid_chg in iTE6805_SYS.c
 *
 * @param new_state The new state to change to.
 */
static void it68051_video_change_state(enum video_state new_state)
{
	LOG_DBG("iTE6805_vid_chg");
	uint8_t chip_id;

	LOG_INF("%s, %s to %s", __func__, statev_name[statev],
		statev_name[new_state]);
	statev = new_state;

	switch (statev) {
	case VIDEO_OFF:
		it68051_set_hpd(PORT2, false);
		it68051_set_hpd(PORT1, false);
		break;
	case UNPLUG:
		/* Auto Reset when B0 */
		chip_id = it68051_get_chip_id();
		if (chip_id == 0xA0 || chip_id == 0xA1) {
			/*
			 * Unplug need to reset EDID, because EDID reset is
			 * also reset SCDC in hardware, or SCDC may hang in
			 * sometimes.
			 */
			it68051_chgbank(0);
			it68051_hdmi_write(0xC5, 0xFF, 0x12);
			it68051_hdmi_write(0xC5, 0xFF, 0x02);

			it68051_chgbank(4);
			it68051_hdmi_write(0xC5, 0xFF, 0x12);
			it68051_hdmi_write(0xC5, 0xFF, 0x02);
			it68051_chgbank(0);
		}

		/* force set SCDC Clock Ratio 1/40 and Scramble */
		if (it68051_get_selected_port() == PORT2) {
			it68051_chgbank(3);
		} else if (it68051_get_selected_port() == PORT1) {
			it68051_chgbank(7);
		}
		it68051_hdmi_write(0xE5, 0x1C, 0x00);
		it68051_chgbank(0);

		first_time_vid_stable_done = false;
		first_time_param_change = false;
		disable_new_aviif_when_param_change = false;

		vid_stable_done = false;
		downscale = false;
		is_yuv420 = false;

		prev_avi_db[0] = 0;
		prev_avi_db[1] = 0;
		deskew_error_count = 0;
		hdcp_trigger_auto_eq_again = true;
		ch0_symbol_lock_reset_count = 0;
		ch1_symbol_lock_reset_count = 0;
		ch2_symbol_lock_reset_count = 0;
		ipll_relock_count = 0;

		it68051_hdmi_write(0x08, 0xFF, 0x04); /* port0 */
		it68051_hdmi_write(0x0D, 0xFF, 0x04); /* port1 */
		it68051_hdmi_write(0x22, 0xFF, 0x12);
		it68051_hdmi_write(0x22, 0xFF, 0x10);
		it68051_hdmi_write(0x23, 0xFF, 0xAC);
		it68051_hdmi_write(0x23, 0xFF, 0xA0);

		it68051_hdmi_write(0x2B, 0xFF, 0xAC);
		it68051_hdmi_write(0x2B, 0xFF, 0xA0);

		LOG_DBG("VidState change to UNPLUG state");
		it68051_set_video_tristate(true);

		break;
	case WAIT_SYNC:
		first_time_vid_stable_done = false;
		first_time_param_change = false;
		disable_new_aviif_when_param_change = false;
		vid_stable_done = false;
		deskew_error_count = 0;
		ipll_relock_count = 0;
		LOG_DBG("VidState change to WAIT_SYNC state");
		it68051_set_video_tristate(true);
		break;
	case CHECK_SYNC:
		LOG_DBG("VidState change to CHECK_SYNC state");
		scdt_check_count = TIMEOUT_SCDT_CHECK_COUNT;
		break;
	case VID_STABLE:
		LOG_INF("VidState change to VID_STABLE state");
		it68051_chgbank(0);
		/* for enable Rx Chip count */
		it68051_hdmi_write(0x90, 0xFF, 0x8F);

		it68051_get_avi_info_frame_info();
		it68051_show_vid_info();
		it68051_video_output_setting();
		it68051_set_1b0_by_pclk();
		it68051_enable_video_output();

		/*
		 * need to mute audio/video for might lost the PKT in the
		 * moment between Source-Video-In and Sink-Video-Stable
		 * and detect AVMUTE off status in the vid_fsm selection
		 */
		it68051_set_av_mute(true);

		it68051_audio_change_state(REQUEST_AUDIO);

		it68051_reset_video_logic();

		it68051_set_video_tristate(false);

		vid_stable_done = true;
		first_time_vid_stable_done = true;

		break;
	default:
		LOG_DBG("ERROR: VidState change to Unknown state %d!!!",
			statev);
		statev = UNPLUG;
		break;
	}
}

/**
 * @brief Change the audio state machine to a new state
 *
 * This function basically does the "on-enter" for each state.
 *
 * Based on code in iTE6805_aud_chg in iTE6805_SYS.c
 *
 * @param new_state The new state to change to.
 */
static void it68051_audio_change_state(enum audio_state new_state)
{
	LOG_DBG("iTE6805_aud_chg");
	LOG_INF("%s, %s to %s", __func__, statea_name[statea],
		statea_name[new_state]);

	if (statea == new_state)
		return;
	statea = new_state;

	switch (statea) {
	case AUDIO_OFF:
	case REQUEST_AUDIO:
		audio_sampling_freq_error_count = 0;
		it68051_chgbank(0);
		/* RegForce_FS : 0: Disable Force Audio FS mode */
		it68051_hdmi_write(0x81, BIT(6), 0x00);
		it68051_set_audio_tristate(true);
		break;
	case WAIT_FOR_READY:
		it68051_chgbank(0);
		/* set RegHWMuteClr */
		it68051_hdmi_write(0x8C, BIT(4), BIT(4));
		/* clear RegHWMuteClr for clear H/W Mute */
		it68051_hdmi_write(0x8C, BIT(4), 0x00);
		audio_check_count = TIMEOUT_AUDIO_CHECK_COUNT;
		break;
	case AUDIO_ON:
		it68051_show_aud_info();
		it68051_enable_audio_output();
		it68051_set_audio_tristate(false);
		break;
	default:
		LOG_ERR("ERROR: AudState change to Unknown state %d!!!\n",
			statea);
		statea = AUDIO_OFF;
		break;
	}
}

/**
 * @brief Implement the video state machine
 *
 * Based on code in iTE6805_vid_fsm in iTE6805_SYS.c
 */
static void it68051_video_fsm(void)
{
	LOG_DBG("iTE6805_vid_fsm");
	switch (statev) {
	case VIDEO_OFF:
		break;
	case UNPLUG:
		if (it68051_is_5v_active(it68051_get_selected_port())) {
			LOG_INF("UNPLUG state; it68051_is_5v_active == true");
			it68051_int_5v_power_change(
				it68051_get_selected_port());
		}
		break;
	case WAIT_SYNC:
		if (it68051_check_scdt()) {
			it68051_video_change_state(CHECK_SYNC);
		} else {
			if (it68051_clk_is_stable()) {
				ipll_relock_count++;
			}

			if (ipll_relock_count > MAX_IPLL_RELOCK_COUNT) {
				ipll_relock_count = 0;
				it68051_set_47_by_tmds();
			}
		}
		break;
	case CHECK_SYNC:
		if (scdt_check_count == 0) {
			it68051_video_change_state(VID_STABLE);
		} else {
			scdt_check_count--;
		}
		break;
	case VID_STABLE:
		/* New AVI Info Frame */
		if (new_avi_info_frame) {
			LOG_DBG("!!! New AVI InfoFrame in VID_STABLE !!!");
			it68051_get_avi_info_frame_info();
			it68051_show_vid_info();
			it68051_video_output_setting();
			it68051_set_1b0_by_pclk();
			it68051_enable_video_output();
			it68051_reset_video_logic();
			new_avi_info_frame = false;
			first_time_param_change = true;
			it68051_set_video_tristate(false);
		}

		/*
		 * If setting AV by last stable video, and do not receive av
		 * mute clear pkt because HW auto reset and clock and vid
		 * stable again VDGatting will be set by last AV Mute, should
		 * check and clear again
		 */
		it68051_chgbank(0);
		if (it68051_hdmi_read(0x4F) & BIT(5) &&
		    !it68051_check_av_mute()) {
			it68051_set_av_mute(false);
		}
		vid_stable_count++;
		if (vid_stable_count == MAX_VID_STABLE_COUNT) {
			vid_stable_count = 0;
			if (audio_sampling_freq_error_count < 6) {
				audio_sampling_freq_error_count = 0;
			}
		}
		break;

	default:
		LOG_DBG("Video State Error statev=%d!!!", statev);
		statev = UNPLUG;
		break;
	}
}

/**
 * @brief Implement the audio state machine
 *
 * Based on code in iTE6805_aud_fsm in iTE6805_SYS.c
 */
static void it68051_audio_fsm(void)
{
	LOG_DBG("iTE6805_aud_fsm");

	uint8_t audio_b0, audio_b1, audio_b2;
	uint8_t eccerr = 0;

	switch (statea) {
	case AUDIO_OFF:
		break;
	case REQUEST_AUDIO:
		first_time_audio_monitor = true;
		audio_b0 = 0x00;
		audio_b1 = 0x00;
		audio_b2 = 0x00;
		prev_audio_b0 = 0x00;
		prev_audio_b1 = 0x00;
		prev_audio_b2 = 0x00;
		it68051_audio_change_state(WAIT_FOR_READY);
		break;
	case WAIT_FOR_READY:
		if (audio_check_count == 0) {
			if (it68051_get_selected_port() == PORT2) {
				it68051_chgbank(0);
			} else {
				it68051_chgbank(4);
			}
			/*
			 * REG0B9 : P0 Received error
			 * REG4B9 : P1 Received error
			 */
			eccerr = it68051_hdmi_read(0xB9) & 0xC0;
			it68051_chgbank(0);

			if (eccerr) {
				it68051_reset_audio_logic();
			}

			if (it68051_check_scdt() && it68051_check_audt()) {
				it68051_audio_change_state(AUDIO_ON);
				break;
			}
			audio_check_count = TIMEOUT_AUDIO_CHECK_COUNT;
		} else {
			audio_check_count--;
		}
		break;
	case AUDIO_ON:
		if (audio_monitor_count-- == 0) {
			audio_monitor_count = TIMEOUT_AUDIO_MONITOR;
			it68051_chgbank(0);

			if (first_time_audio_monitor == true) {
				prev_audio_b0 = it68051_hdmi_read(0xB0) & 0xF0;
				prev_audio_b1 = it68051_hdmi_read(0xB1);
				prev_audio_b2 = it68051_hdmi_read(0xB2) &
						BIT(1);
				first_time_audio_monitor = false;
				if (prev_audio_b2 == 0x00) {
					it68051_hdmi_write(0x8C, BIT(3), 0);
				} else {
					it68051_hdmi_write(0x8C, BIT(3),
							   BIT(3));
				}
			} else {
				audio_b0 = it68051_hdmi_read(0xB0) & 0xF0;
				audio_b1 = it68051_hdmi_read(0xB1);
				audio_b2 = it68051_hdmi_read(0xB2) & BIT(1);

				if (prev_audio_b0 != audio_b0 ||
				    prev_audio_b1 != audio_b1 ||
				    prev_audio_b2 != audio_b2) {
					it68051_audio_change_state(
						REQUEST_AUDIO);
				}
			}
		}
		break;

	default:
		LOG_ERR("Audio State Error statea=%d!!!", statea);
		statea = AUDIO_OFF;
		break;
	}
}

/**
 * @brief manages initialization and event handling for the IT68051
 *
 * @param unused1 Required by the Zephyr thread API. Unused.
 * @param unused2 Required by the Zephyr thread API. Unused.
 * @param unused3 Required by the Zephyr thread API. Unused.
 */
static void it68051_task(void *unused1, void *unused2, void *unused3)
{
	int retval;

	k_thread_name_set(NULL, "it68051_task");

	for (;;) {
		it68051_lock(); /* Locked until init is done. */

		/*
		 * Note that at start-up, the IT68051 is already in reset, but
		 * after that, we need to actively reset the chip.
		 */
		gpio_set_level(it68051_rst_l, 0);
		k_msleep(25);
		gpio_set_level(it68051_rst_l, 1);

		LOG_INF("it68051_init");
		retval = it68051_init();
		/* Unlock mutex *before* checking results. */
		it68051_unlock();

		if (retval != 0) {
			LOG_ERR("init_68051 failed, retval =%d", retval);
			continue;
		}

		/* Run the IT68051 state machine. */
		LOG_INF("statev = %s", statev_name[statev]);
		for (;;) {
			it68051_lock();
			if (statev != UNPLUG && statev != VIDEO_OFF) {
				if (it68051_get_selected_port() == PORT2) {
					it68051_port0_sys_irq();
				} else {
					it68051_port1_sys_irq();
				}
				it68051_common_irq();
			}

			it68051_video_fsm();
			it68051_audio_fsm();
			it68051_unlock();
			/*
			 * Check the I2C error count, and if it's too high,
			 * reset and re-initialize.
			 */
			if (it68051_get_i2c_error_count() > I2C_ERROR_THRESH) {
				LOG_ERR("I2C error count too high, re-init.");
				it68051_reset_i2c_error_count();
				break;
			}

			/* Delay before running state machine again. */
			k_msleep(100);
		}
	}
}

/**
 * Define priority for the it68051 task.
 */
#define IT68051_PRIORITY 5

/**
 * Define the size of the stack for the it68051 task.
 */
#define IT68051_STACK_SIZE 1000

/**
 * Define and start a thread that will manage the IT68051.
 */
K_THREAD_DEFINE(it68051, IT68051_STACK_SIZE, it68051_task, NULL, NULL, NULL,
		IT68051_PRIORITY, 0, 0);
