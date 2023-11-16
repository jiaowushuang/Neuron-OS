/*
 * Copyright (c) 2020-2022, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef COMMON_LD_H
#define COMMON_LD_H

#include <platform_def.h>

#ifdef __aarch64__
#define STRUCT_ALIGN	8
#define BSS_ALIGN	16
#else
#define STRUCT_ALIGN	4
#define BSS_ALIGN	8
#endif

#ifndef DATA_ALIGN
#define DATA_ALIGN	1
#endif

#define CPU_OPS						\
	. = ALIGN(STRUCT_ALIGN);			\
	__CPU_OPS_START__ = .;				\
	KEEP(*(cpu_ops))				\
	__CPU_OPS_END__ = .;

/*
 * The base xlat table
 *
 * It is put into the rodata section if PLAT_RO_XLAT_TABLES=1,
 * or into the bss section otherwise.
 */
#define BASE_XLAT_TABLE					\
	. = ALIGN(16);					\
	__BASE_XLAT_TABLE_START__ = .;			\
	*(base_xlat_table)				\
	__BASE_XLAT_TABLE_END__ = .;

#if PLAT_RO_XLAT_TABLES
#define BASE_XLAT_TABLE_RO		BASE_XLAT_TABLE
#define BASE_XLAT_TABLE_BSS
#else
#define BASE_XLAT_TABLE_RO
#define BASE_XLAT_TABLE_BSS		BASE_XLAT_TABLE
#endif

#define RODATA_COMMON					\
	CPU_OPS						\
	BASE_XLAT_TABLE_RO		

/*
 * .data must be placed at a lower address than the stacks if the stack
 * protector is enabled. Alternatively, the .data.stack_protector_canary
 * section can be placed independently of the main .data section.
 */
#define DATA_SECTION					\
	.data . : ALIGN(DATA_ALIGN) {			\
		__DATA_START__ = .;			\
		*(SORT_BY_ALIGNMENT(.data*))		\
		__DATA_END__ = .;			\
	}

/*
 * The .bss section gets initialised to 0 at runtime.
 * Its base address has bigger alignment for better performance of the
 * zero-initialization code.
 */
#define BSS_SECTION					\
	.bss (NOLOAD) : ALIGN(BSS_ALIGN) {		\
		__BSS_START__ = .;			\
		*(SORT_BY_ALIGNMENT(.bss*))		\
		*(COMMON)				\
		BAKERY_LOCK_NORMAL			\
		PMF_TIMESTAMP				\
		BASE_XLAT_TABLE_BSS			\
		__BSS_END__ = .;			\
	}

/*
 * The xlat_table section is for full, aligned page tables (4K).
 * Removing them from .bss avoids forcing 4K alignment on
 * the .bss section. The tables are initialized to zero by the translation
 * tables library.
 */
#define XLAT_TABLE_SECTION				\
	xlat_table (NOLOAD) : {				\
		__XLAT_TABLE_START__ = .;		\
		*(xlat_table)				\
		__XLAT_TABLE_END__ = .;			\
	}

#endif /* COMMON_LD_H */
