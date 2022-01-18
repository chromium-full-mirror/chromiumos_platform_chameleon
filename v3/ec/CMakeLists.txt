# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.13.1)
set(BOARD_ROOT ${CMAKE_CURRENT_LIST_DIR})
set(BOARD chameleon)

# ---
# TODO b/216092752
# Temporary workaround until we figure out why pw_checksum is being built
# for ARM assembly instead of Thumb-2.
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mcpu=cortex-m7 -mthumb" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mcpu=cortex-m7 -mthumb" CACHE INTERNAL "")
# ---

# Use this copy of Pigweed
get_filename_component(PW_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/pigweed" ABSOLUTE)
set(ENV{PW_ROOT} ${PW_ROOT})

set(dir_pw_third_party_nanopb "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/zephyr/nanopb" CACHE PATH "" FORCE)
set(pw_third_party_nanopb_ADD_SUBDIRECTORY ON CACHE BOOL "" FORCE)

list(APPEND ZEPHYR_EXTRA_MODULES
    ${PW_ROOT}
    ${dir_pw_third_party_nanopb}
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(chameleon)

add_definitions(-DCONFIG_RPC_BUFFER_SIZE=1024)
add_definitions(-DPW_LOG_LEVEL=PW_LOG_LEVEL_INFO)
add_definitions(-DPW_LOG_SHOW_MODULE=1)

# Define the proto library
include($ENV{PW_ROOT}/pw_protobuf_compiler/proto.cmake)
pw_proto_library(
    v3.protos
    SOURCES proto/v3.proto
)

FILE(GLOB app_sources src/*.c src/*.cc)
FILE(GLOB ite_private_sources private/ite/src/*.c)
target_include_directories(app PRIVATE include)
target_include_directories(app PRIVATE private/ite/include)
target_sources(app PRIVATE ${app_sources} ${ite_private_sources})

zephyr_link_libraries(
    v3.protos.nanopb
    v3.protos.nanopb_rpc
)
