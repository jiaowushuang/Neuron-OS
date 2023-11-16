/*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

#include <arch.h>
#include <asm_macros.S>
#include <common.h>
#include <context.h>
#include <lib/xlat_tables/xlat_tables.h>

        .globl arm_undefined_inst_exception
        .globl arm_syscall
        .globl arm_prefetch_abort_exception
        .globl arm_data_abort_exception
        .globl arm_trap
        .globl arm_irq_exception
        .globl arm_fiq_exception

/****************************************
 ***  Traps taken to SVC/HYP/MON mode ***
 ****************************************/

func arm_trap
#ifdef ARM_SUPERVISER_SUPPORT
	b 	report_exception
#endif /* ARM_SUPERVISER_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
	bl 	enter_kernel_entry
	prepare_kernel_stack
	/* ARM_ARM B3.13.6 */
    	ldcopr  lr, HSR
    	and 	lr, lr, #(HSREC_MASK)
    	cmp 	lr, #(HSREC_SVC << HSREC_SHIFT)
    	beq 	arm_syscall
    	cmp 	lr, #(HSREC_HVC << HSREC_SHIFT)
    	beq 	arm_syscall
    	cmp 	lr, #(HSREC_PREFETCH_ABORT << HSREC_SHIFT)
    	beq 	arm_prefetch_abort
    	cmp 	lr, #(HSREC_DATA_ABORT << HSREC_SHIFT)
    	beq 	arm_data_abort
    	cmp 	lr, #(HSREC_UNKNOWN << HSREC_SHIFT)
   	beq 	arm_undefined_inst

   	/** Everything else is assumed to be a VCPU trap **/
    	ldcopr  r0, HSR
    	b 	user_handle_vcpu_fault	
	b	1f
arm_syscall:
	b	user_syscall_handler
	b	1f
arm_undefined_inst:
	b	user_undefined_handler 
	b	1f
arm_prefetch_abort:
	b 	user_prefetch_abort_handler
	b	1f
arm_data_abort:
	b	user_data_abort_handler
1:
	bl	exit_kernel_entry
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT */
endfunc arm_trap

/*********************************
 *** Traps taken from SVC/HYP/MON mode ***
 *********************************/

func arm_prefetch_abort_exception
#ifdef ARM_SUPERVISER_SUPPORT
	bl 	enter_kernel_entry
	ldr	r9, [sp, #CTX_SPSR_SVC]
    	/* Ensure the bottom 4 bits of SPSR are zero, indicating we came from
     	 * userspace. If not, something has gone amiss in the kernel. 
     	 */
    	tst     r9, #0xf
    	bne	kernel_prefetch_fault
	prepare_kernel_stack
	b	user_prefetch_abort_handler
	bl	exit_kernel_entry	
kernel_prefetch_fault:
	prepare_kernel_stack
	b 	kernel_prefetch_abort_handler
	ldcopr  r9, ISFR 	/* Get ISFR. */
	b 	report_exception /* Infinite loop. You'd better have a watchdog. */	
#endif /* ARM_SUPERVISER_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
	prepare_kernel_stack
	blx	kernel_prefetch_abort_handler
	ldcopr  r9, HSR    /* Get Hype Syndrome Register. */
    	ldcopr  r10, HIFAR /* Get fault address register. */
	b 	report_exception
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT */
endfunc arm_prefetch_abort_exception

func arm_data_abort_exception
#ifdef ARM_SUPERVISER_SUPPORT
	bl 	enter_kernel_entry
	ldr	r9, [sp, #CTX_SPSR_SVC]
    	/* Ensure the bottom 4 bits of SPSR are zero, indicating we came from
     	 * userspace. If not, something has gone amiss in the kernel. 
     	 */
    	tst     r9, #0xf
    	bne	kernel_data_fault
	prepare_kernel_stack
	b	user_data_abort_handler
	bl	exit_kernel_entry	
kernel_data_fault:
	prepare_kernel_stack
	b 	kernel_data_abort_handler
	ldcopr  r9, DFSR 	/* Get DFSR. */
	ldcopr  r9, DFAR 	/* Get DFAR. */
	b 	report_exception /* Infinite loop. You'd better have a watchdog. */	
#endif /* ARM_SUPERVISER_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
	prepare_kernel_stack
	blx	kernel_prefetch_abort_handler
	ldcopr  r9, HSR    /* Get Hype Syndrome Register. */
    	ldcopr  r10, HIFAR /* Get fault address register. */
	b 	report_exception
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT */
endfunc arm_data_abort_exception

func arm_undefined_inst_exception
#ifdef ARM_SUPERVISER_SUPPORT
	bl 	enter_kernel_entry
	prepare_kernel_stack
	b 	kernel_undefined_handler
	bl	exit_kernel_entry
#endif /* ARM_SUPERVISER_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
	prepare_kernel_stack
	blx	kernel_undefined_handler
	ldcopr  r9, HSR    /* Get Hype Syndrome Register. */
    	ldcopr  r10, HIFAR /* Get fault address register. */
1: 	b 1b
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT */

#ifdef CONFIG_ARM_MONITOR_SUPPORT
	b 	report_exception
#endif /* CONFIG_ARM_MONITOR_SUPPORT */
endfunc arm_undefined_inst_exception

func arm_syscall
#ifdef ARM_SUPERVISER_SUPPORT
	bl 	enter_kernel_entry
	/*
	 * `sp` still points to `gp_regs_t`. Save it to a register
	 * and restore the C runtime stack pointer to `sp`.
	 */
	mov	r6, sp	
	prepare_kernel_stack
	/* Prepare arguments for CALL wrapper. */
	ldr	r0, [r6, #CTX_GPREG_R0]		/* call_fid */
	mov	r1, #0				/* cookie */
	mov	r2, r6				/* handle of context */
	mov	r3, r7				/* flags:syscallNo */
	b	user_syscall_handler
	bl	exit_kernel_entry
#endif /* ARM_SUPERVISER_SUPPORT */

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
	b	arm_undefined_inst_exception
#endif /* CONFIG_ARM_HYPERVISOR_SUPPORT */
endfunc arm_syscall


/************************
 *** Other exceptions ***
 ************************/
func arm_irq_exception
    	bl 	enter_kernel_entry
    	prepare_kernel_stack
    	b	user_interrupt_handler
	bl	exit_kernel_entry
endfunc arm_irq_exception

func arm_fiq_exception
	b 	report_exception
endfunc arm_fiq_exception

