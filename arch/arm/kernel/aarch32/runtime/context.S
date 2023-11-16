/*
 * Copyright (c) 2016-2019, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


#include <arch.h>
#include <asm_macros.S>
#include <assert_macros.S>
#include <platform_def.h>

	.globl	enter_kernel_entry
	.globl	exit_kernel_entry
	.globl 	kernel_stacks
	.globl	update_stack_protector_canary

/* -----------------------------------------------------
 * Per-cpu stacks in normal memory. Each cpu gets a
 * stack of PLATFORM_STACK_SIZE bytes.
 * -----------------------------------------------------
 */
declare_stack kernel_stacks, normal_stacks, \
	PLATFORM_STACK_SIZE, PLATFORM_CORE_COUNT

/* -----------------------------------------------------------------------
 * void update_stack_protector_canary(void)
 *
 * Change the value of the canary used for stack smashing attacks protection.
 * Note: This must be called when it is safe to call C code, but this cannot be
 * called by C code. Doing this will make the check fail when the calling
 * function returns.
 * -----------------------------------------------------------------------
 */

func update_stack_protector_canary
	/* Use r4 as it is callee-saved */
	mov	r4, lr
	bl	plat_get_stack_protector_canary

	/* Update the canary with the returned value */
	ldr	r1,  =__stack_chk_guard
	str	r0, [r1]
	bx	r4
endfunc update_stack_protector_canary

/*
 * Macro to save the General purpose registers (r0 - r12), the banked
 * spsr, lr, sp registers. The `lr` of the current mode (svc/hvc/mon) is expected to be
 * already saved. The `sp` must point to the `gp_regs_t` to save to.
 */
func enter_kernel_entry
	/* Save r0 - r12 in the CALLER context */
	stm	sp, {r0-r12}
	mov	r0, sp
	add	r0, r0, #CTX_SP_USR
	
#if ARM_ARCH_MAJOR == 7 && !defined(CONFIG_ARM_HYPERVISOR_SUPPORT)	
	cps	#MODE32_sys
	stm	r0!, {sp, lr} /* lr: user function LR; sp: user process SP */

#ifdef ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT
	cps	#MODE32_svc
	mrs	r2, spsr
	stm	r0!, {sp, lr, r2} /* lr_svc: svc return LR; sp: `gp_regs_t`; spsr: spsr_svc banked of cpsr */
	b	1f
#endif /* ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT */

	cps	#MODE32_irq
	mrs	r2, spsr
	stm	r0!, {sp, lr, r2}

	cps	#MODE32_fiq
	mrs	r2, spsr
	stm	r0!, {sp, lr, r2}

	cps	#MODE32_abt
	mrs	r2, spsr
	stm	r0!, {sp, lr, r2}

	cps	#MODE32_und
	mrs	r2, spsr
	stm	r0!, {sp, lr, r2}

	cps	#MODE32_mon
	mrs	r2, spsr
	stm	r0!, {sp, lr, r2}

#else
	/* Save the banked registers including the current SPSR and LR */
	mrs	r4, sp_usr
	mrs	r5, lr_usr
	stm	r0!, {r4-r5}
	
#ifdef ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT
	mrs	r4, sp_svc
	mrs	r5, lr_svc
	mrs	r6, spsr_svc
	stm	r0!, {r4-r6}
	b	1f
#endif /* ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT
	mrs	r4, sp_hyp
	mrs	r5, elr_hyp
	mrs	r6, spsr_hyp
	stm	r0!, {r4-r6}	
	b	1f
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT*/

	mrs	r4, sp_irq
	mrs	r5, lr_irq
	mrs	r6, spsr_irq
	
	mrs	r7, sp_fiq
	mrs	r8, lr_fiq
	mrs	r9, spsr_fiq

	mrs	r10, sp_abt
	mrs	r11, lr_abt
	mrs	r12, spsr_abt
	stm	r0!, {r4-r12}
	
	mrs	r4, sp_und
	mrs	r5, lr_und
	mrs	r6, spsr_und

	mrs	r7, sp_mon
	mrs	r8, lr_mon 	
	mrs	r9, spsr_mon
	stm	r0!, {r4-r9}

#endif /* ARM_ARCH_MAJOR == 7 && !defined(CONFIG_ARM_HYPERVISOR_SUPPORT) */

1:
endfunc enter_kernel_entry

/*
 * Macro to restore the `gp_regs_t`, which includes the General purpose
 * registers and banked mode registers, and exit from the (svc/hvc/mon) mode.
 * sp must point to the `gp_regs_t` to restore from.
 */
func exit_kernel_entry
	
	/* 
	 * Restore the `gp_regs_t` context pointer to sp which will be used for handling the
	 * next CALL.
	 */
	prepare_user_stack
	mov 	r0, sp
	/* Restore the banked registers including the current SPSR */
	add	r0, r0, #CTX_SP_USR

#if ARM_ARCH_MAJOR == 7 && !defined(CONFIG_ARM_HYPERVISOR_SUPPORT)
	cps	#MODE32_sys
	ldm	r0!, {sp, lr}
#ifdef ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT
	cps	#MODE32_svc
	ldm	r0!, {sp, lr, r2}
	msr	spsr_fsxc, r2
	b	1f
#endif /* ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT */
	cps	#MODE32_irq
	ldm	r0!, {sp, lr, r2}
	msr	spsr_fsxc, r2

	cps	#MODE32_fiq
	ldm	r0!, {sp, lr, r2}
	msr	spsr_fsxc, r2

	cps	#MODE32_abt
	ldm	r0!, {sp, lr, r2}
	msr	spsr_fsxc, r2

	cps	#MODE32_und
	ldm	r0!, {sp, lr, r2}
	msr	spsr_fsxc, r2
	
	cps	#MODE32_mon
	ldm	r0!, {sp, lr, r2}
	msr	spsr_fsxc, r2
	/*
	 * Use the `_fsxc` suffix explicitly to instruct the assembler
	 * to update all the 32 bits of SPSR. Else, by default, the
	 * assembler assumes `_fc` suffix which only modifies
	 * f->[31:24] and c->[7:0] bits of SPSR.
	 */	
#else
	ldm	r0!, {r4-r5}
	msr	sp_usr, r4
	msr	lr_usr, r5
#ifdef ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT
	ldm	r0!, {r4-r6}
	msr	sp_svc, r4
	msr	lr_svc, r5
	msr	spsr_svc, r6
	b	1f
#endif /* ARM_SUPERVISER_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT
	ldm	r0!, {r4-r6}
	msr	sp_hyp, r4
	msr	lr_hyp, r5
	msr	spsr_hyp, r6
	b	1f
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT || CONFIG_ARM_MONITOR_SUPPORT */

	ldm	r1!, {r4-r12}
	msr	sp_irq, r5
	msr	lr_irq, r6
	msr	spsr_irq, r6

	msr	sp_fiq, r7
	msr	lr_fiq, r8
	msr	spsr_fiq, r9

	msr	sp_abt, r10
	msr	lr_abt, r11
	msr	spsr_abt, r12
	
	ldm	r0!, {r4-r9}
	msr	sp_und, r4
	msr	lr_und, r5
	msr	spsr_und, r6

	msr	sp_mon, r7
	msr	lr_mon, r8
	msr	spsr_mon, r9
#endif /* ARM_ARCH_MAJOR == 7 && !defined(CONFIG_ARM_HYPERVISOR_SUPPORT) */

1:
	/* Restore the rest of the general purpose registers */
	ldm	r0, {r0-r12}
	exception_return
endfunc exit_kernel_entry

