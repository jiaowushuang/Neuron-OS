/*
 * Copyright (c) 2016-2022, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef COMMON_MACROS_S
#define COMMON_MACROS_S

#include <arch.h>
#include <asm_macros.S>
#include <assert_macros.S>
#include <lib/xlat_tables/xlat_tables_defs.h>


/* -----------------------------------------------------------------------------
 * This is the super set of actions that need to be performed during a cold boot
 * or a warm boot in EL3. This code is shared by BL1 and BL32 (SP_MIN).
 *
 * This macro will always perform reset handling, architectural initialisations
 * and stack setup. The rest of the actions are optional because they might not
 * be needed, depending on the context in which this macro is called. This is
 * why this macro is parameterised ; each parameter allows to enable/disable
 * some actions.
 *
 *  _init_sctlr:
 *	Whether the macro needs to initialise the SCTLRX register including
 *	configuring the endianness of data accesses.
 *
 *  _warm_boot_mailbox:
 *	Whether the macro needs to detect the type of boot (cold/warm). The
 *	detection is based on the platform entrypoint address : if it is zero
 *	then it is a cold boot, otherwise it is a warm boot. In the latter case,
 *	this macro jumps on the platform entrypoint address.
 *
 *  _secondary_cold_boot:
 *	Whether the macro needs to identify the CPU that is calling it: primary
 *	CPU or secondary CPU. The primary CPU will be allowed to carry on with
 *	the platform initialisations, while the secondaries will be put in a
 *	platform-specific state in the meantime.
 *
 *	If the caller knows this macro will only be called by the primary CPU
 *	then this parameter can be defined to 0 to skip this step.
 *
 * _init_memory:
 *	Whether the macro needs to initialise the memory.
 *
 * _init_c_runtime:
 *	Whether the macro needs to initialise the C runtime environment.
 *
 * _exception_vectors:
 *	Address of the exception vectors to program in the VBAR_EL3 register.
 *
 * _pie_fixup_size:
 *	Size of memory region to fixup Global Descriptor Table (GDT).
 *
 *	A non-zero value is expected when firmware needs GDT to be fixed-up.
 *
 * -----------------------------------------------------------------------------
 */
	.macro entrypoint_common					\
		_init_sctlr, _warm_boot_mailbox, _secondary_cold_boot,	\
		_init_memory, _init_c_runtime, _exception_vectors

	/* Supervisor/hypervisor mode, interrupts disabled */
	ldr r5, #DISABLE_ALL_EXCEPTIONS
	lsl r5, r5, SPSR_AIF_SHIFT
    	msr cpsr_fc, r5
	isb

#ifdef CONFIG_ARM_MONITOR_SUPPORT
	/* Switch to monitor mode */
	cps	#MODE32_mon
#elif CONFIG_ARM_HYPERVISOR_SUPPORT
	/* Switch to hypervisor mode */
	cps	#MODE32_hyp
#else
	/* Switch to superviser mode */
	cps	#MODE32_svc
#endif	
	isb
	
	.if \_init_sctlr
		/* -------------------------------------------------------------
		 * This is the initialisation of SCTLRX and so must ensure that
		 * all fields are explicitly set rather than relying on hw. Some
		 * fields reset to an IMPLEMENTATION DEFINED value.
		 *
		 * SCTLRX.TE: Set to zero so that exceptions to an Exception
		 *  Level executing at PL1 are taken to A32 state.
		 *
		 * SCTLRX.EE: Set the CPU endianness before doing anything that
		 *  might involve memory reads or writes. Set to zero to select
		 *  Little Endian.
		 *
		 * SCTLRX.V: Set to zero to select the normal exception vectors
		 *  with base address held in VBARX.
		 *
		 * SCTLRX.DSSBS: Set to zero to disable speculation store bypass
		 *  safe behaviour upon exception entry to EL3.
		 * -------------------------------------------------------------
		 */
		ldr     r0, =(SCTLR_RESET_VAL & ~(SCTLR_TE_BIT | SCTLR_EE_BIT | \
				SCTLR_V_BIT | SCTLR_DSSBS_BIT))
		stcopr	r0, SCTLRX
		isb
	.endif /* _init_sctlr */

	.if \_warm_boot_mailbox
		/* -------------------------------------------------------------
		 * This code will be executed for both warm and cold resets.
		 * Now is the time to distinguish between the two.
		 * Query the platform entrypoint address and if it is not zero
		 * then it means it is a warm boot so jump to this address.
		 * -------------------------------------------------------------
		 */
		bl	plat_get_my_entrypoint
		cmp	r0, #0
		bxne	r0
	.endif /* _warm_boot_mailbox */

	/* ---------------------------------------------------------------------
	 * Set the exception vectors (VBARX/MVBAR).
	 * ---------------------------------------------------------------------
	 */
	ldr	r0, =\_exception_vectors
	stcopr	r0, VBARX
	isb

	/* -----------------------------------------------------
	 * Enable the Asynchronous data abort now that the
	 * exception vectors have been setup.
	 * -----------------------------------------------------
	 */
	cpsie   a
	isb
	/* ---------------------------------------------------------------------
	 * Initialise FPEXC, setting all fields rather than relying on hw. Some
	 * fields are architecturally UNKNOWN on reset and are set to zero
	 * except for field(s) listed below.
	 *
	 * FPEXC.EN: Enable access to Advanced SIMD and floating point features
	 *  from all exception levels.
         *
         * __SOFTFP__: Predefined macro exposed by soft-float toolchain.
         *  ARMv7 and Cortex-A32(ARMv8/aarch32) has both soft-float and
         *  hard-float variants of toolchain, avoid compiling below code with
         *  soft-float toolchain as "vmsr" instruction will not be recognized.
	 * ---------------------------------------------------------------------
	 */
#if ((ARM_ARCH_MAJOR > 7) || defined(ARMV7_SUPPORTS_VFP)) && !(__SOFTFP__)
	ldr	r0, =(FPEXC_RESET_VAL | FPEXC_EN_BIT)
	vmsr	FPEXC, r0
	isb
#endif

	bl	init_cpu_data_ptr
	.if \_secondary_cold_boot
		/* -------------------------------------------------------------
		 * Check if this is a primary or secondary CPU cold boot.
		 * The primary CPU will set up the platform while the
		 * secondaries are placed in a platform-specific state until the
		 * primary CPU performs the necessary actions to bring them out
		 * of that state and allows entry into the OS.
		 * -------------------------------------------------------------
		 */
		bl	plat_is_my_cpu_primary
		cmp	r0, #0
		bne	do_primary_cold_boot

		/* This is a cold boot on a secondary CPU */
		bl	plat_secondary_cold_boot_setup
		/* plat_secondary_cold_boot_setup() is not supposed to return */
		no_ret	plat_panic_handler

	do_primary_cold_boot:
	.endif /* _secondary_cold_boot */

	/* ---------------------------------------------------------------------
	 * Initialize memory now. Secondary CPU initialization won't get to this
	 * point.
	 * ---------------------------------------------------------------------
	 */

	.if \_init_memory
		bl	platform_mem_init
	.endif /* _init_memory */

	/* ---------------------------------------------------------------------
	 * Init C runtime environment:
	 *   - Zero-initialise the NOBITS sections. There are 2 of them:
	 *       - the .bss section;
	 *       - the coherent memory section (if any).
	 *   - Relocate the data section from ROM to RAM, if required.
	 * ---------------------------------------------------------------------
	 */
	.if \_init_c_runtime
		/* -----------------------------------------------------------------
		 * Invalidate the RW memory used by the image. This
		 * includes the data and NOBITS sections. This is done to
		 * safeguard against possible corruption of this memory by
		 * dirty cache lines in a system cache as a result of use by
		 * an earlier boot loader stage. If PIE is enabled however,
		 * RO sections including the GOT may be modified during
		 * pie fixup. Therefore, to be on the safe side, invalidate
		 * the entire image region if PIE is enabled.
		 * -----------------------------------------------------------------
		 */

		ldr	r0, =__RW_START__

		ldr	r1, =__RW_END__
		sub	r1, r1, r0
		bl	inv_dcache_range

		/*
		 * zeromem uses r12 whereas it is used to save previous BL arg3,
		 * save it in r7
		 */
		mov	r7, r12
		ldr	r0, =__BSS_START__
		ldr	r1, =__BSS_END__
		sub 	r1, r1, r0
		bl	zeromem

		/* Restore r12 */
		mov	r12, r7

		/* -----------------------------------------------------
		 * Copy data from ROM to RAM.
		 * -----------------------------------------------------
		 */
		ldr	r0, =__DATA_RAM_START__
		ldr	r1, =__DATA_ROM_START__
		ldr	r2, =__DATA_RAM_END__
		sub 	r2, r2, r0
		bl	memcpy4

	.endif /* _init_c_runtime */

	/* ---------------------------------------------------------------------
	 * Allocate a stack whose memory will be marked as Normal-IS-WBWA when
	 * the MMU is enabled. There is no risk of reading stale stack memory
	 * after enabling the MMU as only the primary CPU is running at the
	 * moment.
	 * ---------------------------------------------------------------------
	 */
	bl	plat_set_my_stack

#if STACK_PROTECTOR_ENABLED
	.if \_init_c_runtime
	bl	update_stack_protector_canary
	.endif /* _init_c_runtime */
#endif
	.endm

#endif /* COMMON_MACROS_S */
