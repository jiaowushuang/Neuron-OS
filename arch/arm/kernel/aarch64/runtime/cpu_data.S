/*
 * Copyright (c) 2014-2020, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <asm_macros.S>
#include <cpu_data.h>

.globl	init_cpu_data_ptr
.globl	_cpu_data_by_index

/* -----------------------------------------------------------------
 * void init_cpu_data_ptr(void)
 *
 * Initialise the TPIDR_EL3 register to refer to the cpu_data_t
 * for the calling CPU. This must be called before cm_get_cpu_data()
 *
 * This can be called without a valid stack. It assumes that
 * plat_my_core_pos() does not clobber register x10.
 * clobbers: x0, x1, x10
 * -----------------------------------------------------------------
 */
func init_cpu_data_ptr
	mov	x10, x30
#ifdef 	CONFIG_SMP_SUPPORT
	bl	plat_my_core_pos
#else
	mov 	x0, 0
#endif
	bl	_cpu_data_by_index
	msr	TPIDRX, x0
	ret	x10
endfunc init_cpu_data_ptr

/* -----------------------------------------------------------------
 * cpu_data_t *_cpu_data_by_index(uint32_t cpu_index)
 *
 * Return the cpu_data structure for the CPU with given linear index
 *
 * This can be called without a valid stack.
 * clobbers: x0, x1
 * -----------------------------------------------------------------
 */
func _cpu_data_by_index
	adrp	x2, kernel_stacks+PLATFORM_STACK_SIZE
	add 	x2, x2, :lo12:kernel_stacks+PLATFORM_STACK_SIZE
	mov 	x1, PLATFORM_STACK_SIZE
	madd 	x3, x0, x1, x2	

	mov_imm	x1, CPU_DATA_SIZE
	mul	x0, x0, x1
	adrp	x1, kernel_percpu_data
	add	x1, x1, :lo12:kernel_percpu_data
	add	x0, x0, x1
	str 	x3, [x0, #CPU_STACK_OFFSET]	
	ret
endfunc _cpu_data_by_index
