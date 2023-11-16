/*
 * Copyright (c) 2016-2020, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <platform_def.h>
#include <arch.h>
#include <arch_helpers.h>
#include <common.h>
#include <context.h>
#include <runtime/context_mgmt.h>
#include <debug.h>
#include <utils.h>

/*******************************************************************************
 * Context management library initialisation routine. This library is used by
 * runtime services to share pointers to 'cpu_context' structures for the secure
 * and non-secure states. Management of the structures and their associated
 * memory is not done by the context management library e.g. the PSCI service
 * manages the cpu context used for entry from and exit to the non-secure state.
 * The Secure payload manages the context(s) corresponding to the secure state.
 * It also uses this library to get access to the non-secure
 * state cpu context pointers.
 ******************************************************************************/
void cm_init(void)
{
	/*
	 * The context management library has only global data to initialize, but
	 * that will be done when the BSS is zeroed out
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


/*******************************************************************************
 * This function prepares the context for Secure/Normal world images.
 * Normal world images are transitioned to HYP(if supported) else SVC.
 ******************************************************************************/
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

	unsigned int security_state, prev_mode, mode, process_mode;

	initserver = &initserver_data;
	
#ifdef CONFIG_ARM_MONITOR_SUPPORT
	prev_mode= MODE32_mon;

	security_state = SECURE;
	cpu_ops.setup = setup_el3_context;
#if ENABLE_RUN_IN_CURRENT
	mode = MODE32_mon;
	process_mode = MONITOR_K;
	cpu_ops.next_setup = NULL;
#else
	/* Prepare the SPSR for the next BL image. */
	if ((security_state != SECURE) && GET_VIRT_EXT(read_id_pfr1()) != 0U) {
		mode = MODE32_hyp;
		process_mode = HYPERVISOR_U;
		cpu_ops.next_setup = setup_el2_context;
	} else {
		mode = MODE32_svc;
		process_mode = SUPERVISER_U;
		cpu_ops.next_setup = setup_el1_context;
	}
#endif
#elif CONFIG_ARM_HYPERVISOR_SUPPORT
	prev_mode= MODE32_hyp;

	security_state = NON_SECURE;
	cpu_ops.setup = setup_el2_context;

#if ENABLE_RUN_IN_CURRENT
	mode = MODE32_hyp;
	process_mode = HYPERVISOR_K;
	cpu_ops.next_setup = NULL;
#else
	mode = MODE32_svc;
	process_mode = SUPERVISER_U;
	cpu_ops.next_setup = setup_el1_context;
#endif
#else
	prev_mode= MODE32_svc;
	security_state = NON_SECURE;
	cpu_ops.setup = setup_el1_context;
	cpu_ops.next_setup = NULL;
#if ENABLE_RUN_IN_CURRENT
	mode = MODE32_svc;
	process_mode = SUPERVISER_K;
#else
	mode = MODE32_usr;
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

	spsr = SPSR_MODE32(mode, SPSR_T_ARM,
				SPSR_E_LITTLE, DISABLE_ALL_EXCEPTIONS);

	/* Clear any residual register values from the context */
	zeromem(cpu_context_ptr, sizeof(*cpu_context_ptr));

	/* next process */
	initserver->base.mode |= (BIT(security_state) | BIT(process_mode));


#ifdef CONFIG_ARM_MONITOR_SUPPORT
	initserver->base.cpu_context.gpregs_ctx.spsr_mon = spsr;
	initserver->base.cpu_context.gpregs_ctx.lr_mon = initserver->base.handler_entry;
#elif CONFIG_ARM_HYPERVISOR_SUPPORT
	initserver->base.cpu_context.gpregs_ctx.spsr_hyp = spsr;
	initserver->base.cpu_context.gpregs_ctx.lr_hyp = initserver->base.handler_entry;
#else
	initserver->base.cpu_context.gpregs_ctx.spsr_svc = spsr;
	initserver->base.cpu_context.gpregs_ctx.lr_svc = initserver->base.handler_entry;
#endif

	/* Prepare the context for the next BL image. */
	cpu_ops.setup(prev_mode, cpu_context_ptr, initserver);
	cpu_ops.next_setup(prev_mode, cpu_context_ptr, initserver);

}

static void setup_el3_context(unsigned int prev_mode, pcpu_context_t *ctx, user_data_t *process_data)
{
	unsigned int security_state;
	uint32_t scr, sctlr, nsacr, sdcr, cpsr;
	sysregs_t *reg_ctx;
	uint32_t spsr;
	unsigned int security_state;

	unsigned int secure = BIT(SECURE), non_secure = BIT(NON_SECURE);
	unsigned int mask = secure | non_secure;

	(void) prev_mode;
	
	spsr = process_data->base.cpu_context.spsr_x;
	security_state = process_data->base.mode & mask;


	/* ---------------------------------------------------------------------
	 * SCTLR has already been initialised - read current value before
	 * modifying.
	 *
	 * SCTLR.I: Enable the instruction cache.
	 *
	 * SCTLR.A: Enable Alignment fault checking. All instructions that load
	 *  or store one or more registers have an alignment check that the
	 *  address being accessed is aligned to the size of the data element(s)
	 *  being accessed.
	 * ---------------------------------------------------------------------
	 */
	sctlr = read_sctlr();
	sctlr |= SCTLR_I_BIT | SCTLR_A_BIT;
	write_sctlr(sctlr);

	/* ---------------------------------------------------------------------
	 * Initialise SCR, setting all fields rather than relying on the hw.
	 *
	 * SCR.SIF: Enabled so that Secure state instruction fetches from
	 *  Non-secure memory are not permitted.
	 * ---------------------------------------------------------------------
	 */
	write_scr(SCR_RESET_VAL | SCR_SIF_BIT);

	/* ---------------------------------------------------------------------
	 * Initialise NSACR, setting all the fields, except for the
	 * IMPLEMENTATION DEFINED field, rather than relying on the hw. Some
	 * fields are architecturally UNKNOWN on reset.
	 *
	 * NSACR_ENABLE_FP_ACCESS: Represents NSACR.cp11 and NSACR.cp10. The
	 *  cp11 field is ignored, but is set to same value as cp10. The cp10
	 *  field is set to allow access to Advanced SIMD and floating point
	 *  features from both Security states.
	 *
	 * NSACR.NSTRCDIS: When system register trace implemented, Set to one
	 *  so that NS System register accesses to all implemented trace
	 *  registers are disabled.
	 *  When system register trace is not implemented, this bit is RES0 and
	 *  hence set to zero.
	 * ---------------------------------------------------------------------
	 */
	nsacr = read_nsacr() & NSACR_IMP_DEF_MASK;
	nsacr |= NSACR_RESET_VAL | NSACR_ENABLE_FP_ACCESS;
	write_nsacr(nsacr);

	/* ---------------------------------------------------------------------
	 * Initialise CPACR, setting all fields rather than relying on hw. Some
	 * fields are architecturally UNKNOWN on reset.
	 *
	 * CPACR.TRCDIS: Trap control for PL0 and PL1 System register accesses
	 *  to trace registers. Set to zero to allow access.
	 *
	 * CPACR_ENABLE_FP_ACCESS: Represents CPACR.cp11 and CPACR.cp10. The
	 *  cp11 field is ignored, but is set to same value as cp10. The cp10
	 *  field is set to allow full access from PL0 and PL1 to floating-point
	 *  and Advanced SIMD features.
	 * ---------------------------------------------------------------------
	 */
	write_cpacr((CPACR_RESET_VAL | CPACR_ENABLE_FP_ACCESS) & ~(TRCDIS_BIT));

#if (ARM_ARCH_MAJOR > 7)
	/* ---------------------------------------------------------------------
	 * Initialise SDCR, setting all the fields rather than relying on hw.
	 *
	 * SDCR.SPD: Disable AArch32 privileged debug. Debug exceptions from
	 *  Secure EL1 are disabled.
	 *
	 * SDCR.SCCD: Set to one so that cycle counting by PMCCNTR is prohibited
	 *  in Secure state. This bit is RES0 in versions of the architecture
	 *  earlier than ARMv8.5, setting it to 1 doesn't have any effect on
	 *  them.
	 *
	 * SDCR.TTRF: Set to one so that access to trace filter control
	 *  registers in non-monitor mode generate Monitor trap exception,
	 *  unless the access generates a higher priority exception when
	 *  trace filter control(FEAT_TRF) is implemented.
	 *  When FEAT_TRF is not implemented, this bit is RES0.
	 * ---------------------------------------------------------------------
	 */
	sdcr = (SDCR_RESET_VAL | SDCR_SPD(SDCR_SPD_DISABLE) | 
		      SDCR_SCCD_BIT) & ~SDCR_TTRF_BIT;
	sdcr |= SDCR_TTRF_BIT;
	write_sdcr(sdcr);

	write_pmcr(PMCR_RESET_VAL | PMCR_DP_BIT | PMCR_LC_BIT | 
		      PMCR_LP_BIT);
#else
	write_pmcr(PMCR_RESET_VAL | PMCR_DP_BIT);
#endif

#if ENABLE_FEAT_DIT
	cpsr = read_cpsr();
	cpsr |= CPSR_DIT_BIT;
	write_cpsr(cpsr);
#endif

	reg_ctx = get_sysregs_ctx(ctx);

	/*
	 * Base the context SCR on the current value, adjust for entry point
	 * specific requirements
	 */
	scr = read_scr();

	scr &= ~(SCR_NS_BIT | SCR_HCE_BIT);

	if (security_state != SECURE) {
		scr |= SCR_NS_BIT;
		/*
		 * Set up SCTLR for the Non-secure context.
		 *
		 * SCTLR.EE: Endianness is taken from the entrypoint attributes.
		 *
		 * SCTLR.M, SCTLR.C and SCTLR.I: These fields must be zero (as
		 *  required by PSCI specification)
		 *
		 * Set remaining SCTLR fields to their architecturally defined
		 * values. Some fields reset to an IMPLEMENTATION DEFINED value:
		 *
		 * SCTLR.TE: Set to zero so that exceptions to an Exception
		 *  Level executing at PL1 are taken to A32 state.
		 *
		 * SCTLR.V: Set to zero to select the normal exception vectors
		 *  with base address held in VBAR.
		 */

		sctlr = spsr != 0U) ? SCTLR_EE_BIT : 0U;
		sctlr |= (SCTLR_RESET_VAL & ~(SCTLR_TE_BIT | SCTLR_V_BIT));
		write_ctx_reg(reg_ctx, CTX_NS_SCTLR, sctlr);
	}

	/*
	 * The target exception level is based on the spsr mode requested. If
	 * execution is requested to hyp mode, HVC is enabled via SCR.HCE.
	 */
	if (spsr) == MODE32_hyp)
		scr |= SCR_HCE_BIT;
	write_ctx_reg(reg_ctx, CTX_SCR, scr);
	write_scr_el3(scr);
}

static void setup_el2_context(unsigned int prev_mode, pcpu_context_t *ctx, user_data_t *process_data)
{
	unsigned int security_state;

	unsigned int secure = BIT(SECURE), non_secure = BIT(NON_SECURE);
	unsigned int mask = secure | non_secure;

	security_state = process_data->base.mode & mask;

	(void) prev_mode;

	if (security_state != NON_SECURE)
		return;
	
	/*
	 * Set the NS bit to access NS copies of certain banked
	 * registers
	 */
	write_scr(read_scr() | SCR_NS_BIT);
	isb();

	/*
	 * Hyp / PL2 present but unused, need to disable safely.
	 * HSCTLR can be ignored in this case.
	 *
	 * Set HCR to its architectural reset value so that
	 * Non-secure operations do not trap to Hyp mode.
	 */
	write_hcr(HCR_RESET_VAL);

	/*
	 * Set HCPTR to its architectural reset value so that
	 * Non-secure access from EL1 or EL0 to trace and to
	 * Advanced SIMD and floating point functionality does
	 * not trap to Hyp mode.
	 */
	write_hcptr(HCPTR_RESET_VAL);

	/*
	 * Initialise CNTHCTL. All fields are architecturally
	 * UNKNOWN on reset and are set to zero except for
	 * field(s) listed below.
	 *
	 * CNTHCTL.PL1PCEN: Disable traps to Hyp mode of
	 *  Non-secure EL0 and EL1 accessed to the physical
	 *  timer registers.
	 *
	 * CNTHCTL.PL1PCTEN: Disable traps to Hyp mode of
	 *  Non-secure EL0 and EL1 accessed to the physical
	 *  counter registers.
	 */
	write_cnthctl(CNTHCTL_RESET_VAL |
			PL1PCEN_BIT | PL1PCTEN_BIT);

	/*
	 * Initialise CNTVOFF to zero as it resets to an
	 * IMPLEMENTATION DEFINED value.
	 */
	write64_cntvoff(0);

	/*
	 * Set VPIDR and VMPIDR to match MIDR_EL1 and MPIDR
	 * respectively.
	 */
	write_vpidr(read_midr());
	write_vmpidr(read_mpidr());

	/*
	 * Initialise VTTBR, setting all fields rather than
	 * relying on the hw. Some fields are architecturally
	 * UNKNOWN at reset.
	 *
	 * VTTBR.VMID: Set to zero which is the architecturally
	 *  defined reset value. Even though EL1&0 stage 2
	 *  address translation is disabled, cache maintenance
	 *  operations depend on the VMID.
	 *
	 * VTTBR.BADDR: Set to zero as EL1&0 stage 2 address
	 *  translation is disabled.
	 */
	write64_vttbr(VTTBR_RESET_VAL &
		~((VTTBR_VMID_MASK << VTTBR_VMID_SHIFT)
		| (VTTBR_BADDR_MASK << VTTBR_BADDR_SHIFT)));

	/*
	 * Initialise HDCR, setting all the fields rather than
	 * relying on hw.
	 *
	 * HDCR.HPMN: Set to value of PMCR.N which is the
	 *  architecturally-defined reset value.
	 *
	 * HDCR.HLP: Set to one so that event counter
	 *  overflow, that is recorded in PMOVSCLR[0-30],
	 *  occurs on the increment that changes
	 *  PMEVCNTR<n>[63] from 1 to 0, when ARMv8.5-PMU is
	 *  implemented. This bit is RES0 in versions of the
	 *  architecture earlier than ARMv8.5, setting it to 1
	 *  doesn't have any effect on them.
	 *  This bit is Reserved, UNK/SBZP in ARMv7.
	 *
	 * HDCR.HPME: Set to zero to disable EL2 Event
	 *  counters.
	 */
#if (ARM_ARCH_MAJOR > 7)
	write_hdcr((HDCR_RESET_VAL | HDCR_HLP_BIT |
		   ((read_pmcr() & PMCR_N_BITS) >>
		    PMCR_N_SHIFT)) & ~HDCR_HPME_BIT);
#else
	write_hdcr((HDCR_RESET_VAL |
		   ((read_pmcr() & PMCR_N_BITS) >>
		    PMCR_N_SHIFT)) & ~HDCR_HPME_BIT);
#endif
	/*
	 * Set HSTR to its architectural reset value so that
	 * access to system registers in the cproc=1111
	 * encoding space do not trap to Hyp mode.
	 */
	write_hstr(HSTR_RESET_VAL);
	/*
	 * Set CNTHP_CTL to its architectural reset value to
	 * disable the EL2 physical timer and prevent timer
	 * interrupts. Some fields are architecturally UNKNOWN
	 * on reset and are set to zero.
	 */
	write_cnthp_ctl(CNTHP_CTL_RESET_VAL);
	isb();

	write_scr(read_scr() & ~SCR_NS_BIT);
	isb();
}


static void setup_el1_context(unsigned int prev_mode, pcpu_context_t *ctx, user_data_t *process_data)
{
	unsigned int security_state;

	unsigned int secure = BIT(SECURE), non_secure = BIT(NON_SECURE);
	unsigned int mask = secure | non_secure;

	security_state = process_data->base.mode & mask;

	if (security_state != NON_SECURE)
		return;

	uint32_t hsctlr;
	/* hyp */
	if ((read_id_pfr1() &
		(ID_PFR1_VIRTEXT_MASK << ID_PFR1_VIRTEXT_SHIFT)) != 0U && prev_mode == MODE32_mon) {

		/* Use SCTLR value to initialize HSCTLR */
		hsctlr = read_ctx_reg(get_sysregs_ctx(ctx),
					 CTX_NS_SCTLR);
		hsctlr |= HSCTLR_RES1;
		/* Temporarily set the NS bit to access HSCTLR */
		write_scr(read_scr() | SCR_NS_BIT);
		/*
		 * Make sure the write to SCR is complete so that
		 * we can access HSCTLR
		 */
		isb();
		write_hsctlr(hsctlr);
		isb();
		
		write_scr(read_scr() & ~SCR_NS_BIT);
		isb();
	}
}

