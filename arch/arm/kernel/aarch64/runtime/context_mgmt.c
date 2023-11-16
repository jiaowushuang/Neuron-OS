/*
 * Copyright (c) 2015-2021, Arm Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <assert.h>

#include <arch_helpers.h>
#include <context.h>
#include <debug.h>
#include <runtime/context_mgmt.h>
#include <cpu_data.h>
#include <interrupt_mgmt.h>
#include <context.h>
#include <drivers/gic/gicv3.h>

/*******************************************************************************
 * Context management library initialization routine. This library is used by
 * runtime services to share pointers to 'world_process' structures for secure
 * non-secure and realm states. Management of the structures and their associated
 * memory is not done by the context management library e.g. the PSCI service
 * manages the cpu context used for entry from and exit to the non-secure state.
 * The Secure payload dispatcher service manages the context(s) corresponding to
 * the secure state. It also uses this library to get access to the non-secure
 * state cpu context pointers.
 * Lastly, this library provides the API to make SP_EL3 point to the cpu context
 * which will be used for programming an entry into a lower EL. The same context
 * will be used to save state upon exception entry from that EL.
 ******************************************************************************/
void __init cm_init(void)
{
	/*
	 * The context management library has only global data to intialize, but
	 * that will be done when the BSS is zeroed out.
	 */

}

uintptr_t cm_get_curr_stack(void)
{
	return get_cpu_data(cpu_stack);
}

uintptr_t cm_get_curr_process(void)
{
	return get_cpu_data(cpu_process);
}


/* Context management library setup routine */
void cpu_arch_setup(void)
{
	/*
	 * Following array will be used for context management.
	 * There are 2 instances, for the Secure and Non-Secure contexts.
	 */
	cpu_data_ops_t cpu_ops;
	world_data_t *world_data_ptr;
	pcpu_context_t *cpu_context_ptr;
	user_data_t *initserver; // next BL user process
	uint32_t spsr; // next BL image
	gp_regs_t *ctx;
	unsigned int security_state, prev_mode, mode, process_mode;

	initserver = &initserver_data;
#if CTX_INCLUDE_AARCH32_REGS
	/*
	 * Ensure that the build flag to save AArch32 system registers in CPU
	 * context is not set for AArch64-only platforms.
	 */
	if (el_implemented(1) == EL_IMPL_A64ONLY) {
		ERROR("EL1 supports AArch64-only. Please set build flag "
				"CTX_INCLUDE_AARCH32_REGS = 0\n");
		panic();
	}
#endif

#ifdef CONFIG_ARM_MONITOR_SUPPORT
	prev_mode = MODE_EL3;
	security_state = SECURE;
	cpu_ops.setup = setup_el3_context;
#if ENABLE_RUN_IN_CURRENT
	mode = MODE_EL3;
	process_mode = MONITOR_K;
	cpu_ops.next_setup = NULL;
#else
	/* Prepare the SPSR for the next BL image. */
	if ((security_state != SECURE) && (el_implemented(2) != EL_IMPL_NONE)) {
		mode = MODE_EL2;
		process_mode = HYPERVISOR_U;
		cpu_ops.next_setup = setup_el2_context;
	} else {
		mode = MODE_EL1;
		process_mode = SUPERVISER_U;
		cpu_ops.next_setup = setup_el1_context;
	}
#endif
#elif CONFIG_ARM_HYPERVISOR_SUPPORT
	prev_mode = MODE_EL2;

	security_state = NON_SECURE;
	cpu_ops.setup = setup_el2_context;

#if ENABLE_RUN_IN_CURRENT
	mode = MODE_EL2;
	process_mode = HYPERVISOR_K;
	cpu_ops.next_setup = NULL;
#else
	mode = MODE_EL1;
	process_mode = SUPERVISER_U;
	cpu_ops.next_setup = setup_el1_context;
#endif
#else
	prev_mode = MODE_EL1;

	security_state = NON_SECURE;
	cpu_ops.setup = setup_el1_context;
	cpu_ops.next_setup = NULL;
#if ENABLE_RUN_IN_CURRENT
	mode = MODE_EL1;
	process_mode = SUPERVISER_K;
#else
	mode = MODE_EL0;
	process_mode = ADMINISTRATOR_U;
#endif
#endif


	world_data_ptr = &perworld_data[security_state];
	zeromem(world_data_ptr, sizeof(*world_data_ptr));
	cpu_context_ptr = &kernel_pcpu_context[security_state];
	world_data_ptr->extra = cpu_context_ptr;

	/* Setup the Secure/Non-Secure context if not done already. */
	if (cm_get_world_context(security_state) == NULL)
		cm_set_world_context(world_data_ptr, security_state);

	spsr = (uint32_t)SPSR_64((uint64_t) mode,
		(uint64_t)MODE_SP_ELX, DISABLE_ALL_EXCEPTIONS);

	/* Clear any residual register values from the context */
	zeromem(cpu_context_ptr, sizeof(*cpu_context_ptr));

	/* next process */
	initserver->base.mode |= (BIT(security_state) | BIT(process_mode));
	ctx = get_gpregs_ctx(initserver->base.cpu_context);
	write_ctx_reg(ctx, CTX_ELR_ELX, initserver->base.handler_entry);
	write_ctx_reg(ctx, CTX_SPSR_ELX, spsr);
	/* Prepare the context for the next BL image. */
	cpu_ops.setup(prev_mode, cpu_context_ptr, initserver);
	cpu_ops.next_setup(prev_mode, cpu_context_ptr, initserver);

}

/*******************************************************************************
 * The following function performs initialization of the world_process 'ctx'
 * for first use that is common to all security states, and sets the
 * initial entrypoint state as specified by the entry_point_info structure.
 *
 * The EE and ST attributes are used to configure the endianness and secure
 * timer availability for the new execution context.
 ******************************************************************************/
static void setup_el3_context(unsigned int prev_mode, pcpu_context_t *ctx, user_data_t *process_data)
{
	u_register_t scr_el3;
	el3_state_t *state;
	uint32_t spsr;
	unsigned int security_state;

	unsigned int secure = BIT(SECURE), non_secure = BIT(NON_SECURE);
	unsigned int mask = secure | non_secure;

	(void) prev_mode;
	
	spsr = process_data->base.cpu_context.spsr_x;
	security_state = process_data->base.mode & mask;


	/* ---------------------------------------------------------------------
	 * Initialise SCR_EL3, setting all fields rather than relying on hw.
	 * All fields are architecturally UNKNOWN on reset. The following fields
	 * do not change during the TF lifetime. The remaining fields are set to
	 * zero here but are updated ahead of transitioning to a lower EL in the
	 * function cm_init_context_common().
	 *
	 * SCR_EL3.TWE: Set to zero so that execution of WFE instructions at
	 *  EL2, EL1 and EL0 are not trapped to EL3.
	 *
	 * SCR_EL3.TWI: Set to zero so that execution of WFI instructions at
	 *  EL2, EL1 and EL0 are not trapped to EL3.
	 *
	 * SCR_EL3.SIF: Set to one to disable instruction fetches from
	 *  Non-secure memory.
	 *
	 * SCR_EL3.SMD: Set to zero to enable CALL calls at EL1 and above, from
	 *  both Security states and both Execution states.
	 *
	 * SCR_EL3.EA: Set to one to route External Aborts and SError Interrupts
	 *  to EL3 when executing at any EL.
	 *
	 * SCR_EL3.{API,APK}: For Armv8.3 pointer authentication feature,
	 * disable traps to EL3 when accessing key registers or using pointer
	 * authentication instructions from lower ELs.
	 * ---------------------------------------------------------------------
	 */	 
	write_scr_el3((SCR_RESET_VAL | SCR_EA_BIT | SCR_SIF_BIT)
			& ~(SCR_TWE_BIT | SCR_TWI_BIT | SCR_SMD_BIT));

	/* ---------------------------------------------------------------------
	 * Initialise MDCR_EL3, setting all fields rather than relying on hw.
	 * Some fields are architecturally UNKNOWN on reset.
	 *
	 * MDCR_EL3.SDD: Set to one to disable AArch64 Secure self-hosted debug.
	 *  Debug exceptions, other than Breakpoint Instruction exceptions, are
	 *  disabled from all ELs in Secure state.
	 *
	 * MDCR_EL3.SPD32: Set to 0b10 to disable AArch32 Secure self-hosted
	 *  privileged debug from S-EL1.
	 *
	 * MDCR_EL3.TDOSA: Set to zero so that EL2 and EL2 System register
	 *  access to the powerdown debug registers do not trap to EL3.
	 *
	 * MDCR_EL3.TDA: Set to zero to allow EL0, EL1 and EL2 access to the
	 *  debug registers, other than those registers that are controlled by
	 *  MDCR_EL3.TDOSA.
	 *
	 * MDCR_EL3.TPM: Set to zero so that EL0, EL1, and EL2 System register
	 *  accesses to all Performance Monitors registers do not trap to EL3.
	 *
	 * MDCR_EL3.SCCD: Set to one so that cycle counting by PMCCNTR_EL0 is
	 *  prohibited in Secure state. This bit is RES0 in versions of the
	 *  architecture with FEAT_PMUv3p5 not implemented, setting it to 1
	 *  doesn't have any effect on them.
	 *
	 * MDCR_EL3.MCCD: Set to one so that cycle counting by PMCCNTR_EL0 is
	 *  prohibited in EL3. This bit is RES0 in versions of the
	 *  architecture with FEAT_PMUv3p7 not implemented, setting it to 1
	 *  doesn't have any effect on them.
	 *
	 * MDCR_EL3.SPME: Set to zero so that event counting by the programmable
	 *  counters PMEVCNTR<n>_EL0 is prohibited in Secure state. If ARMv8.2
	 *  Debug is not implemented this bit does not have any effect on the
	 *  counters unless there is support for the implementation defined
	 *  authentication interface ExternalSecureNoninvasiveDebugEnabled().
	 *
	 * MDCR_EL3.NSTB, MDCR_EL3.NSTBE: Set to zero so that Trace Buffer
	 *  owning security state is Secure state. If FEAT_TRBE is implemented,
	 *  accesses to Trace Buffer control registers at EL2 and EL1 in any
	 *  security state generates trap exceptions to EL3.
	 *  If FEAT_TRBE is not implemented, these bits are RES0.
	 *
	 * MDCR_EL3.TTRF: Set to one so that access to trace filter control
	 *  registers in non-monitor mode generate EL3 trap exception,
	 *  unless the access generates a higher priority exception when trace
	 *  filter control(FEAT_TRF) is implemented.
	 *  When FEAT_TRF is not implemented, this bit is RES0.
	 * ---------------------------------------------------------------------
	 */


	write_mdcr_el3((MDCR_EL3_RESET_VAL | MDCR_SDD_BIT | 
		      MDCR_SPD32(MDCR_SPD32_DISABLE) | MDCR_SCCD_BIT | 
		      MDCR_MCCD_BIT) & ~(MDCR_SPME_BIT | MDCR_TDOSA_BIT | 
		      MDCR_TDA_BIT | MDCR_TPM_BIT | MDCR_NSTB(MDCR_NSTB_EL1) | 
		      MDCR_NSTBE | MDCR_TTRF_BIT));
	/* ---------------------------------------------------------------------
	 * Initialise PMCR_EL0 setting all fields rather than relying
	 * on hw. Some fields are architecturally UNKNOWN on reset.
	 *
	 * PMCR_EL0.LP: Set to one so that event counter overflow, that
	 *  is recorded in PMOVSCLR_EL0[0-30], occurs on the increment
	 *  that changes PMEVCNTR<n>_EL0[63] from 1 to 0, when ARMv8.5-PMU
	 *  is implemented. This bit is RES0 in versions of the architecture
	 *  earlier than ARMv8.5, setting it to 1 doesn't have any effect
	 *  on them.
	 *
	 * PMCR_EL0.LC: Set to one so that cycle counter overflow, that
	 *  is recorded in PMOVSCLR_EL0[31], occurs on the increment
	 *  that changes PMCCNTR_EL0[63] from 1 to 0.
	 *
	 * PMCR_EL0.DP: Set to one so that the cycle counter,
	 *  PMCCNTR_EL0 does not count when event counting is prohibited.
	 *
	 * PMCR_EL0.X: Set to zero to disable export of events.
	 *
	 * PMCR_EL0.D: Set to zero so that, when enabled, PMCCNTR_EL0
	 *  counts on every clock cycle.
	 * ---------------------------------------------------------------------
	 */
	write_pmcr_el0((PMCR_EL0_RESET_VAL | PMCR_EL0_LP_BIT | 
		      PMCR_EL0_LC_BIT | PMCR_EL0_DP_BIT) & 
		    ~(PMCR_EL0_X_BIT | PMCR_EL0_D_BIT));
	/* ---------------------------------------------------------------------
	 * Initialise CPTR_EL3, setting all fields rather than relying on hw.
	 * All fields are architecturally UNKNOWN on reset.
	 *
	 * CPTR_EL3.TCPAC: Set to zero so that any accesses to CPACR_EL1,
	 *  CPTR_EL2, CPACR, or HCPTR do not trap to EL3.
	 *
	 * CPTR_EL3.TTA: Set to one so that accesses to the trace system
	 *  registers trap to EL3 from all exception levels and security
	 *  states when system register trace is implemented.
	 *  When system register trace is not implemented, this bit is RES0 and
	 *  hence set to zero.
	 *
	 * CPTR_EL3.TTA: Set to zero so that System register accesses to the
	 *  trace registers do not trap to EL3.
	 *
	 * CPTR_EL3.TFP: Set to zero so that accesses to the V- or Z- registers
	 *  by Advanced SIMD, floating-point or SVE instructions (if implemented)
	 *  do not trap to EL3.
	 *
	 * CPTR_EL3.TAM: Set to one so that Activity Monitor access is
	 *  trapped to EL3 by default.
	 *
	 * CPTR_EL3.EZ: Set to zero so that all SVE functionality is trapped
	 *  to EL3 by default.
	 *
	 * CPTR_EL3.ESM: Set to zero so that all SME functionality is trapped
	 *  to EL3 by default.
	 */
	write_cptr_el3(CPTR_EL3_RESET_VAL & ~(TCPAC_BIT | TTA_BIT | TFP_BIT));
	/*
	 * If Data Independent Timing (DIT) functionality is implemented,
	 * always enable DIT in EL3.
	 * First assert that the FEAT_DIT build flag matches the feature id
	 * register value for DIT.
	 */
#if ENABLE_FEAT_DIT
	write_dit(DIT_BIT);
#endif

	/*
	 * SCR_EL3 was initialised during reset sequence in macro
	 * el3_arch_init_common. This code modifies the SCR_EL3 fields that
	 * affect the next EL.
	 *
	 * The following fields are initially set to zero and then updated to
	 * the required value depending on the state of the SPSR_EL3 and the
	 * Security state and entrypoint attributes of the next EL.
	 */	
	scr_el3 = read_scr_el3();
	scr_el3 &= ~(SCR_NS_BIT | SCR_RW_BIT | SCR_FIQ_BIT | SCR_IRQ_BIT |
			SCR_ST_BIT | SCR_HCE_BIT | SCR_NSE_BIT);



	/*
	 * SCR_EL3.RW: Set the execution state, AArch32 or AArch64, for next
	 *  Exception level as specified by SPSR.
	 */
	if (GET_RW(spsr) == MODE_RW_64)
		scr_el3 |= SCR_RW_BIT;

	/*
	 * SCR_EL3.ST: Traps Secure EL1 accesses to the Counter-timer Physical
	 * Secure timer registers to EL3, from AArch64 state only, if specified
	 * by the entrypoint attributes. If SEL2 is present and enabled, the ST
	 * bit always behaves as 1 (i.e. secure physical timer register access
	 * is not trapped)
	 */
	if (security_state == secure)
		scr_el3 |= SCR_ST_BIT;

	/*
	 * If FEAT_HCX is enabled, enable access to HCRX_EL2 by setting
	 * SCR_EL3.HXEn.
	 */
#if ENABLE_FEAT_HCX
	scr_el3 |= SCR_HXEn_BIT;
#endif

#if RAS_TRAP_LOWER_EL_ERR_ACCESS
	/*
	 * SCR_EL3.TERR: Trap Error record accesses. Accesses to the RAS ERR
	 * and RAS ERX registers from EL1 and EL2 are trapped to EL3.
	 */
	scr_el3 |= SCR_TERR_BIT;
#endif

#if !HANDLE_EA_EL3_FIRST
	/*
	 * SCR_EL3.EA: Do not route External Abort and SError Interrupt External
	 * to EL3 when executing at a lower EL. When executing at EL3, External
	 * Aborts are taken to EL3.
	 */
	scr_el3 &= ~SCR_EA_BIT;
#endif

#if FAULT_INJECTION_SUPPORT
	/* Enable fault injection from lower ELs */
	scr_el3 |= SCR_FIEN_BIT;
#endif

	/*
	 * SCR_EL3.HCE: Enable HVC instructions if next execution state is
	 * AArch64 and next EL is EL2, or if next execution state is AArch32 and
	 * next mode is Hyp.
	 * SCR_EL3.FGTEn: Enable Fine Grained Virtualization Traps under the
	 * same conditions as HVC instructions and when the processor supports
	 * ARMv8.6-FGT.
	 * SCR_EL3.ECVEn: Enable Enhanced Counter Virtualization (ECV)
	 * CNTPOFF_EL2 register under the same conditions as HVC instructions
	 * and when the processor supports ECV.
	 */
	if (((GET_RW(spsr) == MODE_RW_64) && (GET_EL(spsr) == MODE_EL2))
	    || ((GET_RW(spsr) != MODE_RW_64) && (GET_M32(spsr) == MODE32_hyp))) {
		scr_el3 |= SCR_HCE_BIT;

		if (is_armv8_6_fgt_present())
			scr_el3 |= SCR_FGTEN_BIT;

		if (get_armv8_6_ecv_support()
		    == ID_AA64MMFR0_EL1_ECV_SELF_SYNCH)
			scr_el3 |= SCR_ECVEN_BIT;
	}

#if ENABLE_FEAT_TWED
	/* Enable WFE trap delay in SCR_EL3 if supported and configured */
	/* Set delay in SCR_EL3 */
	scr_el3 &= ~(SCR_TWEDEL_MASK << SCR_TWEDEL_SHIFT);
	scr_el3 |= ((TWED_DELAY & SCR_TWEDEL_MASK)
			<< SCR_TWEDEL_SHIFT);

	/* Enable WFE delay */
	scr_el3 |= SCR_TWEDEn_BIT;
#endif /* ENABLE_FEAT_TWED */

	if (security_state == secure) {
		scr_el3 |= get_scr_el3_from_routing_model(SECURE);
#if CTX_INCLUDE_MTE_REGS
		scr_el3 |= SCR_ATA_BIT;
#endif
	/* Enable S-EL2 if the next EL is EL2 and S-EL2 is present */
	if ((GET_EL(spsr) == MODE_EL2) && is_armv8_4_sel2_present()) {
		if (GET_RW(spsr) != MODE_RW_64) {
			ERROR("S-EL2 can not be used in AArch32\n.");
			panic();
		}
		scr_el3 |= SCR_EEL2_BIT;
	}

	} else if (security_state == non_secure) {
		/* SCR_NS: Set the NS bit */
		scr_el3 |= SCR_NS_BIT;
#if !CTX_INCLUDE_PAUTH_REGS
		/*
		 * If the pointer authentication registers aren't saved during world
		 * switches the value of the registers can be leaked from the Secure to
		 * the Non-secure world. To prevent this, rather than enabling pointer
		 * authentication everywhere, we only enable it in the Non-secure world.
		 *
		 * If the Secure world wants to use pointer authentication,
		 * CTX_INCLUDE_PAUTH_REGS must be set to 1.
		 */
		scr_el3 |= SCR_API_BIT | SCR_APK_BIT;
#endif /* !CTX_INCLUDE_PAUTH_REGS */
	
		/* Allow access to Allocation Tags when MTE is implemented. */
		scr_el3 |= SCR_ATA_BIT;
		/*
		 * SCR_EL3.IRQ, SCR_EL3.FIQ: Enable the physical FIQ and IRQ routing as
		 *  indicated by the interrupt routing model for BL31.
		 */
		scr_el3 |= get_scr_el3_from_routing_model(NON_SECURE);

	} else {
		ERROR("Invalid security state\n");
		panic();
	}

	/*
	 * Populate EL3 state so that we've the right context
	 * before doing ERET
	 */
	state = get_el3state_ctx(ctx);
	write_ctx_reg(state, CTX_SCR_EL3, scr_el3);
	/*
	 * CPTR_EL3 was initialized out of reset, copy that value to the
	 * context register.
	 */
	write_ctx_reg(get_el3state_ctx(ctx), CTX_CPTR_EL3, read_cptr_el3());
	write_ctx_reg(get_el3state_ctx(ctx), CTX_PMCR_EL0, read_pmcr_el0());

	write_scr_el3(scr_el3);
}

static void setup_el2_context(unsigned int prev_mode, pcpu_context_t *ctx, user_data_t *process_data)
{
	u_register_t sysreg_el2    = 0;
	unsigned int security_state;
	unsigned int secure = BIT(SECURE), non_secure = BIT(NON_SECURE);
	unsigned int mask = secure | non_secure;
	uint32_t spsr;

	(void) prev_mode;


	spsr = process_data->base.cpu_context.spsr_x;
	security_state = process_data->base.mode & mask;
	if (security_state != NON_SECURE)
		return;		
	/* ---------------------------------------------------------------------
	 * Initialise HCR_EL2, setting all fields rather than relying on HW.
	 * All fields are architecturally UNKNOWN on reset. The following fields
	 * do not change during the TF lifetime. The remaining fields are set to
	 * zero here but are updated ahead of transitioning to a lower EL in the
	 * function cm_init_context_common().
	 *
	 * HCR_EL2.TWE: Set to zero so that execution of WFE instructions at
	 *  EL2, EL1 and EL0 are not trapped to EL2.
	 *
	 * HCR_EL2.TWI: Set to zero so that execution of WFI instructions at
	 *  EL2, EL1 and EL0 are not trapped to EL2.
	 *
	 * HCR_EL2.HCD: Set to zero to enable HVC calls at EL1 and above,
	 *  from both Security states and both Execution states.
	 *
	 * HCR_EL2.TEA: Set to one to route External Aborts and SError
	 * Interrupts to EL2 when executing at any EL.
	 *
	 * HCR_EL2.{API,APK}: For Armv8.3 pointer authentication feature,
	 * disable traps to EL2 when accessing key registers or using
	 * pointer authentication instructions from lower ELs.
	 * ---------------------------------------------------------------------
	 */ 
	if (GET_RW(spsr) == MODE_RW_64)
 		sysreg_el2 |= HCR_RW_BIT;
	/*
	 * For Armv8.3 pointer authentication feature, disable
	 * traps to EL2 when accessing key registers or using
	 * pointer authentication instructions from lower ELs.
	 */
	sysreg_el2 |= (HCR_API_BIT | HCR_APK_BIT);	
	sysreg_el2 |=  (HCR_RESET_VAL | HCR_TEA_BIT)
			& ~(HCR_TWE_BIT | HCR_TWI_BIT | HCR_HCD_BIT);
	write_hcr_el2(sysreg_el2);

	/* ---------------------------------------------------------------------
	 * Initialise MDCR_EL2, setting all fields rather than relying on
	 * hw. Some fields are architecturally UNKNOWN on reset.
	 *
	 * MDCR_EL2.TDOSA: Set to zero so that EL2 and EL2 System register
	 *  access to the powerdown debug registers do not trap to EL2.
	 *
	 * MDCR_EL2.TDA: Set to zero to allow EL0, EL1 and EL2 access to the
	 *  debug registers, other than those registers that are controlled by
	 *  MDCR_EL2.TDOSA.
	 *
	 * MDCR_EL2.TPM: Set to zero so that EL0, EL1, and EL2 System
	 *  register accesses to all Performance Monitors registers do not trap
	 *  to EL2.
	 *
	 * MDCR_EL2.HPMD: Set to zero so that event counting by the program-
	 *  mable counters PMEVCNTR<n>_EL0 is prohibited in Secure state. If
	 *  ARMv8.2 Debug is not implemented this bit does not have any effect
	 *  on the counters unless there is support for the implementation
	 *  defined authentication interface
	 *  ExternalSecureNoninvasiveDebugEnabled().
	 * ---------------------------------------------------------------------
	 */
	sysreg_el2 = 0;
	sysreg_el2 = (MDCR_EL2_RESET_VAL | 
		      MDCR_SPD32(MDCR_SPD32_DISABLE)) 
		      & ~(MDCR_EL2_HPMD | MDCR_TDOSA_BIT | 
		      MDCR_TDA_BIT | MDCR_TPM_BIT);
	write_mdcr_el2(sysreg_el2);
	/*
	 * Initialise MDCR_EL2, setting all fields rather than
	 * relying on hw. Some fields are architecturally
	 * UNKNOWN on reset.
	 *
	 * MDCR_EL2.HLP: Set to one so that event counter
	 *  overflow, that is recorded in PMOVSCLR_EL0[0-30],
	 *  occurs on the increment that changes
	 *  PMEVCNTR<n>_EL0[63] from 1 to 0, when ARMv8.5-PMU is
	 *  implemented. This bit is RES0 in versions of the
	 *  architecture earlier than ARMv8.5, setting it to 1
	 *  doesn't have any effect on them.
	 *
	 * MDCR_EL2.TTRF: Set to zero so that access to Trace
	 *  Filter Control register TRFCR_EL1 at EL1 is not
	 *  trapped to EL2. This bit is RES0 in versions of
	 *  the architecture earlier than ARMv8.4.
	 *
	 * MDCR_EL2.HPMD: Set to one so that event counting is
	 *  prohibited at EL2. This bit is RES0 in versions of
	 *  the architecture earlier than ARMv8.1, setting it
	 *  to 1 doesn't have any effect on them.
	 *
	 * MDCR_EL2.TPMS: Set to zero so that accesses to
	 *  Statistical Profiling control registers from EL1
	 *  do not trap to EL2. This bit is RES0 when SPE is
	 *  not implemented.
	 *
	 * MDCR_EL2.TDRA: Set to zero so that Non-secure EL0 and
	 *  EL1 System register accesses to the Debug ROM
	 *  registers are not trapped to EL2.
	 *
	 * MDCR_EL2.TDOSA: Set to zero so that Non-secure EL1
	 *  System register accesses to the powerdown debug
	 *  registers are not trapped to EL2.
	 *
	 * MDCR_EL2.TDA: Set to zero so that System register
	 *  accesses to the debug registers do not trap to EL2.
	 *
	 * MDCR_EL2.TDE: Set to zero so that debug exceptions
	 *  are not routed to EL2.
	 *
	 * MDCR_EL2.HPME: Set to zero to disable EL2 Performance
	 *  Monitors.
	 *
	 * MDCR_EL2.TPM: Set to zero so that Non-secure EL0 and
	 *  EL1 accesses to all Performance Monitors registers
	 *  are not trapped to EL2.
	 *
	 * MDCR_EL2.TPMCR: Set to zero so that Non-secure EL0
	 *  and EL1 accesses to the PMCR_EL0 or PMCR are not
	 *  trapped to EL2.
	 *
	 * MDCR_EL2.HPMN: Set to value of PMCR_EL0.N which is the
	 *  architecturally-defined reset value.
	 *
	 * MDCR_EL2.E2TB: Set to zero so that the trace Buffer
	 *  owning exception level is NS-EL1 and, tracing is
	 *  prohibited at NS-EL2. These bits are RES0 when
	 *  FEAT_TRBE is not implemented.
	 */
	 sysreg_el2 = 0;
	sysreg_el2 = ((MDCR_EL2_RESET_VAL | MDCR_EL2_HLP |
		     MDCR_EL2_HPMD) |
		   ((read_pmcr_el0() & PMCR_EL0_N_BITS)
		   >> PMCR_EL0_N_SHIFT)) &
		   ~(MDCR_EL2_TTRF | MDCR_EL2_TPMS |
		     MDCR_EL2_TDRA_BIT | MDCR_EL2_TDOSA_BIT |
		     MDCR_EL2_TDA_BIT | MDCR_EL2_TDE_BIT |
		     MDCR_EL2_HPME_BIT | MDCR_EL2_TPM_BIT |
		     MDCR_EL2_TPMCR_BIT |
		     MDCR_EL2_E2TB(MDCR_EL2_E2TB_EL1));
	
	write_mdcr_el2(sysreg_el2);
	
	/* ---------------------------------------------------------------------
	 * Initialise PMCR_EL0 setting all fields rather than relying
	 * on hw. Some fields are architecturally UNKNOWN on reset.
	 *
	 * PMCR_EL0.DP: Set to one so that the cycle counter,
	 *  PMCCNTR_EL0 does not count when event counting is prohibited.
	 *
	 * PMCR_EL0.X: Set to zero to disable export of events.
	 *
	 * PMCR_EL0.D: Set to zero so that, when enabled, PMCCNTR_EL0
	 *  counts on every clock cycle.
	 * ---------------------------------------------------------------------
	 */
	sysreg_el2 = 0; 
	sysreg_el2 = (PMCR_EL0_RESET_VAL | PMCR_EL0_DP_BIT) & 
		    ~(PMCR_EL0_X_BIT | PMCR_EL0_D_BIT);
	write_pmcr_el0(sysreg_el2);
	/* ---------------------------------------------------------------------
	 * Initialise CPTR_EL2, setting all fields rather than relying on hw.
	 * All fields are architecturally UNKNOWN on reset.
	 *
	 * CPTR_EL2.TCPAC: Set to zero so that any accesses to CPACR_EL1 do
	 * not trap to EL2.
	 *
	 * CPTR_EL2.TTA: Set to zero so that System register accesses to the
	 *  trace registers do not trap to EL2.
	 *
	 * CPTR_EL2.TFP: Set to zero so that accesses to the V- or Z- registers
	 *  by Advanced SIMD, floating-point or SVE instructions (if implemented)
	 *  do not trap to EL2.
	 */
	sysreg_el2 = 0; 
	 sysreg_el2 = CPTR_EL2_RESET_VAL & ~(CPTR_EL2_TCPAC_BIT | CPTR_EL2_TTA_BIT | CPTR_EL2_TFP_BIT);
	 write_cptr_el2(sysreg_el2);

	 /*
	  * Initialise CNTHCTL_EL2. All fields are
	  * architecturally UNKNOWN on reset and are set to zero
	  * except for field(s) listed below.
	  *
	  * CNTHCTL_EL2.EL1PTEN: Set to one to disable traps to
	  *  Hyp mode of Non-secure EL0 and EL1 accesses to the
	  *  physical timer registers.
	  *
	  * CNTHCTL_EL2.EL1PCTEN: Set to one to disable traps to
	  *  Hyp mode of  Non-secure EL0 and EL1 accesses to the
	  *  physical counter registers.
	  */
	 sysreg_el2 = 0; 
	 sysreg_el2 = CNTHCTL_RESET_VAL |
				 EL1PCEN_BIT | EL1PCTEN_BIT;
	 write_cnthctl_el2(sysreg_el2);

	 /*
	  * Initialise CNTVOFF_EL2 to zero as it resets to an
	  * architecturally UNKNOWN value.
	  */
	 sysreg_el2 = 0;
	 write_cntvoff_el2(sysreg_el2);

	 /*
	  * Set VPIDR_EL2 and VMPIDR_EL2 to match MIDR_EL1 and
	  * MPIDR_EL1 respectively.
	  */
	 sysreg_el2 = read_midr_el1();
	 write_vpidr_el2(sysreg_el2);
	 sysreg_el2 = read_mpidr_el1();
	 write_vmpidr_el2(sysreg_el2);
	 /*
	  * Initialise VTTBR_EL2. All fields are architecturally
	  * UNKNOWN on reset.
	  *
	  * VTTBR_EL2.VMID: Set to zero. Even though EL1&0 stage
	  *  2 address translation is disabled, cache maintenance
	  *  operations depend on the VMID.
	  *
	  * VTTBR_EL2.BADDR: Set to zero as EL1&0 stage 2 address
	  *  translation is disabled.
	  */
	 sysreg_el2 = 0; 
	 sysreg_el2 = VTTBR_RESET_VAL &
		 ~((VTTBR_VMID_MASK << VTTBR_VMID_SHIFT)
		 | (VTTBR_BADDR_MASK << VTTBR_BADDR_SHIFT));
	 write_vttbr_el2(sysreg_el2);
	 /*
	  * Initialise HSTR_EL2. All fields are architecturally
	  * UNKNOWN on reset.
	  *
	  * HSTR_EL2.T<n>: Set all these fields to zero so that
	  *  Non-secure EL0 or EL1 accesses to System registers
	  *  do not trap to EL2.
	  */
	 sysreg_el2 = 0; 
	 sysreg_el2 = HSTR_EL2_RESET_VAL & ~(HSTR_EL2_T_MASK); 
	 write_hstr_el2(sysreg_el2);
	 /*
	  * Initialise CNTHP_CTL_EL2. All fields are
	  * architecturally UNKNOWN on reset.
	  *
	  * CNTHP_CTL_EL2:ENABLE: Set to zero to disable the EL2
	  *  physical timer and prevent timer interrupts.
	  */
	 sysreg_el2 = 0; 
	 sysreg_el2 = CNTHP_CTL_RESET_VAL &
				 ~(CNTHP_CTL_ENABLE_BIT);
	 write_cnthp_ctl_el2(sysreg_el2);
	 cm_el2_sysregs_context_save(CTZL(security_state));
}

static void setup_el1_context(unsigned int prev_mode, pcpu_context_t *ctx, user_data_t *process_data)
{
	u_register_t sctlr_elx = 0;
	unsigned int security_state;
	unsigned int secure = BIT(SECURE), non_secure = BIT(NON_SECURE);
	unsigned int mask = secure | non_secure;


	security_state = process_data->base.mode & mask;
	if (security_state != NON_SECURE)
		return;

	
	if (el_implemented(2) != EL_IMPL_NONE && prev_mode == MODE_EL3) {
		sctlr_elx &= SCTLR_EE_BIT;
		sctlr_elx |= SCTLR_EL2_RES1;
		write_sctlr_el2(sctlr_elx);
		write_ctx_reg(get_el1_sysregs_ctx(ctx), CTX_SCTLR_EL2, sctlr_elx);
	}

	cm_el1_sysregs_context_save(CTZL(security_state));
}



#if CTX_INCLUDE_EL2_REGS
/*******************************************************************************
 * Save EL2 sysreg context
 ******************************************************************************/
void cm_el2_sysregs_context_save(uint32_t security_state)
{
	u_register_t scr_el3 = read_scr();

	/*
	 * Always save the non-secure and realm EL2 context, only save the
	 * S-EL2 context if S-EL2 is enabled.
	 */
	if ((security_state != SECURE) ||
	    ((security_state == SECURE) && ((scr_el3 & SCR_EEL2_BIT) != 0U))) {
		pcpu_context_t *ctx;

		ctx = cm_get_world_context_extra(security_state);
		assert(ctx != NULL);

		el2_sysregs_context_save_common(get_el2_sysregs_ctx(ctx));
	}
}

/*******************************************************************************
 * Restore EL2 sysreg context
 ******************************************************************************/
void cm_el2_sysregs_context_restore(uint32_t security_state)
{
	u_register_t scr_el3 = read_scr();

	/*
	 * Always restore the non-secure and realm EL2 context, only restore the
	 * S-EL2 context if S-EL2 is enabled.
	 */
	if ((security_state != SECURE) ||
	    ((security_state == SECURE) && ((scr_el3 & SCR_EEL2_BIT) != 0U))) {
		pcpu_context_t *ctx;

		ctx = cm_get_world_context_extra(security_state);
		assert(ctx != NULL);

		el2_sysregs_context_restore_common(get_el2_sysregs_ctx(ctx));
	}
}
#endif /* CTX_INCLUDE_EL2_REGS */


#if CTX_INCLUDE_EL1_REGS

/*******************************************************************************
 * The next four functions are used by runtime services to save and restore
 * EL1 context on the 'world_process' structure for the specified security
 * state.
 ******************************************************************************/
void cm_el1_sysregs_context_save(uint32_t security_state)
{
	pcpu_context_t *ctx;

	ctx = cm_get_world_context_extra(security_state);
	assert(ctx != NULL);

	el1_sysregs_context_save(get_el1_sysregs_ctx(ctx));
}

void cm_el1_sysregs_context_restore(uint32_t security_state)
{
	pcpu_context_t *ctx;

	ctx = cm_get_world_context_extra(security_state);
	assert(ctx != NULL);

	el1_sysregs_context_restore(get_el1_sysregs_ctx(ctx));
}
#endif

