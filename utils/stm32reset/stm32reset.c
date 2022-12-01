/* Copyright 2020 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */
/* Cmdline options code from ec/extra/rma_reset/rma_reset.c */
/* gpio calls as shown in libgpiod/gpioset.c */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <gpiod.h>
#include <getopt.h>


static char *progname;
static char *short_opts = "bd:hu";
static const struct option long_opts[] = {
    /* name    hasarg *flag val */
    {"bootloader", 0,   NULL, 'b'},
    {"device",     1,   NULL, 'd'},
    {"help",       0,   NULL, 'h'},
    {"user",       0,   NULL, 'u'},
    {},
};


static void usage(void)
{
    printf("\nUsage: %s [--device N] --bootloader | --user\n"
        "\n"
        "This is used to reset the Chameleon v3's STM32 into bootloader"
        " or user mode.\n"
        "\n"
        "  -d,--device N     Use device #N for GPIO"
        " (default to 0 if not specified)\n"
        "Select one of:\n"
        "  -b,--bootloader   Reset the STM32 into"
        " bootloader mode\n"
        "  -u,--user         Reset the STM32 into"
        " run-from-user-flash mode\n"
        "\n", progname);
}


int main(int argc, char **argv)
{
    int i;
    int b_flag = 0;
    int u_flag = 0;
    /* Default device number */
    char *device = "0";
    /* CBUS pin numbers for RST_L, BOOT1, BOOT0 */
    unsigned int offsets[3] = { 0, 1, 2 };
    /* Values for the CBUS pins to enter bootloader mode */
    int values[3] = { 0, 0, 1 };
    unsigned int num_lines = 3;

    progname = strrchr(argv[0], '/');
    if (progname)
        progname++;
    else
        progname = argv[0];

    opterr = 0;
    while ((i = getopt_long(argc, argv, short_opts, long_opts, 0)) != -1) {
        switch (i) {
            case 'b':
                b_flag = 1;
                break;
            case 'u':
                u_flag = 1;
                break;
            case 'd':
                /* Don't need a flag, just overwrite the default value. */
                device = optarg;
                break;
            case 'h':
            default:
                usage();
                return 0;
        }
    }

    /* Require either -b or -u flag. */
    if (!b_flag && !u_flag) {
        usage();
        return 1;
    }

    /* Require only one of the -b or -u flag. */
    if (b_flag && u_flag) {
        usage();
        return 1;
    }

    /* If booting into user mode, change the value for BOOT0 pin. */
    if (u_flag) {
        values[2] = 0;
    }

    /* Write pins with RST_L low. */
    i = gpiod_ctxless_set_value_multiple(
        device, offsets, values,
        num_lines, false, progname,
        NULL, NULL);
    if (i < 0) {
        fprintf(stderr, "%s: error setting the GPIO line values: %s\n",
            progname, strerror(errno));
        return 1;
    }

    sleep(1);

    /* Change RST_L high and set the pins again. */
    values[0] = 1;
    i = gpiod_ctxless_set_value_multiple(
        device, offsets, values,
        num_lines, false, progname,
        NULL, NULL);
    if (i < 0) {
        fprintf(stderr, "%s: error setting the GPIO line values: %s\n",
            progname, strerror(errno));
        return 1;
    }

    return 0;
}

