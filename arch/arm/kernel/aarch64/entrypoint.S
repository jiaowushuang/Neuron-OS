/*
 * Copyright (c) 2013-2021, Arm Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <arch.h>
#include <common.h>
#include <common_macros.S>

	.globl	_start
	.globl	cont_kernel_entry

func _start
	entrypoint_common					\
		_init_sctlr=1					\
		_warm_boot_mailbox=!PROGRAMMABLE_RESET_ADDRESS	\
		_secondary_cold_boot=!COLD_BOOT_SINGLE_CPU	\
		_init_memory=1					\
		_init_c_runtime=1				\
		_exception_vectors=arm_exceptions		\

	bl	bootstrap_kernel

#if ENABLE_RUN_IN_CURRENT
	b	cont_kernel_entry
#else
	b	exit_kernel_entry
#endif
endfunc _start

func cont_kernel_entry
	/* read current process */
	mrs x20, TPIDRX
	ldr x20, [x20, #CPU_PROCESS_OFFSET]

	/* MAYTODO: configuration */
	ldp	x0, x1, [x20, #LOGICAL_CPU_PC_OFFSET]
	msr	ELR_ELX, x0
	msr	SPSR_ELX, x1
	exception_return
endfunc cont_kernel_entry
