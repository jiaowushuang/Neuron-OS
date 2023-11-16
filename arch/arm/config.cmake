#
# Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
#
# SPDX-License-Identifier: GPL-2.0-only
#

cmake_minimum_required(VERSION 3.14)

add_sources(
    DEP ""
    PREFIX arch/arm
    CFILES
        c_traps.c
)

# kconfig
include(arch/arm/${CONFIG_KERNEL_BITS}/config.cmake)
