/*
 * Copyright (c) 2013-2022, Arm Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <arch.h>
#include <asm_macros.S>
#include <assert_macros.S>
#include <context.h>
#include <common_macros.S>

#if CTX_INCLUDE_EL2_REGS
	.global	el2_sysregs_context_save_common
	.global	el2_sysregs_context_restore_common
#if ENABLE_SPE_FOR_LOWER_ELS
	.global	el2_sysregs_context_save_spe
	.global	el2_sysregs_context_restore_spe
#endif /* ENABLE_SPE_FOR_LOWER_ELS */
#if CTX_INCLUDE_MTE_REGS
	.global	el2_sysregs_context_save_mte
	.global	el2_sysregs_context_restore_mte
#endif /* CTX_INCLUDE_MTE_REGS */
#if ENABLE_MPAM_FOR_LOWER_ELS
	.global	el2_sysregs_context_save_mpam
	.global	el2_sysregs_context_restore_mpam
#endif /* ENABLE_MPAM_FOR_LOWER_ELS */
#if ENABLE_FEAT_FGT
	.global	el2_sysregs_context_save_fgt
	.global	el2_sysregs_context_restore_fgt
#endif /* ENABLE_FEAT_FGT */
#if ENABLE_FEAT_ECV
	.global	el2_sysregs_context_save_ecv
	.global	el2_sysregs_context_restore_ecv
#endif /* ENABLE_FEAT_ECV */
#if ENABLE_FEAT_VHE
	.global	el2_sysregs_context_save_vhe
	.global	el2_sysregs_context_restore_vhe
#endif /* ENABLE_FEAT_VHE */
#if RAS_EXTENSION
	.global	el2_sysregs_context_save_ras
	.global	el2_sysregs_context_restore_ras
#endif /* RAS_EXTENSION */
#if CTX_INCLUDE_NEVE_REGS
	.global	el2_sysregs_context_save_nv2
	.global	el2_sysregs_context_restore_nv2
#endif /* CTX_INCLUDE_NEVE_REGS */
#if ENABLE_TRF_FOR_NS
	.global	el2_sysregs_context_save_trf
	.global	el2_sysregs_context_restore_trf
#endif /* ENABLE_TRF_FOR_NS */
#if ENABLE_FEAT_CSV2_2
	.global	el2_sysregs_context_save_csv2
	.global	el2_sysregs_context_restore_csv2
#endif /* ENABLE_FEAT_CSV2_2 */
#if ENABLE_FEAT_HCX
	.global	el2_sysregs_context_save_hcx
	.global	el2_sysregs_context_restore_hcx
#endif /* ENABLE_FEAT_HCX */
#endif /* CTX_INCLUDE_EL2_REGS */

#if CTX_INCLUDE_EL1_REGS
	.global	el1_sysregs_context_save
	.global	el1_sysregs_context_restore
#endif

#if CTX_INCLUDE_FPREGS
	.global	fpregs_context_save
	.global	fpregs_context_restore
#endif /* CTX_INCLUDE_FPREGS */

	.global	enter_kernel_entry
	.global save_gp_regs
	.global	restore_gp_regs
	.global	exit_kernel_entry


	.global	kernel_stacks
	.globl	update_stack_protector_canary
	
	/* -----------------------------------------------------
	 * Per-CPU stacks in normal memory. Each CPU gets a
	 * stack of PLATFORM_STACK_SIZE bytes.
	 * -----------------------------------------------------
	 */
declare_stack kernel_stacks, normal_stacks, \
		PLATFORM_STACK_SIZE, PLATFORM_CORE_COUNT, \
		CACHE_WRITEBACK_GRANULE

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
	/* Use x19 as it is callee-saved */
	mov	x19, x30
	bl	plat_get_stack_protector_canary

	/* Update the canary with the returned value */
	adrp	x1,  __stack_chk_guard
	str	x0, [x1, #:lo12:__stack_chk_guard]
	ret	x19
endfunc update_stack_protector_canary

#if CTX_INCLUDE_EL2_REGS

/* -----------------------------------------------------
 * The following functions strictly follow the AArch64
 * PCS to use x9-x16 (temporary caller-saved registers)
 * to save/restore EL2 system register context.
 * el2_sysregs_context_save/restore_common functions
 * save and restore registers that are common to all
 * configurations. The rest of the functions save and
 * restore EL2 system registers that are present when a
 * particular feature is enabled. All functions assume
 * that 'x0' is pointing to a 'el2_sys_regs' structure
 * where the register context will be saved/restored.
 *
 * The following registers are not added.
 * AMEVCNTVOFF0<n>_EL2
 * AMEVCNTVOFF1<n>_EL2
 * ICH_AP0R<n>_EL2
 * ICH_AP1R<n>_EL2
 * ICH_LR<n>_EL2
 * -----------------------------------------------------
 */
func el2_sysregs_context_save_common
	mrs	x9, actlr_el2
	mrs	x10, afsr0_el2
	stp	x9, x10, [x0, #CTX_ACTLR_EL2]

	mrs	x11, afsr1_el2
	mrs	x12, amair_el2
	stp	x11, x12, [x0, #CTX_AFSR1_EL2]

	mrs	x13, cnthctl_el2
	mrs	x14, cntvoff_el2
	stp	x13, x14, [x0, #CTX_CNTHCTL_EL2]

	mrs	x15, cptr_el2
	str	x15, [x0, #CTX_CPTR_EL2]

#if CTX_INCLUDE_AARCH32_REGS
	mrs	x16, dbgvcr32_el2
	str	x16, [x0, #CTX_DBGVCR32_EL2]
#endif /* CTX_INCLUDE_AARCH32_REGS */

	mrs	x9, elr_el2
	mrs	x10, esr_el2
	stp	x9, x10, [x0, #CTX_ELR_EL2]

	mrs	x11, far_el2
	mrs	x12, hacr_el2
	stp	x11, x12, [x0, #CTX_FAR_EL2]

	mrs	x13, hcr_el2
	mrs	x14, hpfar_el2
	stp	x13, x14, [x0, #CTX_HCR_EL2]

	mrs	x15, hstr_el2
	mrs	x16, ICC_SRE_EL2
	stp	x15, x16, [x0, #CTX_HSTR_EL2]

	mrs	x9, ICH_HCR_EL2
	mrs	x10, ICH_VMCR_EL2
	stp	x9, x10, [x0, #CTX_ICH_HCR_EL2]

	mrs	x11, mair_el2
	mrs	x12, mdcr_el2
	stp	x11, x12, [x0, #CTX_MAIR_EL2]

	mrs	x14, sctlr_el2
	str	x14, [x0, #CTX_SCTLR_EL2]

	mrs	x15, spsr_el2
	mrs	x16, sp_el2
	stp	x15, x16, [x0, #CTX_SPSR_EL2]

	mrs	x9, tcr_el2
	mrs	x10, tpidr_el2
	stp	x9, x10, [x0, #CTX_TCR_EL2]

	mrs	x11, ttbr0_el2
	mrs	x12, vbar_el2
	stp	x11, x12, [x0, #CTX_TTBR0_EL2]

	mrs	x13, vmpidr_el2
	mrs	x14, vpidr_el2
	stp	x13, x14, [x0, #CTX_VMPIDR_EL2]

	mrs	x15, vtcr_el2
	mrs	x16, vttbr_el2
	stp	x15, x16, [x0, #CTX_VTCR_EL2]
	ret
endfunc el2_sysregs_context_save_common

func el2_sysregs_context_restore_common
	ldp	x9, x10, [x0, #CTX_ACTLR_EL2]
	msr	actlr_el2, x9
	msr	afsr0_el2, x10

	ldp	x11, x12, [x0, #CTX_AFSR1_EL2]
	msr	afsr1_el2, x11
	msr	amair_el2, x12

	ldp	x13, x14, [x0, #CTX_CNTHCTL_EL2]
	msr	cnthctl_el2, x13
	msr	cntvoff_el2, x14

	ldr	x15, [x0, #CTX_CPTR_EL2]
	msr	cptr_el2, x15

#if CTX_INCLUDE_AARCH32_REGS
	ldr	x16, [x0, #CTX_DBGVCR32_EL2]
	msr	dbgvcr32_el2, x16
#endif /* CTX_INCLUDE_AARCH32_REGS */

	ldp	x9, x10, [x0, #CTX_ELR_EL2]
	msr	elr_el2, x9
	msr	esr_el2, x10

	ldp	x11, x12, [x0, #CTX_FAR_EL2]
	msr	far_el2, x11
	msr	hacr_el2, x12

	ldp	x13, x14, [x0, #CTX_HCR_EL2]
	msr	hcr_el2, x13
	msr	hpfar_el2, x14

	ldp	x15, x16, [x0, #CTX_HSTR_EL2]
	msr	hstr_el2, x15
	msr	ICC_SRE_EL2, x16

	ldp	x9, x10, [x0, #CTX_ICH_HCR_EL2]
	msr	ICH_HCR_EL2, x9
	msr	ICH_VMCR_EL2, x10

	ldp	x11, x12, [x0, #CTX_MAIR_EL2]
	msr	mair_el2, x11
	msr	mdcr_el2, x12

	ldr	x14, [x0, #CTX_SCTLR_EL2]
	msr	sctlr_el2, x14

	ldp	x15, x16, [x0, #CTX_SPSR_EL2]
	msr	spsr_el2, x15
	msr	sp_el2, x16

	ldp	x9, x10, [x0, #CTX_TCR_EL2]
	msr	tcr_el2, x9
	msr	tpidr_el2, x10

	ldp	x11, x12, [x0, #CTX_TTBR0_EL2]
	msr	ttbr0_el2, x11
	msr	vbar_el2, x12

	ldp	x13, x14, [x0, #CTX_VMPIDR_EL2]
	msr	vmpidr_el2, x13
	msr	vpidr_el2, x14

	ldp	x15, x16, [x0, #CTX_VTCR_EL2]
	msr	vtcr_el2, x15
	msr	vttbr_el2, x16
	ret
endfunc el2_sysregs_context_restore_common

#if ENABLE_SPE_FOR_LOWER_ELS
func el2_sysregs_context_save_spe
	mrs	x13, PMSCR_EL2
	str	x13, [x0, #CTX_PMSCR_EL2]
	ret
endfunc el2_sysregs_context_save_spe

func el2_sysregs_context_restore_spe
	ldr	x13, [x0, #CTX_PMSCR_EL2]
	msr	PMSCR_EL2, x13
	ret
endfunc el2_sysregs_context_restore_spe
#endif /* ENABLE_SPE_FOR_LOWER_ELS */

#if CTX_INCLUDE_MTE_REGS
func el2_sysregs_context_save_mte
	mrs	x9, TFSR_EL2
	str	x9, [x0, #CTX_TFSR_EL2]
	ret
endfunc el2_sysregs_context_save_mte

func el2_sysregs_context_restore_mte
	ldr	x9, [x0, #CTX_TFSR_EL2]
	msr	TFSR_EL2, x9
	ret
endfunc el2_sysregs_context_restore_mte
#endif /* CTX_INCLUDE_MTE_REGS */

#if ENABLE_MPAM_FOR_LOWER_ELS
func el2_sysregs_context_save_mpam
	mrs	x10, MPAM2_EL2
	str	x10, [x0, #CTX_MPAM2_EL2]

	mrs	x11, MPAMHCR_EL2
	mrs	x12, MPAMVPM0_EL2
	stp	x11, x12, [x0, #CTX_MPAMHCR_EL2]

	mrs	x13, MPAMVPM1_EL2
	mrs	x14, MPAMVPM2_EL2
	stp	x13, x14, [x0, #CTX_MPAMVPM1_EL2]

	mrs	x15, MPAMVPM3_EL2
	mrs	x16, MPAMVPM4_EL2
	stp	x15, x16, [x0, #CTX_MPAMVPM3_EL2]

	mrs	x9, MPAMVPM5_EL2
	mrs	x10, MPAMVPM6_EL2
	stp	x9, x10, [x0, #CTX_MPAMVPM5_EL2]

	mrs	x11, MPAMVPM7_EL2
	mrs	x12, MPAMVPMV_EL2
	stp	x11, x12, [x0, #CTX_MPAMVPM7_EL2]
	ret
endfunc func el2_sysregs_context_save_mpam

func el2_sysregs_context_restore_mpam
	ldr	x10, [x0, #CTX_MPAM2_EL2]
	msr	MPAM2_EL2, x10

	ldp	x11, x12, [x0, #CTX_MPAMHCR_EL2]
	msr	MPAMHCR_EL2, x11
	msr	MPAMVPM0_EL2, x12

	ldp	x13, x14, [x0, #CTX_MPAMVPM1_EL2]
	msr	MPAMVPM1_EL2, x13
	msr	MPAMVPM2_EL2, x14

	ldp	x15, x16, [x0, #CTX_MPAMVPM3_EL2]
	msr	MPAMVPM3_EL2, x15
	msr	MPAMVPM4_EL2, x16

	ldp	x9, x10, [x0, #CTX_MPAMVPM5_EL2]
	msr	MPAMVPM5_EL2, x9
	msr	MPAMVPM6_EL2, x10

	ldp	x11, x12, [x0, #CTX_MPAMVPM7_EL2]
	msr	MPAMVPM7_EL2, x11
	msr	MPAMVPMV_EL2, x12
	ret
endfunc el2_sysregs_context_restore_mpam
#endif /* ENABLE_MPAM_FOR_LOWER_ELS */

#if ENABLE_FEAT_FGT
func el2_sysregs_context_save_fgt
	mrs	x13, HDFGRTR_EL2
#if ENABLE_FEAT_AMUv1
	mrs	x14, HAFGRTR_EL2
	stp	x13, x14, [x0, #CTX_HDFGRTR_EL2]
#else
	str	x13, [x0, #CTX_HDFGRTR_EL2]
#endif /* ENABLE_FEAT_AMUv1 */
	mrs	x15, HDFGWTR_EL2
	mrs	x16, HFGITR_EL2
	stp	x15, x16, [x0, #CTX_HDFGWTR_EL2]

	mrs	x9, HFGRTR_EL2
	mrs	x10, HFGWTR_EL2
	stp	x9, x10, [x0, #CTX_HFGRTR_EL2]
	ret
endfunc el2_sysregs_context_save_fgt

func el2_sysregs_context_restore_fgt
	#if ENABLE_FEAT_AMUv1
	ldp	x13, x14, [x0, #CTX_HDFGRTR_EL2]
	msr	HAFGRTR_EL2, x14
#else
	ldr	x13, [x0, #CTX_HDFGRTR_EL2]
#endif /* ENABLE_FEAT_AMUv1 */
	msr	HDFGRTR_EL2, x13

	ldp	x15, x16, [x0, #CTX_HDFGWTR_EL2]
	msr	HDFGWTR_EL2, x15
	msr	HFGITR_EL2, x16

	ldp	x9, x10, [x0, #CTX_HFGRTR_EL2]
	msr	HFGRTR_EL2, x9
	msr	HFGWTR_EL2, x10
	ret
endfunc el2_sysregs_context_restore_fgt
#endif /* ENABLE_FEAT_FGT */

#if ENABLE_FEAT_ECV
func el2_sysregs_context_save_ecv
	mrs	x11, CNTPOFF_EL2
	str	x11, [x0, #CTX_CNTPOFF_EL2]
	ret
endfunc el2_sysregs_context_save_ecv

func el2_sysregs_context_restore_ecv
	ldr	x11, [x0, #CTX_CNTPOFF_EL2]
	msr	CNTPOFF_EL2, x11
	ret
endfunc el2_sysregs_context_restore_ecv
#endif /* ENABLE_FEAT_ECV */

#if ENABLE_FEAT_VHE
func el2_sysregs_context_save_vhe
	/*
	 * CONTEXTIDR_EL2 register is saved only when FEAT_VHE or
	 * FEAT_Debugv8p2 (currently not in TF-A) is supported.
	 */
	mrs	x9, contextidr_el2
	mrs	x10, ttbr1_el2
	stp	x9, x10, [x0, #CTX_CONTEXTIDR_EL2]
	ret
endfunc el2_sysregs_context_save_vhe

func el2_sysregs_context_restore_vhe
	/*
	 * CONTEXTIDR_EL2 register is restored only when FEAT_VHE or
	 * FEAT_Debugv8p2 (currently not in TF-A) is supported.
	 */
	ldp	x9, x10, [x0, #CTX_CONTEXTIDR_EL2]
	msr	contextidr_el2, x9
	msr	ttbr1_el2, x10
	ret
endfunc el2_sysregs_context_restore_vhe
#endif /* ENABLE_FEAT_VHE */

#if RAS_EXTENSION
func el2_sysregs_context_save_ras
	/*
	 * VDISR_EL2 and VSESR_EL2 registers are saved only when
	 * FEAT_RAS is supported.
	 */
	mrs	x11, vdisr_el2
	mrs	x12, vsesr_el2
	stp	x11, x12, [x0, #CTX_VDISR_EL2]
	ret
endfunc el2_sysregs_context_save_ras

func el2_sysregs_context_restore_ras
	/*
	 * VDISR_EL2 and VSESR_EL2 registers are restored only when FEAT_RAS
	 * is supported.
	 */
	ldp	x11, x12, [x0, #CTX_VDISR_EL2]
	msr	vdisr_el2, x11
	msr	vsesr_el2, x12
	ret
endfunc el2_sysregs_context_restore_ras
#endif /* RAS_EXTENSION */

#if CTX_INCLUDE_NEVE_REGS
func el2_sysregs_context_save_nv2
	/*
	 * VNCR_EL2 register is saved only when FEAT_NV2 is supported.
	 */
	mrs	x16, vncr_el2
	str	x16, [x0, #CTX_VNCR_EL2]
	ret
endfunc el2_sysregs_context_save_nv2

func el2_sysregs_context_restore_nv2
	/*
	 * VNCR_EL2 register is restored only when FEAT_NV2 is supported.
	 */
	ldr	x16, [x0, #CTX_VNCR_EL2]
	msr	vncr_el2, x16
	ret
endfunc el2_sysregs_context_restore_nv2
#endif /* CTX_INCLUDE_NEVE_REGS */

#if ENABLE_TRF_FOR_NS
func el2_sysregs_context_save_trf
	/*
	 * TRFCR_EL2 register is saved only when FEAT_TRF is supported.
	 */
	mrs	x12, TRFCR_EL2
	str	x12, [x0, #CTX_TRFCR_EL2]
	ret
endfunc el2_sysregs_context_save_trf

func el2_sysregs_context_restore_trf
	/*
	 * TRFCR_EL2 register is restored only when FEAT_TRF is supported.
	 */
	ldr	x12, [x0, #CTX_TRFCR_EL2]
	msr	TRFCR_EL2, x12
	ret
endfunc el2_sysregs_context_restore_trf
#endif /* ENABLE_TRF_FOR_NS */

#if ENABLE_FEAT_CSV2_2
func el2_sysregs_context_save_csv2
	/*
	 * SCXTNUM_EL2 register is saved only when FEAT_CSV2_2 is supported.
	 */
	mrs	x13, scxtnum_el2
	str	x13, [x0, #CTX_SCXTNUM_EL2]
	ret
endfunc el2_sysregs_context_save_csv2

func el2_sysregs_context_restore_csv2
	/*
	 * SCXTNUM_EL2 register is restored only when FEAT_CSV2_2 is supported.
	 */
	ldr	x13, [x0, #CTX_SCXTNUM_EL2]
	msr	scxtnum_el2, x13
	ret
endfunc el2_sysregs_context_restore_csv2
#endif /* ENABLE_FEAT_CSV2_2 */

#if ENABLE_FEAT_HCX
func el2_sysregs_context_save_hcx
	mrs	x14, hcrx_el2
	str	x14, [x0, #CTX_HCRX_EL2]
	ret
endfunc el2_sysregs_context_save_hcx

func el2_sysregs_context_restore_hcx
	ldr	x14, [x0, #CTX_HCRX_EL2]
	msr	hcrx_el2, x14
	ret
endfunc el2_sysregs_context_restore_hcx
#endif /* ENABLE_FEAT_HCX */
#endif /* CTX_INCLUDE_EL2_REGS */

#if CTX_INCLUDE_EL1_REGS
/* ------------------------------------------------------------------
 * The following function strictly follows the AArch64 PCS to use
 * x9-x17 (temporary caller-saved registers) to save EL1 system
 * register context. It assumes that 'x0' is pointing to a
 * 'el1_sys_regs' structure where the register context will be saved.
 * ------------------------------------------------------------------
 */
func el1_sysregs_context_save

	mrs	x9, spsr_el1
	mrs	x10, elr_el1
	stp	x9, x10, [x0, #CTX_SPSR_EL1]

#if !ERRATA_SPECULATIVE_AT
	mrs	x15, sctlr_el1
	mrs	x16, tcr_el1
	stp	x15, x16, [x0, #CTX_SCTLR_EL1]
#endif /* ERRATA_SPECULATIVE_AT */

	mrs	x17, cpacr_el1
	mrs	x9, csselr_el1
	stp	x17, x9, [x0, #CTX_CPACR_EL1]

	mrs	x10, sp_el1
	mrs	x11, esr_el1
	stp	x10, x11, [x0, #CTX_SP_EL1]

	mrs	x12, ttbr0_el1
	mrs	x13, ttbr1_el1
	stp	x12, x13, [x0, #CTX_TTBR0_EL1]

	mrs	x14, mair_el1
	mrs	x15, amair_el1
	stp	x14, x15, [x0, #CTX_MAIR_EL1]

	mrs	x16, actlr_el1
	mrs	x17, tpidr_el1
	stp	x16, x17, [x0, #CTX_ACTLR_EL1]

	mrs	x9, tpidr_el0
	mrs	x10, tpidrro_el0
	stp	x9, x10, [x0, #CTX_TPIDR_EL0]

	mrs	x13, par_el1
	mrs	x14, far_el1
	stp	x13, x14, [x0, #CTX_PAR_EL1]

	mrs	x15, afsr0_el1
	mrs	x16, afsr1_el1
	stp	x15, x16, [x0, #CTX_AFSR0_EL1]

	mrs	x17, contextidr_el1
	mrs	x9, vbar_el1
	stp	x17, x9, [x0, #CTX_CONTEXTIDR_EL1]

	/* Save AArch32 system registers if the build has instructed so */
#if CTX_INCLUDE_AARCH32_REGS
	mrs	x11, spsr_abt
	mrs	x12, spsr_und
	stp	x11, x12, [x0, #CTX_SPSR_ABT]

	mrs	x13, spsr_irq
	mrs	x14, spsr_fiq
	stp	x13, x14, [x0, #CTX_SPSR_IRQ]

	mrs	x15, dacr32_el2
	mrs	x16, ifsr32_el2
	stp	x15, x16, [x0, #CTX_DACR32_EL2]
#endif /* CTX_INCLUDE_AARCH32_REGS */

	/* Save NS timer registers if the build has instructed so */
#if NS_TIMER_SWITCH
	mrs	x10, cntp_ctl_el0
	mrs	x11, cntp_cval_el0
	stp	x10, x11, [x0, #CTX_CNTP_CTL_EL0]

	mrs	x12, cntv_ctl_el0
	mrs	x13, cntv_cval_el0
	stp	x12, x13, [x0, #CTX_CNTV_CTL_EL0]

	mrs	x14, cntkctl_el1
	str	x14, [x0, #CTX_CNTKCTL_EL1]
#endif /* NS_TIMER_SWITCH */

	/* Save MTE system registers if the build has instructed so */
#if CTX_INCLUDE_MTE_REGS
	mrs	x15, TFSRE0_EL1
	mrs	x16, TFSR_EL1
	stp	x15, x16, [x0, #CTX_TFSRE0_EL1]

	mrs	x9, RGSR_EL1
	mrs	x10, GCR_EL1
	stp	x9, x10, [x0, #CTX_RGSR_EL1]
#endif /* CTX_INCLUDE_MTE_REGS */

	ret
endfunc el1_sysregs_context_save

/* ------------------------------------------------------------------
 * The following function strictly follows the AArch64 PCS to use
 * x9-x17 (temporary caller-saved registers) to restore EL1 system
 * register context.  It assumes that 'x0' is pointing to a
 * 'el1_sys_regs' structure from where the register context will be
 * restored
 * ------------------------------------------------------------------
 */
func el1_sysregs_context_restore

	ldp	x9, x10, [x0, #CTX_SPSR_EL1]
	msr	spsr_el1, x9
	msr	elr_el1, x10

#if !ERRATA_SPECULATIVE_AT
	ldp	x15, x16, [x0, #CTX_SCTLR_EL1]
	msr	sctlr_el1, x15
	msr	tcr_el1, x16
#endif /* ERRATA_SPECULATIVE_AT */

	ldp	x17, x9, [x0, #CTX_CPACR_EL1]
	msr	cpacr_el1, x17
	msr	csselr_el1, x9

	ldp	x10, x11, [x0, #CTX_SP_EL1]
	msr	sp_el1, x10
	msr	esr_el1, x11

	ldp	x12, x13, [x0, #CTX_TTBR0_EL1]
	msr	ttbr0_el1, x12
	msr	ttbr1_el1, x13

	ldp	x14, x15, [x0, #CTX_MAIR_EL1]
	msr	mair_el1, x14
	msr	amair_el1, x15

	ldp 	x16, x17, [x0, #CTX_ACTLR_EL1]
	msr	actlr_el1, x16
	msr	tpidr_el1, x17

	ldp	x9, x10, [x0, #CTX_TPIDR_EL0]
	msr	tpidr_el0, x9
	msr	tpidrro_el0, x10

	ldp	x13, x14, [x0, #CTX_PAR_EL1]
	msr	par_el1, x13
	msr	far_el1, x14

	ldp	x15, x16, [x0, #CTX_AFSR0_EL1]
	msr	afsr0_el1, x15
	msr	afsr1_el1, x16

	ldp	x17, x9, [x0, #CTX_CONTEXTIDR_EL1]
	msr	contextidr_el1, x17
	msr	vbar_el1, x9

	/* Restore AArch32 system registers if the build has instructed so */
#if CTX_INCLUDE_AARCH32_REGS
	ldp	x11, x12, [x0, #CTX_SPSR_ABT]
	msr	spsr_abt, x11
	msr	spsr_und, x12

	ldp	x13, x14, [x0, #CTX_SPSR_IRQ]
	msr	spsr_irq, x13
	msr	spsr_fiq, x14

	ldp	x15, x16, [x0, #CTX_DACR32_EL2]
	msr	dacr32_el2, x15
	msr	ifsr32_el2, x16
#endif /* CTX_INCLUDE_AARCH32_REGS */

	/* Restore NS timer registers if the build has instructed so */
#if NS_TIMER_SWITCH
	ldp	x10, x11, [x0, #CTX_CNTP_CTL_EL0]
	msr	cntp_ctl_el0, x10
	msr	cntp_cval_el0, x11

	ldp	x12, x13, [x0, #CTX_CNTV_CTL_EL0]
	msr	cntv_ctl_el0, x12
	msr	cntv_cval_el0, x13

	ldr	x14, [x0, #CTX_CNTKCTL_EL1]
	msr	cntkctl_el1, x14
#endif /* NS_TIMER_SWITCH */

	/* Restore MTE system registers if the build has instructed so */
#if CTX_INCLUDE_MTE_REGS
	ldp	x11, x12, [x0, #CTX_TFSRE0_EL1]
	msr	TFSRE0_EL1, x11
	msr	TFSR_EL1, x12

	ldp	x13, x14, [x0, #CTX_RGSR_EL1]
	msr	RGSR_EL1, x13
	msr	GCR_EL1, x14
#endif /* CTX_INCLUDE_MTE_REGS */

	/* No explict ISB required here as ERET covers it */
	ret
endfunc el1_sysregs_context_restore
#endif

/* ------------------------------------------------------------------
 * The following function follows the aapcs_64 strictly to use
 * x9-x17 (temporary caller-saved registers according to AArch64 PCS)
 * to save floating point register context. It assumes that 'x0' is
 * pointing to a 'fp_regs' structure where the register context will
 * be saved.
 *
 * Access to VFP registers will trap if CPTR_EL3.TFP is set.
 * However currently we don't use VFP registers nor set traps in
 * Trusted Firmware, and assume it's cleared.
 *
 * TODO: Revisit when VFP is used in secure world
 * ------------------------------------------------------------------
 */

#if CTX_INCLUDE_FPREGS
func fpregs_context_save
	stp	q0, q1, [x0, #CTX_FP_Q0]
	stp	q2, q3, [x0, #CTX_FP_Q2]
	stp	q4, q5, [x0, #CTX_FP_Q4]
	stp	q6, q7, [x0, #CTX_FP_Q6]
	stp	q8, q9, [x0, #CTX_FP_Q8]
	stp	q10, q11, [x0, #CTX_FP_Q10]
	stp	q12, q13, [x0, #CTX_FP_Q12]
	stp	q14, q15, [x0, #CTX_FP_Q14]
	stp	q16, q17, [x0, #CTX_FP_Q16]
	stp	q18, q19, [x0, #CTX_FP_Q18]
	stp	q20, q21, [x0, #CTX_FP_Q20]
	stp	q22, q23, [x0, #CTX_FP_Q22]
	stp	q24, q25, [x0, #CTX_FP_Q24]
	stp	q26, q27, [x0, #CTX_FP_Q26]
	stp	q28, q29, [x0, #CTX_FP_Q28]
	stp	q30, q31, [x0, #CTX_FP_Q30]

	mrs	x9, fpsr
	str	x9, [x0, #CTX_FP_FPSR]

	mrs	x10, fpcr
	str	x10, [x0, #CTX_FP_FPCR]

#if CTX_INCLUDE_AARCH32_REGS
	mrs	x11, fpexc32_el2
	str	x11, [x0, #CTX_FP_FPEXC32_EL2]
#endif /* CTX_INCLUDE_AARCH32_REGS */
	ret
endfunc fpregs_context_save

/* ------------------------------------------------------------------
 * The following function follows the aapcs_64 strictly to use x9-x17
 * (temporary caller-saved registers according to AArch64 PCS) to
 * restore floating point register context. It assumes that 'x0' is
 * pointing to a 'fp_regs' structure from where the register context
 * will be restored.
 *
 * Access to VFP registers will trap if CPTR_EL3.TFP is set.
 * However currently we don't use VFP registers nor set traps in
 * Trusted Firmware, and assume it's cleared.
 *
 * TODO: Revisit when VFP is used in secure world
 * ------------------------------------------------------------------
 */
func fpregs_context_restore
	ldp	q0, q1, [x0, #CTX_FP_Q0]
	ldp	q2, q3, [x0, #CTX_FP_Q2]
	ldp	q4, q5, [x0, #CTX_FP_Q4]
	ldp	q6, q7, [x0, #CTX_FP_Q6]
	ldp	q8, q9, [x0, #CTX_FP_Q8]
	ldp	q10, q11, [x0, #CTX_FP_Q10]
	ldp	q12, q13, [x0, #CTX_FP_Q12]
	ldp	q14, q15, [x0, #CTX_FP_Q14]
	ldp	q16, q17, [x0, #CTX_FP_Q16]
	ldp	q18, q19, [x0, #CTX_FP_Q18]
	ldp	q20, q21, [x0, #CTX_FP_Q20]
	ldp	q22, q23, [x0, #CTX_FP_Q22]
	ldp	q24, q25, [x0, #CTX_FP_Q24]
	ldp	q26, q27, [x0, #CTX_FP_Q26]
	ldp	q28, q29, [x0, #CTX_FP_Q28]
	ldp	q30, q31, [x0, #CTX_FP_Q30]

	ldr	x9, [x0, #CTX_FP_FPSR]
	msr	fpsr, x9

	ldr	x10, [x0, #CTX_FP_FPCR]
	msr	fpcr, x10

#if CTX_INCLUDE_AARCH32_REGS
	ldr	x11, [x0, #CTX_FP_FPEXC32_EL2]
	msr	fpexc32_el2, x11
#endif /* CTX_INCLUDE_AARCH32_REGS */

	/*
	 * No explict ISB required here as ERET to
	 * switch to secure EL1 or non-secure world
	 * covers it
	 */

	ret
endfunc fpregs_context_restore
#endif /* CTX_INCLUDE_FPREGS */


/* ------------------------------------------------------------------
 * The following macro is used to save and restore all the general
 * purpose and ARMv8.3-PAuth (if enabled) registers.
 * It also checks if the Secure Cycle Counter (PMCCNTR_EL0)
 * is disabled in EL3/Secure (ARMv8.5-PMU), wherein PMCCNTR_EL0
 * needs not to be saved/restored during world switch.
 *
 * Ideally we would only save and restore the callee saved registers
 * when a world switch occurs but that type of implementation is more
 * complex. So currently we will always save and restore these
 * registers on entry and exit of EL3.
 * clobbers: x18
 * ------------------------------------------------------------------
 */
func save_gp_regs
	stp	x0, x1, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X0]
	stp	x2, x3, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X2]
	stp	x4, x5, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X4]
	stp	x6, x7, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X6]
	stp	x8, x9, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X8]
	stp	x10, x11, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X10]
	stp	x12, x13, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X12]
	stp	x14, x15, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X14]
	stp	x16, x17, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X16]
	stp	x18, x19, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X18]
	stp	x20, x21, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X20]
	stp	x22, x23, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X22]
	stp	x24, x25, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X24]
	stp	x26, x27, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X26]
	stp	x28, x29, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X28]
	str	x30, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_LR]
	mrs	x18, sp_el0
	str	x18, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_SP_EL0]
endfunc save_gp_regs /* save_gp_regs */

/* -----------------------------------------------------------------
 * This function saves the context and sets the PSTATE to a known
 * state, preparing entry to el3.
 * Save all the general purpose and ARMv8.3-PAuth (if enabled)
 * registers.
 * Then set any of the PSTATE bits that are not set by hardware
 * according to the Aarch64.TakeException pseudocode in the Arm
 * Architecture Reference Manual to a default value for EL3.
 * clobbers: x17
 * -----------------------------------------------------------------
 */
func enter_kernel_entry
	/* see SP_ELX NOTE. */
	/* How to call 'cm_set_next_world_context', but this is the 'cpu_context' of physics
	 * So, you need to it that 'cpu_context' of logical 
	 */
	/* mrs x0, TPIDRX 
	 * ldr x0, [x0, #CPU_PROCESS_OFFSET]
	 * msr spsel, #MODE_SP_ELX
	 * mov sp, x0
	 */
	
	bl save_gp_regs
	
	mrs     x22, ELR_ELX
    	mrs     x23, SPSR_ELX
   	str	x22, x23, [sp, #CTX_GPREGS_OFFSET + CTX_ELR_ELX]
	ret
endfunc enter_kernel_entry

/* ------------------------------------------------------------------
 * This function restores ARMv8.3-PAuth (if enabled) and all general
 * purpose registers except x30 from the CPU context.
 * x30 register must be explicitly restored by the caller.
 * ------------------------------------------------------------------
 */
func restore_gp_regs
	ldp	x0, x1, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X0]
	ldp	x2, x3, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X2]
	ldp	x4, x5, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X4]
	ldp	x6, x7, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X6]
	ldp	x8, x9, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X8]
	ldp	x10, x11, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X10]
	ldp	x12, x13, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X12]
	ldp	x14, x15, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X14]
	ldp	x16, x17, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X16]
	ldp	x18, x19, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X18]
	ldp	x20, x21, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X20]
	ldp	x22, x23, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X22]
	ldp	x24, x25, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X24]
	ldp	x26, x27, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X26]
	ldr	x28, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_SP_EL0]
	msr	sp_el0, x28
	ldp	x28, x29, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_X28]
	ldr	x30, [sp, #CTX_GPREGS_OFFSET + CTX_GPREG_LR]
	ret
endfunc restore_gp_regs

/* ------------------------------------------------------------------
 * This routine assumes that the SP_EL3 is pointing to a valid
 * context structure from where the gp regs and other special
 * registers can be retrieved.
 * ------------------------------------------------------------------
 */
func exit_kernel_entry
	/* ----------------------------------------------------------
	 * Save the current SP_EL0 i.e. the EL3 runtime stack which
	 * will be used for handling the next CALL.
	 * Then switch to SP_EL3.
	 * ----------------------------------------------------------
	 */
	/* Before it, must call 'schedule' to update the 'CPU_PROCESS_OFFSET' */
	//mrs x0, TPIDRX
	//ldr x0, [x0, #CPU_PROCESS_OFFSET]
	prepare_user_stack
	/* ----------------------------------------------------------
	 * Restore SPSR_EL3, ELR_EL3 and SCR_EL3 prior to ERET
	 * ----------------------------------------------------------
	 */

	ldp	x16, x17, [sp, #CTX_GPREGS_OFFSET + CTX_ELR_ELX]
	msr	ELR_ELX, x16
	msr	SPSR_ELX, x17
	
	/* ----------------------------------------------------------
	 * Restore general purpose (including x30), PMCR_EL0 and
	 * ARMv8.3-PAuth registers.
	 * Exit EL3 via ERET to a lower exception level.
 	 * ----------------------------------------------------------
 	 */
	bl	restore_gp_regs
	
	exception_return
endfunc exit_kernel_entry
