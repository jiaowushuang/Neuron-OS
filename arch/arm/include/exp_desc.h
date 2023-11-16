/*
 * Copyright (c) 2017-2018, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EXP_DESC_H
#define EXP_DESC_H

#ifndef __ASSEMBLER__

#include <cdefs.h>
#include <stdint.h>
#include <utils.h>

/* Valid priorities set bit 0 of the priority handler. */
#define EXP_PRI_VALID_	BIT(0)

/* Marker for no handler registered for a valid priority */
#define EXP_NO_HANDLER_	(0U | EXP_PRI_VALID_)

/* Extract the specified number of top bits from 7 lower bits of priority */
#define EXP_PRI_TO_IDX(pri, plat_bits) \
	((((unsigned) (pri)) & 0x7fu) >> (7u - (plat_bits)))

/* Install exception priority descriptor at a suitable index */
#define EXP_PRI_DESC(plat_bits, priority) \
	[EXP_PRI_TO_IDX(priority, plat_bits)] = { \
		.exp_handler = EXP_NO_HANDLER_, \
	}

/* Macro for platforms to regiter its exception priorities */
#define EXP_REGISTER_PRIORITIES(priorities, num, bits) \
	const exp_priorities_t exception_data = { \
		.num_priorities = (num), \
		.exp_priorities = (priorities), \
		.pri_bits = (bits), \
	}

/*
 * Priority stack, managed as a bitmap.
 *
 * Currently only supports 32 priority levels, allowing platforms to use up to 5
 * top bits of priority. But the type can be changed to uint64_t should need
 * arise to support 64 priority levels, allowing platforms to use up to 6 top
 * bits of priority.
 */
typedef uint32_t exp_pri_bits_t;

/*
 * Per-PE exception data. The data for each PE is kept as a per-CPU data field.
 * See cpu_data.h.
 */
typedef struct {
	exp_pri_bits_t active_pri_bits;

	/* Priority mask value before any priority levels were active */
	uint8_t init_pri_mask;

	/* Non-secure priority mask value stashed during Secure execution */
	uint8_t ns_pri_mask;
} __aligned(sizeof(uint64_t)) pe_exp_data_t;

typedef int (*exp_handler_t)(uint32_t intr_raw, uint32_t flags, void *handle,
		void *cookie);

typedef struct exp_pri_desc {
	/*
	 * 4-byte-aligned exception handler. Bit 0 indicates the corresponding
	 * priority level is valid. This is effectively of exp_handler_t type,
	 * but left as uintptr_t in order to make pointer arithmetic convenient.
	 */
	uintptr_t exp_handler;
} exp_pri_desc_t;

typedef struct exp_priority_type {
	exp_pri_desc_t *exp_priorities;
	unsigned int num_priorities;
	unsigned int pri_bits;
} exp_priorities_t;

void exp_init(void);
void exp_activate_priority(unsigned int priority);
void exp_deactivate_priority(unsigned int priority);
void exp_register_priority_handler(unsigned int pri, exp_handler_t handler);
void exp_allow_ns_preemption(uint64_t preempt_ret_code);
unsigned int exp_is_ns_preemption_allowed(void);

#endif /* __ASSEMBLER__ */

#endif /* EXP_DESC_H */
