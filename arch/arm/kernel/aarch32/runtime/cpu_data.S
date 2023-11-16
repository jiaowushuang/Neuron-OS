/*
 * Copyright (c) 2016, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <asm_macros.S>
#include <cpu_data.h>


	.globl	_cpu_data
	.globl	init_cpu_data_ptr
	.globl	_cpu_data_by_index


/* -----------------------------------------------------------------
 * cpu_data_t *_cpu_data(void)
 *
 * Return the cpu_data structure for the current CPU.
 * -----------------------------------------------------------------
 */
func _cpu_data
	/* r12 is pushed to meet the 8 byte stack alignment requirement */
	push	{r12, lr}
	bl	plat_my_core_pos
	pop	{r12, lr}
	b	_cpu_data_by_index
endfunc _cpu_data


/* -----------------------------------------------------------------
 * void init_cpu_data_ptr(void)
 *
 * Return the cpu_data structure for the current CPU.
 * -----------------------------------------------------------------
 */
func	init_cpu_data_ptr
	push	{r12, lr}
#ifdef 	CONFIG_SMP_SUPPORT
	bl	plat_my_core_pos
#else
	mov 	r0, 0
#endif
	pop	{r12, lr}
	b	_cpu_data_by_index
	stcopr	r0, TPIDRX
endfunc init_cpu_data_ptr

/* -----------------------------------------------------------------
 * cpu_data_t *_cpu_data_by_index(uint32_t cpu_index)
 *
 * Return the cpu_data structure for the CPU with given linear index
 *
 * This can be called without a valid stack.
 * clobbers: r0, r1
 * -----------------------------------------------------------------
 */
func _cpu_data_by_index
	ldr 	r2, =kernel_stacks + PLATFORM_STACK_SIZE
	mov 	r1, PLATFORM_STACK_SIZE
	mla 	r3, r0, r1, r2	

	mov_imm	r1, CPU_DATA_SIZE
	mul	r0, r0, r1
	ldr	r1, =kernel_percpu_data
	add	r0, r0, r1
	str 	r3, [r0, #CPU_STACK_OFFSET]
	bx	lr
endfunc _cpu_data_by_index
