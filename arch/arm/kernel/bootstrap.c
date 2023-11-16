/*
 * Copyright (c) 2013-2022, Arm Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <assert.h>

#include <platform_def.h>

#include <arch.h>
#include <arch_features.h>
#include <arch_helpers.h>
#include <bl1/bl1.h>
#include <common.h>
#include <debug.h>
#include <drivers/auth/auth_mod.h>
#include <drivers/auth/crypto_mod.h>
#include <drivers/console/console.h>
#include <lib/cpus/errata_report.h>
#include <utils.h>

void kernel_setup(void)
{

}

void init_process_setup(void)
{

}


void bootstrap_kernel(void)
{
	/* Perform early platform-specific setup - console, .etc */
	early_platform_setup();

	/* Perform late platform-specific setup - memory map, .etc */
	plat_arch_setup();

	/* Perform CPU registers setup when kernel bootstrap */
	cpu_arch_setup();

	/* Perform kernel setup */
	kernel_setup();

	/* Perform init process setup */
	init_process_setup();
	
	console_flush();
}

