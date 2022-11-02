/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Interrupt handler for the DP[12]_HPD pins to reconfigure the PS8468
 * every time HPD asserts.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/logging/log.h>
#include <zephyr/shell/shell.h>
#include <zephyr/sys/__assert.h>
#include "i2c_switch.h"
#include "io.h"

LOG_MODULE_REGISTER(ps8468);

#define PS8468_ADDR 0x0C

static const struct device *i2c_dev = DEVICE_DT_GET(DT_NODELABEL(i2c1));

/**
 * @brief Configure the PS8468 device that corresponds to the given port
 *
 * The PS8468 has the same set of I2C addresses, so each PS8468 is behind
 * an I2C switch. Based on the port number, we set the I2C switch and then
 * access the I2C address for the PS8468.
 *
 * See http://b/186010814#comment21 for the explanation of the registers
 * and values.
 *
 * @param port Port number to configure, must be 1 or 2
 */
static void ps8468_config(uint8_t port) {
        __ASSERT(port == 1 || port == 2, "Port number should be 1 or 2");
        int ret;

        i2c_switch_select_bus(port==1 ? 0 : 1);
        ret = i2c_reg_write_byte(i2c_dev, PS8468_ADDR, 0x03, 0x80);
        if (ret != 0) {
                LOG_ERR("Error %d: failed to write to PS8468\n", ret);
        }
        i2c_switch_select_bus(-1);
}

/**
 * Message queue size. 10 seems reasonable.
 */
#define PS8468_QUEUE_SIZE 10

/**
 * Message queue of which DisplayPort has asserted HPD.
 *
 * The ISR will send the port number (1 or 2) to the queue. The PS8468 task
 * listens on the queue, gets the port number, sets the I2C switch, and
 * configures the PS8468 for that channel.
 *
 * Because the contents are `uint8_t`, an alignment of 1 is fine.
 */
K_MSGQ_DEFINE(ps8468_msgq, sizeof(uint8_t), PS8468_QUEUE_SIZE, 1);

/**
 * Define priotity for the ps8468 task
 */
#define PS8468_PRIORITY 5

/**
 * Define the size of the stack for the ps8468 task.
 */
#define PS8468_STACK_SIZE 500

/**
 * Zephyr macro to allocate the stack area.
 */
K_THREAD_STACK_DEFINE(ps8468_stack_area, PS8468_STACK_SIZE);

/**
 * Internal data structure for tracking the ps8468 task.
 */
static struct k_thread ps8468_thread_data;

/**
 * Wakeup time from HPD assert to ready to use I2C interface.
 *
 * Because latency isn't critical here, use the max SNK/SRC propagation time.
 *
 */
#define PS8468_WAKEUP_TIME 400

/**
 * @brief Run the PS8468 thread
 *
 * This task waits for a signal from the ISR that HPD is asserted, and then
 * configures the PS8468 registers for that channel.

 * @param unused1 Required by the Zephyr thread API. Unused.
 * @param unused2 Required by the Zephyr thread API. Unused.
 * @param unused3 Required by the Zephyr thread API. Unused.
 */
static void ps8468_task(void *unused1, void *unused2, void *unused3)
{
        ARG_UNUSED(unused1);
        ARG_UNUSED(unused2);
        ARG_UNUSED(unused3);

        uint8_t port;

        k_thread_name_set(NULL, "ps8468_task");

        for (;;) {
                if (k_msgq_get(&ps8468_msgq, &port, K_FOREVER) == 0) {
                        k_msleep(PS8468_WAKEUP_TIME);
                        ps8468_config(port);
                }
        }
}

static struct gpio_callback dp1_hpd_cb_data;

static void dp1_hpd_cb(const struct device *dev, struct gpio_callback *cb,
                        uint32_t pins)
{
        uint8_t port = 1;

        /*
         * Despite configuring the interrupt for rising edge, we seem to
         * get interrupts on both edges. Make sure we only post on a
         * rising edge.
         */
        if (gpio_get_level(dp1_mcu_hpd) != 0) {
                k_msgq_put(&ps8468_msgq, &port, K_NO_WAIT);
        }
}

static struct gpio_callback dp2_hpd_cb_data;

static void dp2_hpd_cb(const struct device *dev, struct gpio_callback *cb,
                        uint32_t pins)
{
        uint8_t port = 2;

        /* Only post on a rising edge. */
        if (gpio_get_level(dp2_mcu_hpd) != 0) {
                k_msgq_put(&ps8468_msgq, &port, K_NO_WAIT);
        }
}

/**
 * @brief Initialize the DP[12]_HPD I/Os and start the PS8468 task
 *
 * @param ptr Unused argument, required by SYS_INIT
 * @retval 0
 * No error
 * @retval Non-zero
 * Error code
 */
static int ps8468_init(const struct device *ptr)
{
        ARG_UNUSED(ptr);

        int ret;

        /* Configure DP1_HPD interrupt on a rising edge. */
        ret = gpio_pin_interrupt_configure(gpio_get_device(dp1_mcu_hpd),
                                           gpio_get_pin(dp1_mcu_hpd),
                                           GPIO_INT_EDGE_RISING);
        if (ret != 0) {
                LOG_ERR("Error %d: failed to configure interrupt on DP1_HPD\n",
                        ret);
                return ret;
        }
        gpio_init_callback(&dp1_hpd_cb_data, dp1_hpd_cb,
                           BIT(gpio_get_pin(dp1_mcu_hpd)));
        gpio_add_callback(gpio_get_device(dp1_mcu_hpd), &dp1_hpd_cb_data);

        /* Configure DP2_HPD interrupt on a rising edge. */
        ret = gpio_pin_interrupt_configure(gpio_get_device(dp2_mcu_hpd),
                                           gpio_get_pin(dp2_mcu_hpd),
                                           GPIO_INT_EDGE_RISING);
        if (ret != 0) {
                LOG_ERR("Error %d: failed to configure interrupt on DP1_HPD\n",
                        ret);
                return ret;
        }
        gpio_init_callback(&dp2_hpd_cb_data, dp2_hpd_cb,
                           BIT(gpio_get_pin(dp2_mcu_hpd)));
        gpio_add_callback(gpio_get_device(dp2_mcu_hpd), &dp2_hpd_cb_data);


        /* Create the ps8468 task and start it. */
        k_thread_create(&ps8468_thread_data, ps8468_stack_area,
                        K_THREAD_STACK_SIZEOF(ps8468_stack_area),
                        ps8468_task, NULL, NULL, NULL, PS8468_PRIORITY, 0,
                        K_NO_WAIT);

        return 0;
}
SYS_INIT(ps8468_init, APPLICATION, 80);