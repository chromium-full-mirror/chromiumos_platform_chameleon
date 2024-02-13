# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

all: v4l-test-toolbox regmap

LDLIBS = -lz
v4l-test-toolbox: v4l-test-toolbox.c

regmap: regmap.c regmap.h
	cc -o regmap regmap.c

clean:
	rm -f v4l-test-toolbox
	rm -f regmap
