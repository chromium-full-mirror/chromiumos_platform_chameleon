# Copyright 2020 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

stm32reset: stm32reset.c
	gcc -Wall -Wextra -g -std=gnu89 -o stm32reset stm32reset.c -l gpiod

clean:
	-rm -f stm32reset
