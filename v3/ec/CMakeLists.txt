# Copyright 2020 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.13.1)
set(BOARD_ROOT ${CMAKE_CURRENT_LIST_DIR})
set(BOARD chameleon)

if("${ZEPHYR_TOOLCHAIN_VARIANT}" STREQUAL "coreboot-sdk")
include_directories(toolchain/include)
endif()

# Use this copy of Pigweed
get_filename_component(PW_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/pigweed" ABSOLUTE)
set(ENV{PW_ROOT} ${PW_ROOT})

set(dir_pw_third_party_nanopb "${CMAKE_CURRENT_SOURCE_DIR}/../../../../third_party/zephyr/nanopb" CACHE PATH "" FORCE)
set(pw_third_party_nanopb_ADD_SUBDIRECTORY ON CACHE BOOL "" FORCE)

list(APPEND ZEPHYR_EXTRA_MODULES
    ${PW_ROOT}
    ${dir_pw_third_party_nanopb}
)

find_package(Zephyr REQUIRED HINTS ${ZEPHYR_BASE})
project(chameleon)

add_definitions(-DCONFIG_RPC_BUFFER_SIZE=1024)
add_definitions(-DPW_LOG_LEVEL=PW_LOG_LEVEL_INFO)
add_definitions(-DPW_LOG_SHOW_MODULE=1)

# Define the proto library
include($ENV{PW_ROOT}/pw_protobuf_compiler/proto.cmake)
pw_proto_library(
    v3.protos
    SOURCES proto/v3.proto
    INPUTS proto/v3.options
)

add_custom_command(OUTPUT version.h
                   COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/getversion.sh
                   WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/)
add_custom_target(getversion ALL DEPENDS version.h)

FILE(GLOB app_sources src/*.c src/*.cc)
target_include_directories(app PRIVATE include)

# Determine if the private ITE code exists in this checkout.
# If so, add it to the build and remove the 'unimplemented' RPC stubs.
# If not, remove the full implementation of the it68051_service RPC.
#
# Note that files added by GLOB will have a path, so when removing from
# the list of sources, we need to specify the full path.
#
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/private/ite)
    list(REMOVE_ITEM app_sources ${CMAKE_CURRENT_SOURCE_DIR}/src/it68051_service_unimplemented.cc)
    FILE(GLOB ite_private_sources private/ite/src/*.c)
    target_include_directories(app PRIVATE private/ite/include)
else()
    list(REMOVE_ITEM app_sources ${CMAKE_CURRENT_SOURCE_DIR}/src/it68051_service.cc)
    set(ite_private_sources "")
endif()

target_sources(app PRIVATE ${app_sources} ${ite_private_sources})

zephyr_link_libraries(
    v3.protos.nanopb
    v3.protos.nanopb_rpc
)
