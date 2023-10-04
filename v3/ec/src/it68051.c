/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Portions based on code in iTE6805_DRV.[ch] and iTE6805_SYS.[ch]
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
#include "it68051_i2c.h"

LOG_MODULE_REGISTER(it68051);

/**
 * @brief Keep track of which port has been selected
 */
static enum it68051_port selected_port;

uint8_t it68051_get_chip_id(void)
{
	LOG_DBG("it68051_get_chip_id");
	it68051_chgbank(0);
	return it68051_hdmi_read(0x04);
}

static const char *video_data_path_to_str(enum video_data_path path)
{
	switch (path) {
	case TTL_SDR:
		return "TTL_SDR";
	case TTL_DDR:
		return "TTL_DDR";
	case TTL_HALF_BUS_DDR:
		return "TTL_HALF_BUS_DDR";
	case TTL_SDR_BTA1004:
		return "TTL_SDR_BTA1004";
	case TTL_DDR_BTA1004:
		return "TTL_DDR_BTA1004";
	default:
		return "Invalid value";
	}
}

static const char *video_sync_mode_to_str(enum video_sync_mode mode)
{
	switch (mode) {
	case TTL_SEP_SYNC:
		return "TTL_SEP_SYNC";
	case TTL_EMB_SYNC:
		return "TTL_EMB_SYNC";
	default:
		return "Invalid value";
	}
}

static const char *avi_color_format_to_str(enum avi_color_format format)
{
	switch (format) {
	case COLOR_FORMAT_RGB:
		return "COLOR_FORMAT_RGB";
	case COLOR_FORMAT_YUV422:
		return "COLOR_FORMAT_YUV422";
	case COLOR_FORMAT_YUV444:
		return "COLOR_FORMAT_YUV444";
	case COLOR_FORMAT_YUV420:
		return "COLOR_FORMAT_YUV420";
	case COLOR_FORMAT_BYPASS_CSC:
		return "COLOR_FORMAT_BYPASS_CSC";
	default:
		return "Invalid value";
	}
}

void it68051_set_ttl_video_path(enum video_data_path video_out_data_path,
				enum video_sync_mode video_sync_mode,
				enum avi_color_format output_color_format)
{
	LOG_DBG("iTE6805_Set_TTL_Video_Path(%s, %s, %s)",
		video_data_path_to_str(video_out_data_path),
		video_sync_mode_to_str(video_sync_mode),
		avi_color_format_to_str(output_color_format));
	it68051_chgbank(1);
	it68051_hdmi_write(0xC0, 0x06, 0x02);
	/*
	 * Configure TTL Video Output mode
	 * Reg1C1 [0] TTL half bus DDR mode, [1] TTL full bus DDR mode,
	 * [5] Enable sync embedded , [6] Enable BTA1004 mode
	 * BTA1004 mode must SyncEmb
	 */
	switch (video_out_data_path) {
	case TTL_SDR:
		it68051_hdmi_write(0xC1, 0x02, 0x00);
		break;
	case TTL_DDR:
		it68051_hdmi_write(0xC1, 0x02, 0x02);
		break;
	case TTL_HALF_BUS_DDR:
		it68051_hdmi_write(0xC1, 0x01, 0x01);
		break;
	case TTL_SDR_BTA1004:
		it68051_hdmi_write(0xC1, 0x60, 0x60);
		break;
	case TTL_DDR_BTA1004:
		it68051_hdmi_write(0xC1, 0x62, 0x62);
		break;
	}

	switch (video_sync_mode) {
	case TTL_SEP_SYNC:
		it68051_hdmi_write(0xC1, 0x20, 0x00);
		break;
	case TTL_EMB_SYNC:
		it68051_hdmi_write(0xC1, 0x20, 0x20);
		break;
	}

	it68051_chgbank(0);
	/* Set Video Output Color Format */
	switch (output_color_format) {
	case COLOR_FORMAT_RGB:
		it68051_hdmi_write(0x6B, 0x0C, 0x00);
		break;
	case COLOR_FORMAT_YUV422:
		it68051_hdmi_write(0x6B, 0x0C, 0x04);
		break;
	case COLOR_FORMAT_YUV444:
		it68051_hdmi_write(0x6B, 0x0C, 0x08);
		break;
	case COLOR_FORMAT_YUV420:
		it68051_hdmi_write(0x6B, 0x0C, 0x0C);
		break;
	case COLOR_FORMAT_BYPASS_CSC:
		break;
	}
}

enum pixel_mode it68051_get_pixel_mode(void)
{
	LOG_DBG("iTE6805_Check_Single_Dual_Mode");
	enum pixel_mode ret;

	it68051_chgbank(1);
	if (it68051_hdmi_read(0xC0) & 0x01) {
		ret = MODE_DUAL;
	} else {
		ret = MODE_SINGLE;
	}
	it68051_chgbank(0);
	return ret;
}

void it68051_set_video_tristate(bool is_tristate)
{
	LOG_DBG("iTE6805_Set_Video_Tristate(%s)",
		is_tristate ? "true" : "false");
	it68051_chgbank(0);
	uint8_t color_depth = it68051_hdmi_read(0x98) & 0xF0;

	/*  6805 no RegTriVDIO 3:1 1: enable tri-state Video IO */
	if (is_tristate) {
		it68051_chgbank(1);
		it68051_hdmi_write(0xC5, 0xff, 0xFF);
		it68051_hdmi_write(0xC6, 0xff, 0xFF);
		LOG_DBG("%s(1) -> tristate on", __func__);
	} else {
		it68051_chgbank(1);
		it68051_hdmi_write(0xC5, 0x80, 0x00);
		it68051_hdmi_write(0xC6, 0x80, 0x00);
		if (it68051_get_pixel_mode() == MODE_SINGLE) {
			LOG_INF("%s, in single pixel mode", __func__);
			it68051_chgbank(1);
			switch (it68051_hdmi_read(0xC0) & 0xC0) {
			case 0x00:
			case 0x40:
				/*
				 * setting Tristate IO by IO/Mode & Color Depth
				 * turn off tristate If IO mode do not need it,
				 * only for single mode
				 */
				switch (color_depth) {
				case 0x10: /* 8b */
					it68051_hdmi_write(0xC5, 0xff, 0x78);
					break;
				case 0x20: /* 10b */
					it68051_hdmi_write(0xC5, 0xff, 0x38);
					break;
				default: /* 12b+ */
					it68051_hdmi_write(0xC5, 0xff, 0x18);
					break;
				}
				break;
			case 0x80:
				/*
				 * setting Tristate IO by IO/Mode & Color Depth
				 * turn off tristate If IO mode do not need it,
				 * only for single mode
				 */
				switch (color_depth) {
				case 0x10: /* 8b */
					it68051_hdmi_write(0xC5, 0xff, 0x63);
					break;
				case 0x20: /* 10b */
					it68051_hdmi_write(0xC5, 0xff, 0x23);
					break;
				default: /* 12b+ */
					it68051_hdmi_write(0xC5, 0xff, 0x03);
					break;
				}
				break;
			}
		} else {
			LOG_INF("%s, in dual pixel mode", __func__);
			it68051_chgbank(1);
			switch (color_depth) {
			case 0x10: /* 8b */
				/*
				 * turn off tristate If IO mode do not need it,
				 * only for single mode
				 */
				it68051_hdmi_write(0xC6, 0xff, 0x40);
				break;
			default: /* 10b+ */
				/*
				 * turn off tristate If IO mode do not need it,
				 * only for single mode
				 */
				it68051_hdmi_write(0xC6, 0xff, 0x00);
				break;
			}
		}
		LOG_DBG("%s(0) -> tristate off", __func__);
	}
	/*
	 * Make sure we go back to having register bank 0 selected, so that
	 * another function that doesn't set the register bank doesn't get
	 * unexpected behavior.
	 */
	it68051_chgbank(0);
}

void it68051_set_audio_tristate(bool is_tristate)
{
	LOG_DBG("iTE6805_Set_Audio_Tristate(%s)",
		is_tristate ? "true" : "false");
	it68051_chgbank(1);
	if (is_tristate) {
		/* SPDIF/I2S tri-state on */
		it68051_hdmi_write(0xC7, 0xFF, 0x7F);
	} else {
		/* SPDIF/I2S tri-state off */
		it68051_hdmi_write(0xC7, 0xFF, 0x00);
	}
	it68051_chgbank(0);
}

void it68051_set_hpd(enum it68051_port port, bool hpd_state)
{
	LOG_DBG("iTE6805_Set_HPD_Ctrl(port %d, state %d)", port, hpd_state);
	/* Note that IT68051P0 is connected to DP2/HDMI2, so "PORT2" */
	if (port == PORT2) {
		it68051_chgbank(3);
		if (hpd_state) {
			/* SET IT68051P0 HPD HIGH */
			it68051_hdmi_write(0xAB, 0xC0, 0xC0);
			/* Release MCDP2900 from reset */
			gpio_set_level(dp1_hdmi_rst_l, 1);
		} else {
			/* SET IT68051P0 HPD LOW */
			it68051_hdmi_write(0xAB, 0xC0, 0x40);
			/* Put MCDP2900 into reset */
			gpio_set_level(dp1_hdmi_rst_l, 0);
		}
		/* Reg_P0_ForceCBUS=1 */
		it68051_hdmi_write(0xAC, 0x7C, 0x40);
		it68051_chgbank(0);
	}

	/* PORT1 uses gpio PE15 for HPD */
	if (port == PORT1) {
		gpio_set_level(gp213_it68051p1_hpd, hpd_state ? 1 : 0);
		/* If HPD is active, release MCDP2900 from reset */
		gpio_set_level(dp1_hdmi_rst_l, hpd_state ? 1 : 0);
	}
}

bool it68051_get_hpd(enum it68051_port port)
{
	bool hpd_state = false;

	/* Note that IT68051P0 is connected to DP2/HDMI2, so "PORT2" */
	if (port == PORT2) {
		it68051_chgbank(3);
		uint8_t hpd_ctrl = it68051_hdmi_read(0xAB);

		hpd_state = (hpd_ctrl & BIT(7)) != 0;
		it68051_chgbank(0);
	}

	/* PORT1 uses gpio PE15 for HPD */
	if (port == PORT1) {
		hpd_state = gpio_get_level(gp213_it68051p1_hpd) == 1;
	}

	LOG_DBG("%s(port %d) => %d", __func__, port, hpd_state);
	return hpd_state;
}

void it68051_port_select(enum it68051_port port)
{
	LOG_DBG("iTE6805_Port_Select(%d)", (int)port);
	selected_port = port;
	it68051_chgbank(0);
	if (port == PORT2) {
		/*select IT68051 port 0, which is DP2/HDMI2 */
		it68051_hdmi_write(0x35, 0x01, 0);
		it68051_set_hpd(PORT1, false);
		it68051_set_hpd(PORT2, true);
	} else {
		/*select IT68051 port 1, which is DP1/HDMI1 */
		it68051_hdmi_write(0x35, 0x01, 1);
		if (it68051_get_chip_id() == 0xA0) {
			it68051_hdmi_write(0xE2, 0x01, 0x00);
		}
		it68051_set_hpd(PORT2, false);
		it68051_set_hpd(PORT1, true);
	}
	it68051_chgbank(0);

	/* clear force SCDC setting */
	it68051_chgbank(3);
	it68051_hdmi_write(0xE5, 0x1C, 0x00);
	it68051_chgbank(7);
	it68051_hdmi_write(0xE5, 0x1C, 0x00);
	it68051_chgbank(0);

	/* power setting: turn on main port TMDS and turn off not main port. */
	it68051_chgbank(0);
	it68051_hdmi_write(0x25, 0xff, 0x00);
	if (port == PORT2) {
		it68051_hdmi_write(0x26, 0xff, 0x00);
		it68051_hdmi_write(0x27, 0xff, 0x00);
		it68051_hdmi_write(0x2A, 0xff, 0x01);

		it68051_hdmi_write(0x2D, 0xff, 0xFF);
		it68051_hdmi_write(0x2E, 0xff, 0xFF);
		it68051_hdmi_write(0x2F, 0xff, 0xFF);
		it68051_hdmi_write(0x32, 0xff, 0x3E);

		it68051_chgbank(3);
		it68051_hdmi_write(0xA8, 0x08, 0x08);
		it68051_chgbank(7);
		it68051_hdmi_write(0xA8, 0x08, 0x00);
		it68051_chgbank(0);
	} else {
		it68051_hdmi_write(0x26, 0xff, 0xFF);
		it68051_hdmi_write(0x27, 0xff, 0xFF);
		it68051_hdmi_write(0x2A, 0xff, 0x3A);

		it68051_hdmi_write(0x2D, 0xff, 0x00);
		it68051_hdmi_write(0x2E, 0xff, 0x00);
		it68051_hdmi_write(0x2F, 0xff, 0x00);
		it68051_hdmi_write(0x32, 0xff, 0x01);

		it68051_chgbank(3);
		it68051_hdmi_write(0xA8, 0x08, 0x00);
		it68051_chgbank(7);
		it68051_hdmi_write(0xA8, 0x08, 0x08);
		it68051_chgbank(0);
	}
}

enum it68051_port it68051_get_selected_port(void)
{
	return selected_port;
}

bool it68051_is_5v_active(enum it68051_port port)
{
	LOG_DBG("iTE6805_Check_5V_State(%d)", (int)port);
	if (port == PORT2) {
		return it68051_hdmi_read(0x13) & BIT(0);
	} else {
		return it68051_hdmi_read(0x16) & BIT(0);
	}
}

void it68051_set_av_mute(bool mute)
{
	LOG_DBG("iTE6805_Set_AVMute");
	/*
	 * Register 1C5
	 *  Reg_TriSVDIO    4:0 1: Tri-state Video data when single pixel mode
	 *  Reg_TriSVDLLIO  5   1: Tri-state Video data when single pixel mode
	 *  Reg_TriSVDLHIO  6   1: Tri-state Video data when single pixel mode
	 *  Reg_VIOSel      7   1: VIO Tri-state controlled by VIO setting
	 *                      0: VIO Tri-state controlled by VDIO setting
	 * Register 1C6
	 *  Reg_TriDVDIO    5:0 1: Tri-state Video data when dual pixel mode
	 *  Reg_TriDVDLLIO  6   1: Tri-state Video data when dual pixel mode
	 *  Reg_TriVIO      7   1: Tri-state Video control IO
	 *
	 * Register 4F
	 *  RegDisVAutoMute 7   1: disable video auto mute
	 *  RegVDGatting    5   Enable output data gating to zero when no
	 *                      Video display
	 *
	 * If AVMUTE ON, VIOSel should set 1
	 * If VIOSel = 1, If no data, sync still on.
	 * If VIOSel = 0, If no data, sync will stop.
	 * Therefore AVMute represent sync still on but should disable video.
	 * so set 3 set the output black clock (no data), and set VIOSel
	 * (sync still go on) or it will reSync(Check Stable) again.
	 * If AV Mute On, hardware auto AV mute mute go before SW or it will
	 * be a short delay for shut the screen block so
	 * Hardware auto AVMute on -> disable AVMute for triiger AVMute again.
	 */

	if (mute) {
		it68051_chgbank(0);
		/*
		 * enable VD Gatting
		 * RegDisVAutoMute : 1: Disable video auto mute
		 */
		it68051_hdmi_write(0x4F, BIT(5) | BIT(7), BIT(5) | BIT(7));
		it68051_chgbank(1);
		/*
		 * Reg_VIOSel:
		 * 1: VIO Tri-state controlled by VIO setting,
		 * 0: VIO Tri-state controlled by VDIO setting
		 */
		it68051_hdmi_write(0xC5, BIT(7), BIT(7));
		LOG_INF("+++++++++++ iTE6805_Set_AVMute -> On");
	} else {
		LOG_INF("+++++++++++  iTE6805_Set_AVMute -> Off");
		if (it68051_check_av_mute()) {
			it68051_chgbank(0);
			/* RegDisVAutoMute : 1: Disable video auto mute */
			it68051_hdmi_write(0x4F, BIT(7), BIT(7));
		} else {
			/* clear AV Mute */
			it68051_chgbank(1);
			it68051_hdmi_write(0xC5, BIT(0), BIT(0));
			it68051_hdmi_write(0xC5, BIT(0), 0);
			if (it68051_get_pixel_mode() == MODE_DUAL) {
				it68051_chgbank(1);
				it68051_hdmi_write(0xC5, BIT(0), BIT(0));
			}
			it68051_chgbank(0);
			/* enable VD Gating */
			it68051_hdmi_write(0x4F, BIT(5) | BIT(7),
					   BIT(5) | BIT(7));
			/* disable VD Gating */
			it68051_hdmi_write(0x4F, BIT(5) | BIT(7), BIT(7));
		}
	}
}

bool it68051_check_av_mute(void)
{
	LOG_DBG("iTE6805_Check_AVMute");
	uint8_t temp;
	/*
	 * REG 0AA[3] Port 0 is in AVMute state
	 * REG 4AA[3] Port 1 is in AVMute state
	 */
	if (it68051_get_selected_port() == PORT2) {
		it68051_chgbank(0);
		temp = it68051_hdmi_read(0xAA);
	} else {
		it68051_chgbank(4);
		temp = it68051_hdmi_read(0xAA);
		it68051_chgbank(0);
	}
	return temp & BIT(3);
}

void it68051_reset_video_logic(void)
{
	LOG_DBG("iTE6805_Reset_Video_Logic");
	it68051_chgbank(0);
	it68051_hdmi_write(0x22, BIT(0), BIT(0));
	k_msleep(1);
	it68051_hdmi_write(0x22, BIT(0), 0x00);
	/* clear vidstable change INT */
	it68051_hdmi_write(0x10, BIT(1), BIT(1));
	/* clear vidstable change INT */
	it68051_hdmi_write(0x12, BIT(7), BIT(7));
}

void it68051_reset_audio_logic(void)
{
	LOG_DBG("iTE6805_Reset_Audio_Logic");

	uint8_t temp;

	it68051_chgbank(0);
	it68051_hdmi_write(0x22, BIT(1), BIT(1));
	it68051_hdmi_write(0x22, BIT(1), 0x00);

	/*
	 * The following was in the reference code without comments as to
	 * why they are reading a value and then writing it back 4 times
	 * in a row.
	 *
	 * RegFS_Set[5:0] : Software set sampling frequency R/W
	 */
	temp = it68051_hdmi_read(0x8A);
	it68051_hdmi_write(0x8A, 0xFF, temp);
	it68051_hdmi_write(0x8A, 0xFF, temp);
	it68051_hdmi_write(0x8A, 0xFF, temp);
	it68051_hdmi_write(0x8A, 0xFF, temp);
}

K_MUTEX_DEFINE(it68051_mutex);

void it68051_lock(void)
{
	k_mutex_lock(&it68051_mutex, K_FOREVER);
}

void it68051_unlock(void)
{
	k_mutex_unlock(&it68051_mutex);
}
