/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <zephyr/shell/shell.h>
#include "io.h"
#include "sysmon.h"

LOG_MODULE_REGISTER(sysmon);

/**
 * Define the interval for the sysmon timer. Every SYSMON_INTERVAL, the
 * sysmon task will read the next ADC input in the sequence.
 */
#define SYSMON_INTERVAL K_MSEC(100)

/**
 * @brief Input selection for the analog switches.
 */
enum sysmon_sel {
	SYSMON_SEL_SOM, /**< Select the FPGA modules voltage rails. */
	SYSMON_SEL_REGULATORS /**< Select the regulator voltage rails. */
};

struct adc_hdl {
	const struct device *dev;
	struct adc_channel_cfg channel_config;
};

/** @brief The STM32 ADC resolution is fixed at 12 bits. */
#define STM_ADC_RESOLUTION 12

/**
 * @brief Define the ADCs in use.
 */
enum hardware_adc {
	ADC1,
	ADC3
};

/**
 * @brief Declare the ADCs this module uses and the configuration.
 *
 * Note that this module does not use ADC2.
 * 1. All of the analog signals are connected to ADC3 inputs, or inputs that
 *    either ADC1 or ADC2 can use.
 * 2. ADC1 and ADC2 share an ISR. When both are enabled, Zephyr trips an
 *    assertion.
 */
static struct adc_hdl adc_list[] = {
	[ADC1] = {
		.dev = DEVICE_DT_GET(DT_NODELABEL(adc1)),
		.channel_config = {
			.gain = ADC_GAIN_1,
			.reference = ADC_REF_INTERNAL,
			.acquisition_time = ADC_ACQ_TIME_DEFAULT,
			.channel_id = 15,
		},
	},
	[ADC3] = {
		.dev = DEVICE_DT_GET(DT_NODELABEL(adc3)),
		.channel_config = {
			.gain = ADC_GAIN_1,
			.reference = ADC_REF_INTERNAL,
			.acquisition_time = ADC_ACQ_TIME_DEFAULT,
			.channel_id = 4,
		},
	}

};

/**
 * @brief Storage for the ADC readings for each monitored voltage.
 */
static uint16_t adc_reading[SYSMON_VMON_NUM_INPUTS];

/**
 * @brief Mutex protecting access to adc_reading.
 */
static K_MUTEX_DEFINE(adc_reading_mutex);

/**
 * @brief Define a struct with details for each of the monitored voltages.
 *
 * This struct is indexed by the enum for the monitored voltage. It
 * provides the setting for the analog switches, which ADC to read (of
 * the ADCs in adc_list[]), the channel to read, a scaling factor when
 * converting from ADC reading to floating-point, and a name for display
 * purposes.
 * The scale_factor is 1.0 for most of the voltages, but some of them are
 * scaled in hardware to a 3.3V input range. For those voltages, the
 * scale_factor is written as `full_range/scaled_range` and we let the
 * do constant folding.
 */
struct sysmon_adc_input {
	enum sysmon_sel sel; /**< Which way to flip the analog switches. */
	int adc_num; /**< Index into adc_list[] for this signal. */
	int channel; /**< ADC channel to read. */
	float scale_factor; /**< Scaling factor. */
	const char *name; /**< Human-readable name of the signal. */
};

/**
 * @brief Map each monitored voltage to the correct `sysmon_adc_input` values.
 */
static struct sysmon_adc_input scan_table[SYSMON_VMON_NUM_INPUTS] = {
	/* Note that SYSMON_VMON_12V and the CMON inputs are not multiplexed,
	 * so the `sel` value doesn't actually matter.
	 */
	[SYSMON_VMON_12V] = { .sel = SYSMON_SEL_REGULATORS,
			      .adc_num = ADC1,
			      .channel = 10,
			      .scale_factor = 12.0 / 3.0,
			      .name = "12V" },
	[SYSMON_CMON_SOM] = { .sel = SYSMON_SEL_REGULATORS,
			      .adc_num = ADC1,
			      .channel = 11,
			      .scale_factor = 1.0,
			      .name = "CMON_SOM" },
	[SYSMON_CMON_BOARD] = { .sel = SYSMON_SEL_REGULATORS,
				.adc_num = ADC3,
				.channel = 0,
				.scale_factor = 1.0,
				"CMON_BOARD" },

	/* The DisplayPort AUX signals are not multiplexed, so the `sel`
	 * value doesn't matter.
	 */
	[DP1_AUXN_DET] = { .sel = SYSMON_SEL_REGULATORS,
			   .adc_num = ADC3,
			   .channel = 5,
			   .scale_factor = 1.0,
			   "DP1_AUXN_DET" },
	[DP1_AUXP_DET] = { .sel = SYSMON_SEL_REGULATORS,
			   .adc_num = ADC1,
			   .channel = 6,
			   .scale_factor = 1.0,
			   "DP1_AUXP_DET" },
	[DP2_AUXP_DET] = { .sel = SYSMON_SEL_REGULATORS,
			   .adc_num = ADC1,
			   .channel = 16,
			   .scale_factor = 1.0,
			   "DP2_AUXP_DET" },
	[DP2_AUXN_DET] = { .sel = SYSMON_SEL_REGULATORS,
			   .adc_num = ADC1,
			   .channel = 17,
			   .scale_factor = 1.0,
			   "DP2_AUXN_DET" },

	/* The rest of the SYSMON values are multiplexed, so pay attention to
	 * the value of `sel`.
	 */
	[SYSMON_VMON_PP1200] = { .sel = SYSMON_SEL_REGULATORS,
				 .adc_num = ADC3,
				 .channel = 1,
				 .scale_factor = 1.0,
				 .name = "PP1200" },
	[SYSMON_CMON_PP1200] = { .sel = SYSMON_SEL_REGULATORS,
				 .adc_num = ADC1,
				 .channel = 4,
				 .scale_factor = 1.0,
				 .name = "CMON_PP1200" },
	[SYSMON_CMON_PP3300] = { .sel = SYSMON_SEL_REGULATORS,
				 .adc_num = ADC1,
				 .channel = 8,
				 .scale_factor = 1.0,
				 .name = "CMON_PP3300" },
	[SYSMON_VMON_9V] = { .sel = SYSMON_SEL_REGULATORS,
			     .adc_num = ADC3,
			     .channel = 3,
			     .scale_factor = 9.0 / 2.25,
			     .name = "VMON_9V" },
	[SYSMON_VMON_5V] = { .sel = SYSMON_SEL_REGULATORS,
			     .adc_num = ADC3,
			     .channel = 7,
			     .scale_factor = 5.0 / 1.25,
			     .name = "VMON_5V" },
	[SYSMON_VMON_3V3] = { .sel = SYSMON_SEL_REGULATORS,
			      .adc_num = ADC3,
			      .channel = 2,
			      .scale_factor = 3.3 / 2.2,
			      .name = "VMON_3V3" },
	[SYSMON_VMON_PP1800] = { .sel = SYSMON_SEL_REGULATORS,
				 .adc_num = ADC3,
				 .channel = 6,
				 .scale_factor = 1.0,
				 .name = "PP1800" },

	[SYSMON_SOM_VMON] = { .sel = SYSMON_SEL_SOM,
			      .adc_num = ADC3,
			      .channel = 1,
			      .scale_factor = 1.0,
			      .name = "SOM_VMON" },
	[SYSMON_SOM_VMON_1V2] = { .sel = SYSMON_SEL_SOM,
				  .adc_num = ADC1,
				  .channel = 4,
				  .scale_factor = 1.0,
				  .name = "SOM_VMON_1V2" },
	[SYSMON_SOM_VMON_MGT] = { .sel = SYSMON_SEL_SOM,
				  .adc_num = ADC1,
				  .channel = 8,
				  .scale_factor = 1.0,
				  .name = "SOM_VMON_MGT" },
	[SYSMON_SOM_VMON_1V8A] = { .sel = SYSMON_SEL_SOM,
				   .adc_num = ADC3,
				   .channel = 8,
				   .scale_factor = 1.0,
				   .name = "SOM_VMON_1V8A" },
	[SYSMON_SOM_VMON_C8] = { .sel = SYSMON_SEL_SOM,
				 .adc_num = ADC3,
				 .channel = 3,
				 .scale_factor = 1.0,
				 .name = "SOM_VMON_C8" },
	[SYSMON_SOM_VREF_CS1] = { .sel = SYSMON_SEL_SOM,
				  .adc_num = ADC3,
				  .channel = 7,
				  .scale_factor = 1.0,
				  .name = "VREF_CS1" },
	[SYSMON_SOM_VREF_CS2] = { .sel = SYSMON_SEL_SOM,
				  .adc_num = ADC3,
				  .channel = 2,
				  .scale_factor = 1.0,
				  .name = "VREF_CS2" },
	[SYSMON_SOM_VREF_CS3] = { .sel = SYSMON_SEL_SOM,
				  .adc_num = ADC3,
				  .channel = 6,
				  .scale_factor = 1.0,
				  .name = "VREF_CS3" },

};

/**
 * Define priotity for the sysmon task
 */
#define SYSMON_PRIORITY 5

/**
 * Define the size of the stack for the sysmon task.
 */
#define SYSMON_STACK_SIZE 500

/**
 * Zephyr macro to allocate the stack area.
 */
K_THREAD_STACK_DEFINE(sysmon_stack_area, SYSMON_STACK_SIZE);

/**
 * Internal data structure for tracking the sysmon task.
 */
static struct k_thread sysmon_thread_data;

/**
 * Binary semaphore to let the sysmon task wait for the next timer tick
 *
 * The timer handler will signal this semaphone, and the the sysmon task
 * will wait on it. Every time the timer event handles, the sysmon task
 * will get unblocked and sample another ADC input.
 */
K_SEM_DEFINE(sysmon_sem, 0, 1);

/**
 * @brief Timer handler to signal sysmon to sample another ADC input
 *
 * Note that we don't care if the semaphone has already been signaled; it
 * is a binary semaphore, so internally the kernel will just ignore the
 * extra give.
 *
 * @param timer_id Unused, required by signature
 */
static void sysmon_timer_handler(struct k_timer *timer_id)
{
	ARG_UNUSED(timer_id);

	k_sem_give(&sysmon_sem);
}
K_TIMER_DEFINE(sysmon_timer, sysmon_timer_handler, NULL);

/**
 * @brief Store the ADC value for a particular input
 *
 * This internal function provides a way for sysmon to store the ADC readings
 * without worrying about how the tables are organized.
 *
 * @param input Which of the monitored inputs is being set.
 * @param reading The ADC reading to store.
 */
static void sysmon_set_val(enum sysmon_input input, uint16_t reading)
{
	__ASSERT(input < SYSMON_VMON_NUM_INPUTS && (int)input >= 0,
		 "Invalid enum passed to sysmon_set");

	k_mutex_lock(&adc_reading_mutex, K_FOREVER);
	adc_reading[input] = reading;
	k_mutex_unlock(&adc_reading_mutex);
}

/**
 * @brief Read the ADCs sequentially in a loop forever.
 *
 * The sysmon task will step through the list of inputs in an infinite loop.
 * For each input, it will set the analog switches to the correct setting,
 * read the channel from the ADC, and store the reading in the adc_reading
 * array. When it reaches the end of the list, it starts over at the beginning.
 * Between each reading, the thread sleeps to give other threads a chance
 * to run.
 *
 * @param unused1 Required by the Zephyr thread API. Unused.
 * @param unused2 Required by the Zephyr thread API. Unused.
 * @param unused3 Required by the Zephyr thread API. Unused.
 */
static void sysmon_task(void *unused1, void *unused2, void *unused3)
{
	ARG_UNUSED(unused1);
	ARG_UNUSED(unused2);
	ARG_UNUSED(unused3);

	uint16_t sample_buffer;
	int idx = SYSMON_VMON_NUM_INPUTS;
	int ret;

	k_thread_name_set(NULL, "sysmon_task");

	/* Step through the scan_table one entry at a time, resetting to 0
	 * when we get to the end. Loop forever.
	 */
	for (;;) {
		/*
		 * The delay and "next channel" logic is at the start of
		 * this infinite loop so that if we have an error, we
		 * can just `continue`, instead of having nested logic
		 * that goes to the next statement if the previous one
		 * succeeds.
		 */

		/*
		 * Wait for the timer to signal the semaphore, so we don't
		 * starve the system.
		 */
		k_sem_take(&sysmon_sem, K_FOREVER);
		/* Move to the next channel */
		idx++;
		if (idx >= (int)SYSMON_VMON_NUM_INPUTS) {
			idx = 0;
		}

		/* Double-check that the ADC is valid. `adc_num` is an array
		 * index, not the actual ADC number in the datasheet.
		 */
		__ASSERT(scan_table[idx].adc_num < ARRAY_SIZE(adc_list),
			 "Invalid adc_num, exceeds size of adc_list[]");

		/* Read the ADCs one channel at a time. The Zephyr driver
		 * for the STM32 ADC doesn't seem to like a sequence of more
		 * than one ADC channel, even though the hardware supports it.
		 */
		const struct adc_sequence seq = {
			.channels = BIT(scan_table[idx].channel),
			.buffer = &sample_buffer,
			.buffer_size = sizeof(sample_buffer),
			.resolution = STM_ADC_RESOLUTION,
		};

		ret = gpio_set_level(
			sysmon_sel,
			(scan_table[idx].sel == SYSMON_SEL_REGULATORS) ? 1 : 0);
		if (ret < 0) {
			LOG_ERR("gpio_set_level(sysmon_sel) failed, ret = %d\n",
				ret);
			continue;
		}
		if (adc_read(adc_list[scan_table[idx].adc_num].dev, &seq) < 0) {
			continue;
		}
		sysmon_set_val((enum sysmon_input)idx, sample_buffer);
	}
}

float sysmon_get_val(enum sysmon_input input)
{
	__ASSERT((int)input < (int)SYSMON_VMON_NUM_INPUTS && (int)input >= 0,
		 "Invalid enum passed to sysmon_get");

	/* Get the reading inside a mutex. */
	k_mutex_lock(&adc_reading_mutex, K_FOREVER);
	uint16_t reading = adc_reading[input];

	k_mutex_unlock(&adc_reading_mutex);

	/* Convert ADC reading to 3.3V. */
	float val = (float)reading;

	/* This division is by a power of two, so it will only adjust the
	 * floating-point exponent; we won't lose precision in the mantissa.
	 */
	val /= (float)(1 << STM_ADC_RESOLUTION);
	val *= 3.3;
	val *= scan_table[input].scale_factor;

	return val;
}

/** @brief Initialize the system monitor
 *
 * sysmon is responsible for reading several ADC channels to monitor
 * the supply current and voltages. There are more voltages to monitor
 * than ADC input pins, so there are are analog switches to select which
 * sets of voltages is connected to the ADC inputs. sysmon needs to
 * initialize a GPIO to control the analog switches in addition to
 * intializing the ADCs to sample inputs.
 */
static int sysmon_init(void)
{
	int ret = 0;

	/* Configure the ADCs. */
	for (int idx = 0; idx < ARRAY_SIZE(adc_list); ++idx) {
		ret = adc_channel_setup(adc_list[idx].dev,
					&adc_list[idx].channel_config);
		if (ret < 0) {
			LOG_ERR("adc_channel_setup failed, ret = %d\n", ret);
			return ret;
		}
	}

	/* Create the sysmon task and start it. */
	k_thread_create(&sysmon_thread_data, sysmon_stack_area,
			K_THREAD_STACK_SIZEOF(sysmon_stack_area), sysmon_task,
			NULL, NULL, NULL, SYSMON_PRIORITY, 0, K_NO_WAIT);

	/* Start the periodic timer for sysmon */
	k_timer_start(&sysmon_timer, SYSMON_INTERVAL, SYSMON_INTERVAL);

	return ret;
}
SYS_INIT(sysmon_init, APPLICATION, 50);

/**
 * @brief Display all of the monitored values in a friendly format
 *
 * @param shell Our shell data struct; needed for some shell APIs.
 * @param argc Count of arguments passed to this shell command. Unused.
 * @param argv Arguments for this shell command. Unused.
 */
static int cmd_sysmon(const struct shell *shell, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	for (int idx = 0; idx < (int)SYSMON_VMON_NUM_INPUTS; ++idx) {
		shell_fprintf(shell, SHELL_VT100_COLOR_DEFAULT, "%s: %f\n",
			      scan_table[idx].name,
			      sysmon_get_val((enum sysmon_input)idx));
	}
	return 0;
}
SHELL_CMD_REGISTER(sysmon, NULL, "show the SYSMON values", cmd_sysmon);
