/*
 * Copyright (c) 2015-2016, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <assert.h>

#include <platform_def.h>

#include <arch.h>
#include <arch_helpers.h>
#include <common.h>

#include "qemu_private.h"

/* Data structure which holds the extents of the kernel */
static meminfo_t kernel_ram_layout;

meminfo_t *plat_sec_mem_layout(void)
{
	return &kernel_ram_layout;
}

/*******************************************************************************
 * Perform any specific platform actions.
 ******************************************************************************/
void early_platform_setup(void)
{
	/* Initialize the console to provide early debug support */
	qemu_console_init();

	/* Allow BL1 to see the whole Trusted RAM */
	kernel_ram_layout.total_base = BL_RAM_BASE;
	kernel_ram_layout.total_size = BL_RAM_SIZE;
}

/******************************************************************************
 * Perform the very early platform specific architecture setup.  This only
 * does basic initialization. Later architectural setup
 * does not do anything platform specific.
 *****************************************************************************/
#ifdef __aarch64__
#define QEMU_CONFIGURE_MMU(...)	qemu_configure_mmu_el3(__VA_ARGS__)
#else
#define QEMU_CONFIGURE_MMU(...)	qemu_configure_mmu_svc_mon(__VA_ARGS__)
#endif

void plat_arch_setup(void)
{
	/* ram/ code/ rodata */
	QEMU_CONFIGURE_MMU(kernel_ram_layout.total_base,
				kernel_ram_layout.total_size,
				CODE_BASE, CODE_END,
				RO_DATA_BASE, RO_DATA_END);
}

