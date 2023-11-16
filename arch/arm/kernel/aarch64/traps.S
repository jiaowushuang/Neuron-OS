/*
 * Copyright (c) 2013-2022, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <platform_def.h>
#include <arch.h>
#include <asm_macros.S>
#include <context.h>
#include <common_macros.S>
#include <cpu_data.h>


/* 
 * 0. [lower el,user] 	enter_kernel_entry ; [curr el, kernel] only save reused registers
 * 1. [c]	prepare_kernel_stack
 * 2. [sync]	Enable interrupt? exp type? handler type?
 * 3. [c/asm]	user/kernel_xx_handler, asm_handler
 * 4. [lower el,user]	exit_kernel_entry ; [curr el, kernel, option] only restore reused registers
 */

	.globl	arm_exceptions

	.globl	sync_exception_sp_el0
	.globl	irq_sp_el0
	.globl	fiq_sp_el0
	.globl	serror_sp_el0

	.globl	sync_exception_sp_elx
	.globl	irq_sp_elx
	.globl	fiq_sp_elx
	.globl	serror_sp_elx

	.globl	sync_exception_aarch64
	.globl	irq_aarch64
	.globl	fiq_aarch64
	.globl	serror_aarch64

	.globl	sync_exception_aarch32
	.globl	irq_aarch32
	.globl	fiq_aarch32
	.globl	serror_aarch32

#ifdef MONITOR_BREAKPOINT_SUPPORT
	.section .rodata.brk_string, "aS"
brk_location:
	.asciz "Error at instruction 0x"
brk_message:
	.asciz "Unexpected BRK instruction with value 0x"
#endif /* MONITOR_BREAKPOINT_SUPPORT */


#ifdef RAS_EXTENSION_SUPPORT
	/*
	 * Macro that prepares entry upon taking an exception.
	 *
	 * With RAS_EXTENSION, this macro synchronizes pending errors with an ESB
	 * instruction. When an error is thus synchronized, the handling is
	 * delegated to platform EA handler.
	 *
	 * Without RAS_EXTENSION, this macro synchronizes pending errors using
         * a DSB, unmasks Asynchronous External Aborts and saves X30 before
	 * setting the flag CTX_IS_IN_EL3.
	 */
	.macro handle_sync_pending_ea
	/* Synchronize pending External Aborts */
	esb

	/* Unmask the SError interrupt */
	msr	daifclr, #DAIF_ABT_BIT

	/* <0> */
	bl	save_gp_regs

	/* Check for SErrors synchronized by the ESB instruction */
	mrs	x30, DISR_EL1
	tbz	x30, #DISR_A_BIT, 1f
	
	/* arguments x0,x1 */
	mov	x0, #ERROR_EA_ESB
	mrs	x1, DISR_EL1
	b	ea_proceed

	/* <4> */
	bl	restore_gp_regs
1:	
	.endm
	
	/* ---------------------------------------------------------------------
	 * This macro handles Asynchronous External Aborts.
	 * ---------------------------------------------------------------------
	 */
	.macro	handle_lower_el_async_exception
	msr	daifclr, #DAIF_ABT_BIT
	/* <0> */	
	bl 	enter_kernel_entry

	/* arguments x0,x1 */
	mov	x0, #ERROR_EA_ASYNC
	mrs	x1, ESR_ELX

	/*
	 * Check for Implementation Defined Syndrome. If so, skip checking
	 * Uncontainable error type from the syndrome as the format is unknown.
	 */
	tbnz	x1, #SERROR_IDS_BIT, 1f

	/*
	 * Check for Uncontainable error type. If so, route to the platform
	 * fatal error handler rather than the generic EA one.
	 */
	ubfx	x2, x1, #EABORT_AET_SHIFT, #EABORT_AET_WIDTH
	cmp	x2, #ERROR_STATUS_UET_UC
	b.ne	1f

	/* Check DFSC for SError type */
	ubfx	x3, x1, #EABORT_DFSC_SHIFT, #EABORT_DFSC_WIDTH
	cmp	x3, #DFSC_SERROR
	b.ne	1f

	no_ret	report_unhandled_exception
1:

	b	ea_proceed	

	/* <4> */
	b 	exit_kernel_entry
	.endm

#else
	.macro handle_sync_pending_ea
	/*
	 * For SoCs which do not implement RAS, use DSB as a barrier to
	 * synchronize pending external aborts.
	 */
	dsb	sy

	/* Unmask the SError interrupt */
	msr	daifclr, #DAIF_ABT_BIT

	/* Use ISB for the above unmask operation to take effect immediately */
	isb
	.endm
	
	.macro	handle_lower_el_async_exception
	handle_sync_pending_ea

	/* <0> */	
	bl 	enter_kernel_entry

	/* arguments x0,x1 */
	mov	x0, #ERROR_EA_ASYNC
	mrs	x1, ESR_ELX
	b	ea_proceed	

	/* <4> */
	b 	exit_kernel_entry
	.endm	
#endif /* RAS_EXTENSION_SUPPORT */


	/* ---------------------------------------------------------------------
	 * This macro handles Synchronous exceptions.
	 * ---------------------------------------------------------------------
	 */
	.macro	handler_lower_el_sync_exception
	/* <0> */
	bl 	enter_kernel_entry

	/* <2> */
	mrs	x30, ESR_ELX
	ubfx	x30, x30, #ESR_EC_SHIFT, #ESR_EC_LENGTH

	/* Handle CALL exceptions separately from other synchronous exceptions */
	cmp	x30, #EC_AARCH32_SMC
	b.eq	smc_handler32
	cmp	x30, #EC_AARCH64_SMC
	b.eq	smc_handler64
	cmp	x30, EC_AARCH32_HVC
	b.eq	x30, hvc_handler32
	cmp	x30, EC_AARCH64_HVC
	b.eq	x30, hvc_handler64
	cmp 	x30, #EC_AARCH32_SVC
	b.eq	svc_handler32	
	cmp 	x30, #EC_AARCH64_SVC
	b.eq	svc_handler64	

	/* Synchronous exceptions other than the above are assumed to be EA */	
	cmp 	x30, #EC_DABORT_LOWER_EL
	b.eq 	sync_ea_handler
	cmp 	x30, #EC_IABORT_LOWER_EL
	b.eq	sync_ea_handler

	b	3f

	/* <3> */
smc_handler32:
smc_handler64:
	/* <1> */
	prepare_kernel_stack
	bl	user_smc_handler
	b	2f
hvc_handler32:
hvc_handler64:
	/* <1> */
	prepare_kernel_stack
	bl 	user_hvc_handler
	b	2f
svc_handler32:
svc_handler64:
	/* <1> */
	prepare_kernel_stack
	bl 	user_svc_handler
	b	2f
sync_ea_handler:
	mrs	x30, ESR_ELX
	tbz	x30, #ESR_ISS_EABORT_EA_BIT, 3f

	/*
	 * x0: EA reason
	 * x1: EA syndrome
	 */	
	mov	x0, #ERROR_EA_SYNC
	mrs	x1, ESR_ELX
#ifdef RAS_EXTENSION_SUPPORT
	/*
	 * Check for Uncontainable error type. If so, route to the platform
	 * fatal error handler rather than the generic EA one.
	 */
	ubfx    x2, x1, #EABORT_SET_SHIFT, #EABORT_SET_WIDTH
	cmp     x2, #ERROR_STATUS_SET_UC
	b.ne    1f

	/* Check fault status code */
	ubfx    x3, x1, #EABORT_DFSC_SHIFT, #EABORT_DFSC_WIDTH
	cmp     x3, #SYNC_EA_FSC
	b.ne    1f

	no_ret  report_unhandled_exception	
1:	
#endif /* RAS_EXTENSION_SUPPORT */

	b       ea_proceed
2:
	/* <4> */
	b 	exit_kernel_entry	
3:
	no_ret	report_unhandled_exception
	.endm


	/* ---------------------------------------------------------------------
	 * This macro handles FIQ or IRQ interrupts i.e. EL3, S-EL1 and NS
	 * interrupts.
	 * ---------------------------------------------------------------------
	 */
	.macro	handle_lower_el_interrupt_exception

	/* <0> */
	bl	enter_kernel_entry

	/* <1> */
	prepare_kernel_stack	

	/* <3> */
	bl	user_interrupt_handler

	/* <4> */
	b	exit_kernel_entry
	.endm
	

vector_base arm_exceptions

	/* ---------------------------------------------------------------------
	 * Current EL with SP_EL0 : 0x0 - 0x200
	 * ---------------------------------------------------------------------
	 */
vector_entry sync_exception_sp_el0
#ifdef MONITOR_BREAKPOINT_SUPPORT
	/* <0> */
	str 	x30, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_LR]
	/* <2> */
	mrs	x30, ESR_ELX
	ubfx	x30, x30, #ESR_EC_SHIFT, #ESR_EC_LENGTH
	cmp	x30, #EC_BRK
	/* <3> */
	b.eq	breakpoint_handler
	/* <4> */
	ldr 	x30, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_LR]	
#endif	/* MONITOR_BREAKPOINT_SUPPORT */
	b	report_unhandled_exception
	/* ---------------------------------------------------------------------
	 * The following code handles exceptions caused by BRK instructions.
	 * Following a BRK instruction, the only real valid cause of action is
	 * to print some information and panic, as the code that caused it is
	 * likely in an inconsistent internal state.
	 *
	 * This is initially intended to be used in conjunction with
	 * __builtin_trap.
	 * ---------------------------------------------------------------------
	 */
#ifdef MONITOR_BREAKPOINT_SUPPORT	 
breakpoint_handler:
	/* Extract the ISS */
	mrs	x10, ESR_ELX
	ubfx	x10, x10, #ESR_ISS_SHIFT, #ESR_ISS_LENGTH

	/* Ensure the console is initialized */
	bl	plat_crash_console_init

	adr	x4, brk_location
	bl	asm_print_str
	mrs	x4, ESR_ELX
	bl	asm_print_hex
	bl	asm_print_newline

	adr	x4, brk_message
	bl	asm_print_str
	mov	x4, x10
	mov	x5, #28
	bl	asm_print_hex_bits
	bl	asm_print_newline

	no_ret	plat_panic_handler
#endif	
end_vector_entry sync_exception_sp_el0

vector_entry irq_sp_el0
	b	report_unhandled_interrupt
end_vector_entry irq_sp_el0

vector_entry fiq_sp_el0
	b	report_unhandled_interrupt
end_vector_entry fiq_sp_el0

vector_entry serror_sp_el0
	b	report_unhandled_interrupt
end_vector_entry serror_sp_el0

	/* ---------------------------------------------------------------------
	 * Current EL with SP_ELx: 0x200 - 0x400
	 * ---------------------------------------------------------------------
	 */
vector_entry sync_exception_sp_elx
	/* <0> */
	str	x30, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_LR]
	/* <1> */
	prepare_kernel_stack
	/* <2> */
	mrs	x30, ESR_ELX
	ubfx	x30, x30, #ESR_EC_SHIFT, #ESR_EC_LENGTH
	cmp 	x30, #EC_DABORT_CUR_EL
	b.eq	cur_el_da
	cmp 	x30, #EC_IABORT_CUR_EL
	b.eq	cur_el_ia
	b       cur_el_inv
	/* <3> */
cur_el_da:
	bl 	kernel_data_abort_handler
cur_el_ia:
	bl 	kernel_prefetch_abort_handler
cur_el_inv:
	b	report_unhandled_exception
end_vector_entry sync_exception_sp_elx

vector_entry irq_sp_elx
	/* <1> */
	prepare_kernel_stack
	/* <3> */
	bl	kernel_interrupt_handler
end_vector_entry irq_sp_elx

vector_entry fiq_sp_elx
	b	report_unhandled_interrupt
end_vector_entry fiq_sp_elx

vector_entry serror_sp_elx
	b	handle_lower_el_async_ea
end_vector_entry serror_sp_elx

	/* ---------------------------------------------------------------------
	 * Lower EL using AArch64 : 0x400 - 0x600
	 * ---------------------------------------------------------------------
	 */
vector_entry sync_exception_aarch64
	/*
	 * This exception vector will be the entry point for SMCs and traps
	 * that are unhandled at lower ELs most commonly. SP_EL3 should point
	 * to a valid cpu context where the general purpose and system register
	 * state can be saved.
	 */
	handle_sync_pending_ea	 
	handler_lower_el_sync_exception
end_vector_entry sync_exception_aarch64


vector_entry irq_aarch64
	handle_sync_pending_ea	
	handle_lower_el_interrupt_exception
end_vector_entry irq_aarch64

vector_entry fiq_aarch64
	handle_sync_pending_ea	
	handle_lower_el_interrupt_exception
end_vector_entry fiq_aarch64

vector_entry serror_aarch64
	handle_lower_el_async_exception
end_vector_entry serror_aarch64

	/* ---------------------------------------------------------------------
	 * Lower EL using AArch32 : 0x600 - 0x800
	 * ---------------------------------------------------------------------
	 */
vector_entry sync_exception_aarch32
	/*
	 * This exception vector will be the entry point for SMCs and traps
	 * that are unhandled at lower ELs most commonly. SP_EL3 should point
	 * to a valid cpu context where the general purpose and system register
	 * state can be saved.
	 */
	handle_sync_pending_ea	 
	handler_lower_el_sync_exception
end_vector_entry sync_exception_aarch32

vector_entry irq_aarch32
	handle_sync_pending_ea
	handle_lower_el_interrupt_exception
end_vector_entry irq_aarch32

vector_entry fiq_aarch32
	handle_sync_pending_ea
	handle_lower_el_interrupt_exception
end_vector_entry fiq_aarch32

vector_entry serror_aarch32
	handle_lower_el_async_exception
end_vector_entry serror_aarch32


/*
 * Delegate External Abort handling to platform's EA handler. This function
 * assumes that all GP registers have been saved by the caller.
 *
 * x0: EA reason
 * x1: EA syndrome
 */
func ea_proceed
	/*
	 * Setup rest of arguments, and call platform External Abort handler.
	 *
	 * x0: EA reason (already in place)
	 * x1: Exception syndrome (already in place).
	 * x2: Cookie (unused for now).
	 * x3: Context pointer.
	 * x4: Flags (security state from SCR for now).
	 */
	mov	x2, xzr
	mov	x3, sp /* sp_elx */
	ubfx	x4, x4, #0, #1

	mov	x29, x30
#if ENABLE_ASSERTIONS
	/* Stash the stack pointer */
	mov	x28, sp
#endif
	/* 1 */
	prepare_kernel_stack
	/* 3 */
	bl	user_ea_handler

#if ENABLE_ASSERTIONS
	/*
	 * Error handling flows might involve long jumps; so upon returning from
	 * the platform error handler, validate that the we've completely
	 * unwound the stack.
	 */
	mov	x27, sp
	cmp	x28, x27
	ASM_ASSERT(eq)
#endif

	ret	x29
endfunc ea_proceed

