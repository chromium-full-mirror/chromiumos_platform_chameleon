/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * "Public" API for controling the IT68051 HDMI Receiver.
 */

#ifndef __IT68051_H
#define __IT68051_H

#include <zephyr/kernel.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Note that the HDMI/DP ports are connected to the IT68051 as HDMI1/DP1 to
 * IT68051 Port 1, and HDMI2/DP2 are connected to IT68051 Port **zero**.
 */
enum it68051_port { PORT1 = 1, PORT2 = 0 };

enum pixel_mode { MODE_SINGLE = 0, MODE_DUAL = 1 };

enum avi_color_format {
	COLOR_FORMAT_RGB = 0,
	COLOR_FORMAT_YUV422 = 1,
	COLOR_FORMAT_YUV444 = 2,
	COLOR_FORMAT_YUV420 = 3,
	COLOR_FORMAT_BYPASS_CSC = 4
};

enum avi_colorimetry {
	COLORIMETRY_UNKNOWN,
	COLORIMETRY_ITU601 = 1,
	COLORIMETRY_ITU709 = 2,
	COLORIMETRY_EXTEND = 3
};

enum avi_range_type_rgb {
	RGB_RANGE_DEPENDED_ON_VIC = 0,
	RGB_RANGE_LIMIT = 1,
	RGB_RANGE_FULL = 2,
	RGB_RANGE_RESERVE
};

enum avi_range_type_yuv {
	YUV_RANGE_LIMIT = 0,
	YUV_RANGE_FULL = 1,
	YUV_RANGE_RESERVE1,
	YUV_RANGE_RESERVE2
};

enum video_data_path {
	TTL_SDR = 0,
	TTL_DDR,
	TTL_HALF_BUS_DDR,
	TTL_SDR_BTA1004,
	TTL_DDR_BTA1004
};

enum video_sync_mode {
	TTL_SEP_SYNC = 0,
	TTL_EMB_SYNC,
};

/* Details about the video timing */
struct vtiming {
	uint16_t h_active;
	uint16_t v_active;
	uint16_t h_total;
	uint16_t v_total;
	uint32_t pclk;
	uint32_t tmdsclk;
	uint32_t frame_rate;
	uint16_t h_front_porch;
	uint16_t h_sync_width;
	uint16_t h_back_porch;
	uint16_t v_front_porch;
	uint16_t v_sync_width;
	uint16_t v_back_porch;
	uint16_t scan_mode;
	uint16_t v_polarity;
	uint16_t h_polarity;
	uint32_t n;
	uint32_t cts;
};

/* Details about the audio timing */
struct atiming {
	bool aud_3d_on;
	bool mult_aud_on;
	bool hbr_aud;
	bool dsd_aud;

	/* Can be -1 if invalid */
	int8_t aud_ch;

	/* Fs in Hz, except
	 * 0 = "Refer to Stream Header"
	 * -1 = Invalid
	 */
	int32_t aud_fs;
};

/* Details from the AVI Information Frame */
struct aviif {
	enum avi_color_format aviif_input_color_format;
	enum avi_colorimetry aviif_colorimetry;
	enum avi_range_type_rgb aviif_rgb_quantization_range;
	enum avi_range_type_yuv aviif_yuv_quantization_range;
	uint8_t aviif_vic;
	uint8_t aviif_extended_colorimetry;
};

/**
 * @brief Get the chip ID
 *
 * Several functions depend on the specific silicon version to determine
 * which registers to write and what values to write.
 *
 * @return Chip ID byte
 */
uint8_t it68051_get_chip_id(void);

/**
 * @brief Configure how the decoded video is presented on the output bus
 *
 * Configure the data path (SDR or DDR plus variations), whether sync signals
 * are on separate pins or embedded in the data, and the color format
 * (RGB or a couple of YUV options).
 *
 * Based on code in iTE6805_Set_TTL_Video_Path in iTE6805_DRV.c
 *
 * @param video_out_data_path signalling on the TTL lines
 * @param video_sync_mode if sync is separate or embedded
 * @param output_color_format RGB or YUV format, with possible decimation for
 * YUV format
 */
void it68051_set_ttl_video_path(enum video_data_path video_out_data_path,
				enum video_sync_mode video_sync_mode,
				enum avi_color_format output_color_format);

/**
 * @brief Calculate all kinds of data about the input video stream
 *
 * Based on code in iTE6805_Get_VID_Info in iTE6805_DRV.c
 *
 * @param vt pointer to a struct vtiming to fill in
 */
void it68051_get_vid_info(struct vtiming *vt);

/**
 * @brief Calculate all kinds of data about the input audio stream
 *
 * Based on code in iTE6805_Show_AUD_Info in iTE6805_DRV.c
 *
 * @param at pointer to a struct atiming to fill in
 */
void it68051_get_aud_info(struct atiming *at);

/**
 * @brief Get information from the AVI Information Frame
 *
 * @param if pointer to a struct to fill in
 */
void it68051_get_aviif(struct aviif *info);

/**
 * @brief Determine if the TTL outputs are in single- or dual-pixel mode
 *
 * Based on code in iTE6805_Check_Single_Dual_Mode in iTE6805_DRV.c
 *
 * @return MODE_DUAL or MODE_SINGLE to indicate the pixel mode
 */
enum pixel_mode it68051_get_pixel_mode(void);

/**
 * @brief Set the TTL outputs for single- or dual-pixel mode
 *
 * This function sets an internal flag that `it68051_video_output_setting`
 * uses to write the correct value to the register. So this function
 * is not exactly orthogonal to `it68051_get_pixel_mode`.
 *
 * @param mode MODE_DUAL or MODE_SINGLE
 */
void it68051_set_pixel_mode(enum pixel_mode mode);

/**
 * @brief Query if the link status is active
 *
 * This function just returns the internal variable `vid_stable_done`
 * to indicate if we have an established video link on the IT68051.
 *
 * @return bool indicating if the link is active
 */
bool it68051_get_link_active(void);

/**
 * @brief Control whether the video output pins are tristated
 *
 * @param is_tristate true to tristate the pins, false to actively drive them
 *
 * Based on code in iTE6805_Set_Video_Tristate in iTE6805_DRV.c
 */
void it68051_set_video_tristate(bool is_tristate);

/**
 * @brief Control whether the audio output pins are tristated
 *
 * @param is_tristate true to tristate the pins, false to actively drive them
 *
 * Based on code in iTE6805_Set_Audio_Tristate in iTE6805_DRV.c
 */
void it68051_set_audio_tristate(bool is_tristate);

/**
 * @brief Control the HPD (hot plug detect) signals for both ports
 *
 * HDMI uses a HPD (hot plug detect) signal to indicate that a cable is
 * connected. The sink (that's us) has to assert HPD for the source (that's
 * the Chromebook) to recognize a connected sink, query the EDID, and then
 * start sending data to it.
 *
 * Based on code in iTE6805_Set_HPD_Ctrl and iTE6805_Port_Select_Body in
 * iTE6805_DRV.c
 *
 * b/201944380, when setting HPD low, also pulse the EXT_RESET_N signal
 * for the MCDP2900 DisplayPort to HDMI converter chip. This chip keeps its
 * HPD output asserted, even when the HPD input is de-asserted, and the only
 * way we've found to get HPD to de-assert is to reset the chip. The MCDP2900
 * datasheet is unclear on how long the external reset pulse needs to be
 * (rev H datasheet, figure 4), so we're using a 2ms delay between asserting
 * the reset and releasing it.
 *
 * @param port PORT1 or PORT2
 * @param hpd_state false to de-assert, true to assert
 */
void it68051_set_hpd(enum it68051_port port, bool hpd_state);

/**
 * @brief Query the HPD (hot plug detect) signals for both ports
 *
 * Determine if we are driving HPD on the port.
 *
 * @param port PORT1 or PORT2
 * @return Whether HPD is being asserted
 */
bool it68051_get_hpd(enum it68051_port port);

/**
 * @brief Select which port the HDMI receiver is listening to
 *
 * The IT68051 has two input ports, so we need to tell it which port it
 * should be decoding.
 *
 * Based on code in iTE6805_Port_Select in iTE6805_SYS.c
 *
 * @param port PORT1 or PORT2
 */
void it68051_port_select(enum it68051_port port);

/**
 * @brief Determine  which port the HDMI receiver is listening to
 *
 * @return PORT1 or PORT2
 */
enum it68051_port it68051_get_selected_port(void);

/**
 * @brief Determine if the PWR_DET signal is active for a port
 *
 * Note that since these are controlled by the STM32, they will almost
 * always be active. "almost always"
 * Also, with an HDMI connector, the signal is 5V, but the R0PWR5V and R1PWR5V
 * pins are 3.3V logic/5V tolerant, so the 3.3V from the STM32 works just
 * fine.
 *
 * Based on code in iTE6805_Check_5V_State in iTE6805_DRV.c
 *
 * @param port Port number to check - these are the external port numbers,
 * so PORT2 and PORT1
 * @return true if the PWR_DET input is active, false otherwise
 */
bool it68051_is_5v_active(enum it68051_port port);

/**
 * @brief Mute the audio and video from the HDMI
 *
 * Based on code in iTE6805_Set_AVMute in iTE6805_DRV.c
 *
 * @param mute true to mute, false to unmute
 */
void it68051_set_av_mute(bool mute);

/**
 * @brief Determine if the HDMI A/V inputs are muted
 *
 * Based on code in iTE6805_Check_AVMute in iTE6805_DRV.c
 *
 * @return true if muted, false if not
 */
bool it68051_check_av_mute(void);

/**
 * @brief Reset the video logic and clear the vid-stable interrupt
 *
 * Based on code in iTE6805_Reset_Video_Logic in iTE6805_DRV.c
 */
void it68051_reset_video_logic(void);

/**
 * @brief Reset the audio logic
 *
 * Based on code in iTE6805_Reset_Audio_Logic in iTE6805_DRV.c
 */
void it68051_reset_audio_logic(void);

/**
 * @brief Take exclusive control of the IT68051
 *
 * This function locks a mutex so that other threads (who also use this
 * function) will be blocked until the first one is done.
 */
void it68051_lock(void);

/**
 * @brief Release exclusive control of the IT68051
 *
 * Unlock the mutex and let other threads that use the IT68051 run.
 */
void it68051_unlock(void);

#ifdef __cplusplus
}
#endif

#endif
