# Using GPIOs in Zephyr

As part of the effort to move the EC to Zephyr, and to bring up the Chameleon
board with Zephyr, we need a good approach for using GPIOs.

The EC has simple `gpio_get_level` and `gpio_set_level` functions that can
operate on any of the GPIOs. We want something like this for Zephyr-based
code.

Zephyr is a little more complicated. We first need a `struct device*` for the
GPIO port. We can get this by using `device_get_binding` and some `DT`
macros. Once we have a `struct device*`, we can call `gpio_pin_configure`
with the `struct device*`, a pin number of type `gpio_pin_t`, and a set of
flags such as `GPIO_OUTPUT_LOW` or `GPIO_INPUT | GPIO_PULL_UP`. We can also
call `gpio_pin_get` to read the value of an input pin.

The GPIO device, pin number, and initial flags are usually stored in the
devicetree. For example, the STM32 Nucleo F103RB evaluation board has an
LED connected to A5 and a pushbutton connected to C13:
```
    leds {
        compatible = "gpio-leds";
        green_led_2: led_2 {
            gpios = <&gpioa 5 GPIO_ACTIVE_HIGH>;
            label = "User LD2";
        };
    };

    gpio_keys {
        compatible = "gpio-keys";
        user_button: button {
            label = "User";
            gpios = <&gpioc 13 GPIO_ACTIVE_LOW>;
        };

```

Getting the GPIO device, pin number, and flags requires using `DT` macros
(usually with an `alias` node in the devicetree to make the name shorter).

To make it easier to use GPIOs, `io.h` provides macros and functions
that wrap the most common Zephyr functions you would otherwise need to call.

## Declare GPIOs in devicetree

In the devicetree file, add a node with a logical name, like the name of the
module that will use the GPIOs. For example, Chameleon's SD card signal mux
has 5 GPIOs. Here is what the devicetree looks like:

```
    sd-mux {
        compatible = "gpio-keys";

        sd_mux_sel {
            gpios = <&gpioe 0 0>;
            label = "SD_MUX_SEL";
        };

        sd_mux_en_l {
        	gpios = <&gpioe 1 0>;
        	label = "SD_MUX_EN_L";
        };

        usd_pwr_sel {
        	gpios = <&gpiob 13 0>;
        	label = "USD_PWR_SEL";
        };

        usd_pwr_en {
        	gpios = <&gpioe 4 0>;
        	label = "USD_PWR_EN";
        };

        usd_cd_det {
        	gpios = <&gpioe 2 0>;
        	label = "USD_CD_DET";
        };
    };
```

Note that we need to declare a `compatible` so that the `gpios` and `label`
are properly typed and recognized. In Zephyr's devicetree schema, a GPIO
is either an output (`gpio-leds`) or an input (`gpio_keys`), so we have
arbitrarily chosen to use `gpio-keys` for our custom GPIOs, even though in this
case, `usd_cd_det` will be an input.

## Update io.h and io.c

In `io.h`, add the name of the GPIO signal to the `gpio_signal` enumeration.
```
    sd_mux_sel,
    sd_mux_en_l,
    usd_pwr_sel,
    usd_pwr_en,
    usd_cd_det,
```

In `io.c`, add the name of the GPIO signal and its group into the `gpios`
array.
```
    GPIO(sd_mux, sd_mux_sel),
    GPIO(sd_mux, sd_mux_en_l),
    GPIO(sd_mux, usd_pwr_sel),
    GPIO(sd_mux, usd_pwr_en),
    GPIO(sd_mux, usd_cd_det),
```

## Using GPIOs

Use the enumerated name to refer to a GPIO when calling the API functions in `io.h`.
For example, to set and get the value of the `dp2_ps8468_sw` GPIO:

```
gpio_set_level(dp2_ps8468_sw, 0);
uint8_t dp2_demux = gpio_get_level(dp2_ps8468_sw);
```

For Zephyr APIs, use `gpio_get_device` and `gpio_get_pin` to get the
`struct device*` and `gpio_pin_t` that the Zephyr APIs need:

```
gpio_init_callback(&pwr_good_cb_data, pwr_good_cb, BIT(gpio_get_pin(pwr_good)));
gpio_add_callback(gpio_get_device(pwr_good), &pwr_good_cb_data);
```

## io.c internals

`io.c` uses a macro to define an array of structs that holds all of the
information about the GPIOs. Since we can't use `device_get_binding` at
compile time, we have to store the name of the device (such as `GPIOB`) in
the table and a `NULL` pointer to hold the `struct device*` that
`device_get_binding` will return. An initialization function (automatically
called during startup) will walk the array, looking up each device and
storing the device pointer into the array, and then configuring the pin
according the flags in the device tree.
