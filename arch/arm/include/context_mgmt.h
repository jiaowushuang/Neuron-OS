/*
 * Copyright (c) 2013-2022, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef CONTEXT_MGMT_H
#define CONTEXT_MGMT_H

#include <assert.h>
#include <context.h>
#include <stdint.h>
#include <arch.h>

/* Inline definitions */

/*******************************************************************************
 * This function returns a pointer to the most recent 'pcpu_context' structure
 * for the calling CPU that was set as the context for the specified security
 * state. NULL is returned if no such structure has been specified.
 ******************************************************************************/
static inline void *cm_get_world_context_extra(uint32_t security_state)
{
	assert(sec_state_is_valid(security_state));

	return get_cpu_data(world_process[get_cpu_context_index(security_state)])->extra;
}

static inline void *cm_get_world_context_base(uint32_t security_state)
{
	assert(sec_state_is_valid(security_state));

	return &get_cpu_data(world_process[get_cpu_context_index(security_state)])->base;
}

static inline void *cm_get_world_context(uint32_t security_state)
{
	assert(sec_state_is_valid(security_state));

	return get_cpu_data(world_process[get_cpu_context_index(security_state)]);
}


/*******************************************************************************
 * This function sets the pointer to the current 'pcpu_context' structure for the
 * specified security state for the calling CPU
 ******************************************************************************/
static inline void cm_set_world_context_extra(void *context, uint32_t security_state)
{
	assert(sec_state_is_valid(security_state));

	set_cpu_data(world_process[get_cpu_context_index(security_state)]->extra,
			context);
}

static inline void cm_set_world_context_base(void *context, uint32_t security_state)
{
	assert(sec_state_is_valid(security_state));

	set_cpu_data(world_process[get_cpu_context_index(security_state)]->base,
			context);
}

static inline void cm_set_world_context(void *context, uint32_t security_state)
{
	assert(sec_state_is_valid(security_state));

	set_cpu_data(world_process[get_cpu_context_index(security_state)],
			context);
}

/*******************************************************************************
 * This function returns a pointer to the most recent 'pcpu_context' structure
 * for the CPU identified by `cpu_idx` that was set as the context for the
 * specified security state. NULL is returned if no such structure has been
 * specified.
 ******************************************************************************/
static inline void *cm_get_world_context_extra_by_index(unsigned int cpu_idx,
				unsigned int security_state)
{
	assert(sec_state_is_valid(security_state));

	return get_cpu_data_by_index(cpu_idx,
			world_process[get_cpu_context_index(security_state)])->extra;
}

static inline void *cm_get_world_context_base_by_index(unsigned int cpu_idx,
				unsigned int security_state)
{
	assert(sec_state_is_valid(security_state));

	return &get_cpu_data_by_index(cpu_idx,
			world_process[get_cpu_context_index(security_state)])->base;
}

static inline void *cm_get_world_context_by_index(unsigned int cpu_idx,
				unsigned int security_state)
{
	assert(sec_state_is_valid(security_state));

	return &get_cpu_data_by_index(cpu_idx,
			world_process[get_cpu_context_index(security_state)]);
}

/*******************************************************************************
 * This function sets the pointer to the current 'pcpu_context' structure for the
 * specified security state for the CPU identified by CPU index.
 ******************************************************************************/
static inline void cm_set_world_context_extra_by_index(unsigned int cpu_idx, void *context,
				unsigned int security_state)
{
	assert(sec_state_is_valid(security_state));

	set_cpu_data_by_index(cpu_idx,
			world_process[get_cpu_context_index(security_state)]->extra,
			context);
}

static inline void cm_set_world_context_base_by_index(unsigned int cpu_idx, void *context,
				unsigned int security_state)
{
	assert(sec_state_is_valid(security_state));

	set_cpu_data_by_index(cpu_idx,
			world_process[get_cpu_context_index(security_state)]->base,
			context);
}

static inline void cm_set_world_context_by_index(unsigned int cpu_idx, void *context,
				unsigned int security_state)
{
	assert(sec_state_is_valid(security_state));

	set_cpu_data_by_index(cpu_idx,
			world_process[get_cpu_context_index(security_state)],
			context);
}

uintptr_t cm_get_curr_stack(void);
uintptr_t cm_get_curr_process(void);
/*******************************************************************************
 * Function & variable prototypes
 ******************************************************************************/
void cm_init(void);


#if CTX_INCLUDE_EL2_REGS
void cm_el2_sysregs_context_save(uint32_t security_state);
void cm_el2_sysregs_context_restore(uint32_t security_state);
#endif

#if CTX_INCLUDE_EL1_REGS
void cm_el1_sysregs_context_save(uint32_t security_state);
void cm_el1_sysregs_context_restore(uint32_t security_state);
#endif




#endif /* CONTEXT_MGMT_H */
