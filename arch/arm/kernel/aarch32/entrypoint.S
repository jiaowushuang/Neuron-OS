/*
 * Copyright (c) 2016-2021, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <arch.h>
#include <asm_macros.S>
#include <common.h>
#include <context.h>
#include <common_macros.S>
#include <context.S>

	.global arm_verctor_table
	.globl	_start

	/* -----------------------------------------------------
	 * Setup the vector table to support SVC & MON mode.
	 * -----------------------------------------------------
	 */
vector_base arm_verctor_table
	b	_start
	b	arm_undefined_inst_exception	/* Undef */
	b	arm_syscall			/* CALL call */
	b	arm_prefetch_abort_exception	/* Prefetch abort */
	b	arm_data_abort_exception	/* Data abort */
	b	arm_trap			/* Reserved */
	b	arm_irq_exception		/* IRQ */
	b	arm_fiq_exception		/* FIQ */

func _start
	entrypoint_common					\
		_init_sctlr=1					\
		_warm_boot_mailbox=!PROGRAMMABLE_RESET_ADDRESS	\
		_secondary_cold_boot=!COLD_BOOT_SINGLE_CPU	\
		_init_memory=1					\
		_init_c_runtime=1				\
		_exception_vectors=arm_verctor_table		


	bl	bootstrap_kernel

	exit_kernel_entry
endfunc _start
