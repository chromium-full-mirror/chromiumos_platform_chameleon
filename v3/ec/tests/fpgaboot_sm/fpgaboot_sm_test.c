/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2020 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <ztest.h>

#include "fpgaboot_sm.h"

/*
 * Test helper functions - do something with the FPGA boot-up state machine
 * and verify that the expected actions come out of it.
 */

static void init(enum fpga_state *p_state)
{
	uint32_t actions;

	/*
	 * By default, start with the FPGA off (PWR_EN == 0), which should
	 * move to the OFF state with no actions.
	 */
	fpgaboot_init_state_machine(0, 0, 0, p_state, &actions);

	zassert_equal(actions, 0, "state=%d, actions=%d\n", *p_state, actions);

	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(*p_state), "state=%d\n",
		     *p_state);
}

static void power_on(enum fpga_state *p_state)
{
	uint32_t actions;

	fpgaboot_run_state_machine(FPGABOOT_POWER_ON_REQ, p_state, &actions);
	zassert_equal(actions,
		      FPGABOOT_ASSERT_SOM_PWR_EN | FPGABOOT_START_SHORT_TIMER,
		      "state=%d, actions=%d\n", *p_state, actions);
}

static void power_good(enum fpga_state *p_state)
{
	uint32_t actions;

	fpgaboot_run_state_machine(FPGABOOT_SOM_PWR_GOOD_ASSERTED, p_state,
				   &actions);
	zassert_equal(actions,
		      FPGABOOT_DEASSERT_SOM_POR_L_LOAD_L |
			      FPGABOOT_START_LONG_TIMER,
		      "state=%d, actions=%d\n", *p_state, actions);
}

static void fpga_done(enum fpga_state *p_state)
{
	uint32_t actions;

	fpgaboot_run_state_machine(FPGABOOT_SOM_FPGA_DONE_ASSERTED, p_state,
				   &actions);
	zassert_equal(actions, FPGABOOT_STOP_TIMER, "state=%d, actions=%d\n",
		      *p_state, actions);
}

static void power_off(enum fpga_state *p_state)
{
	uint32_t actions;

	fpgaboot_run_state_machine(FPGABOOT_POWER_OFF_REQ, p_state, &actions);
	zassert_equal(actions,
		      FPGABOOT_DEASSERT_SOM_PWR_EN |
			      FPGABOOT_ASSERT_SOM_POR_L_LOAD_L,
		      "state=%d, actions=%d\n", *p_state, actions);
}

static void power_off_stop_timer(enum fpga_state *p_state)
{
	uint32_t actions;

	fpgaboot_run_state_machine(FPGABOOT_POWER_OFF_REQ, p_state, &actions);
	zassert_equal(actions,
		      FPGABOOT_DEASSERT_SOM_PWR_EN |
			      FPGABOOT_ASSERT_SOM_POR_L_LOAD_L |
			      FPGABOOT_STOP_TIMER,
		      "state=%d, actions=%d\n", *p_state, actions);
}

static void timeout(enum fpga_state *p_state)
{
	uint32_t actions;

	fpgaboot_run_state_machine(FPGABOOT_TIMER_EXPIRED, p_state, &actions);
	zassert_equal(actions,
		      FPGABOOT_DEASSERT_SOM_PWR_EN |
			      FPGABOOT_ASSERT_SOM_POR_L_LOAD_L |
			      FPGABOOT_STOP_TIMER,
		      "state=%d, actions=%d\n", *p_state, actions);
}

/*
 * Normal flow cases - we go to power up, and either it works, or it times
 * out, or we decide to turn off at some point during or after the power
 * and boot sequence is done.
 */

void test_normal_startup(void)
{
	enum fpga_state state;

	/* Initialize and start the power-on sequence. */
	init(&state);
	power_on(&state);
	power_good(&state);
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_power_off_from_running(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	power_on(&state);
	power_good(&state);
	fpga_done(&state);

	/* Now turn it off. */
	power_off(&state);
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
	/*
	 * PWR_GOOD and DONE will de-assert when power is disabled. The state
	 * machine should do nothing about either event.
	 */
	fpgaboot_run_state_machine(FPGABOOT_SOM_PWR_GOOD_DEASSERTED, &state,
				   &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);
	fpgaboot_run_state_machine(FPGABOOT_SOM_FPGA_DONE_DEASSERTED, &state,
				   &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);
}

void test_timeout_while_waiting_for_power_good(void)
{
	enum fpga_state state;

	init(&state);
	power_on(&state);
	/* Oops, timed out waiting for PWR_GOOD. Shut it down. */
	timeout(&state);
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_timeout_while_waiting_for_done(void)
{
	enum fpga_state state;

	init(&state);
	power_on(&state);
	power_good(&state);
	/* Oops, timed out waiting for FPGA DONE. Shut it down. */
	timeout(&state);
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_power_off_while_waiting_for_power_good(void)
{
	enum fpga_state state;

	init(&state);
	power_on(&state);
	/*
	 * Shut down without waiting for power good. Unlike a regular
	 * power off from RUNNING, powering off from here will also stop
	 * the timer.
	 */
	power_off_stop_timer(&state);
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_power_off_while_waiting_for_done(void)
{
	enum fpga_state state;

	init(&state);
	power_on(&state);
	power_good(&state);
	/* Shut down without waiting for FPGA_DONE. */
	power_off_stop_timer(&state);
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

/*
 * Test that we can power on/off/on again.
 */
void test_power_on_off_on(void) {
	enum fpga_state state;
	uint32_t actions;

	/* Turn on the power. */
	init(&state);
	power_on(&state);
	power_good(&state);
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);

	/* Now turn it off. */
	power_off(&state);
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
	/*
	 * PWR_GOOD and DONE will de-assert when power is disabled. The state
	 * machine should do nothing about either event.
	 */
	fpgaboot_run_state_machine(FPGABOOT_SOM_PWR_GOOD_DEASSERTED, &state,
				   &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);
	fpgaboot_run_state_machine(FPGABOOT_SOM_FPGA_DONE_DEASSERTED, &state,
				   &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);

	/* Now turn it on again. */
	power_on(&state);
	power_good(&state);
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

/*
 * NOP cases - asking to turn off when it's already off, asking to turn on
 * when it's already on or on its way to turning on, stuff like that.
 *
 * Power off request while off
 * Power on request while waiting for power good
 * Power on request while waiting for done
 * Power on request while running
 */

void test_power_off_while_off(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	fpgaboot_run_state_machine(FPGABOOT_POWER_OFF_REQ, &state, &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);

	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_power_on_while_waiting_for_power_good(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	power_on(&state);
	/* Send another power on request. It should do nothing. */
	fpgaboot_run_state_machine(FPGABOOT_POWER_ON_REQ, &state, &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);
}

void test_power_on_while_waiting_for_done(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	power_on(&state);
	power_good(&state);
	/* Send another power on request. It should do nothing. */
	fpgaboot_run_state_machine(FPGABOOT_POWER_ON_REQ, &state, &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);
}

void test_power_on_while_running(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	power_on(&state);
	power_good(&state);
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);

	/* Send another power on request. It should do nothing. */
	fpgaboot_run_state_machine(FPGABOOT_POWER_ON_REQ, &state, &actions);
	zassert_equal(actions, 0, "state=%d, actions=%d\n", state, actions);
}

void test_power_good_deassert_while_loading(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	power_on(&state);
	power_good(&state);
	/* Now, before DONE asserts, have PWR_GOOD deassert. */
	fpgaboot_run_state_machine(FPGABOOT_SOM_PWR_GOOD_DEASSERTED, &state,
				   &actions);
	/* It should turn everything off and stop the timer. */
	zassert_equal(actions,
		      FPGABOOT_DEASSERT_SOM_PWR_EN |
			      FPGABOOT_ASSERT_SOM_POR_L_LOAD_L |
			      FPGABOOT_STOP_TIMER,
		      "state=%d, actions=%d\n", state, actions);
}

void test_power_good_deassert_while_running(void)
{
	enum fpga_state state;
	uint32_t actions;

	init(&state);
	power_on(&state);
	power_good(&state);
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);

	/* Send an event that PWR_GOOD has deasserted. */
	fpgaboot_run_state_machine(FPGABOOT_SOM_PWR_GOOD_DEASSERTED, &state,
				   &actions);
	/*
	 * It should turn everything off. The timer already stopped when we
	 * saw DONE asserted.
	 */
	zassert_equal(actions,
		      FPGABOOT_DEASSERT_SOM_PWR_EN |
			      FPGABOOT_ASSERT_SOM_POR_L_LOAD_L,
		      "state=%d, actions=%d\n", state, actions);
}

/*
 * INIT cases where the FPGA is already powered up - verify that the
 * state machine recognizes the conditions and moves to the appropriate
 * state.
 *
 * PWR_EN == 0 is already tested in the "normal" test cases above.
 *
 * PWR_EN == 1 and PWR_GOOD == 0
 *	move to PWR_GOOD
 * PWR_EN == 1 and PWR_GOOD == 1 and FPGA_DONE == 0
 *	move to LOAD
 * PWR_EN == 1 and PWR_GOOD == 1 and FPGA_DONE == 1
 *	move to RUNNING
 *
 * The hardware design ensures that if PWR_EN == 0, then PWR_GOOD and
 * FPGA_DONE must both be 0, and if PWR_GOOD == 0, then FPGA_DONE must be 0.
 */

void test_startup_when_pwr_en_is_1(void) {
	enum fpga_state state;
	uint32_t actions;

	/* PWR_EN == 1, PWR_GOOD == 0, FPGA_DONE == don't-care (use 0). */
	fpgaboot_init_state_machine(1, 0, 0, &state, &actions);
	/* We should be in `FPGABOOT_PWR_GOOD`, so run from there */
	power_good(&state);
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_startup_when_pwr_good_is_1(void) {
	enum fpga_state state;
	uint32_t actions;

	/* PWR_EN == 1, PWR_GOOD == 1, FPGA_DONE == 0. */
	fpgaboot_init_state_machine(1, 1, 0, &state, &actions);
	/* We should be in `FPGABOOT_LOAD`, so run from there */
	fpga_done(&state);
	/* Check that we're settled - either RUNNING or OFF. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n", state);
}

void test_startup_when_fpga_done_is_1(void) {
	enum fpga_state state;
	uint32_t actions;

	/* PWR_EN == 1, PWR_GOOD == 1, FPGA_DONE == 1. */
	fpgaboot_init_state_machine(1, 1, 1, &state, &actions);
	/* We should be in `RUNNING`, so just check if we are steady-state. */
	zassert_true(fpgaboot_is_steady_state(state), "state=%d\n",
		     state);
}

void test_main(void)
{
	ztest_test_suite(
		fpgaboot_sm, ztest_unit_test(test_normal_startup),
		ztest_unit_test(test_power_off_from_running),
		ztest_unit_test(test_timeout_while_waiting_for_power_good),
		// TODO(b/182420309)
		// Revert http://crrev.com/c/2753452
		// and uncomment unit test case
		// ztest_unit_test(test_timeout_while_waiting_for_done),
		ztest_unit_test(test_power_off_while_waiting_for_power_good),
		ztest_unit_test(test_power_off_while_waiting_for_done),
		ztest_unit_test(test_power_on_off_on),
		ztest_unit_test(test_power_off_while_off),
		ztest_unit_test(test_power_on_while_waiting_for_power_good),
		ztest_unit_test(test_power_on_while_waiting_for_done),
		ztest_unit_test(test_power_on_while_running),
		ztest_unit_test(test_power_good_deassert_while_loading),
		ztest_unit_test(test_power_good_deassert_while_running),
		ztest_unit_test(test_startup_when_pwr_en_is_1),
		ztest_unit_test(test_startup_when_pwr_good_is_1),
		ztest_unit_test(test_startup_when_fpga_done_is_1));
	ztest_run_test_suite(fpgaboot_sm);
}
