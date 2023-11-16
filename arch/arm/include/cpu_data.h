/*
 * Copyright (c) 2014-2021, Arm Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef CPU_DATA_H
#define CPU_DATA_H

#include <platform_def.h>	/* CACHE_WRITEBACK_GRANULE required */
#include <exp_desc.h>


#define CPU_DATA_CONTEXT_NUM		2
#define CPU_STACK_OFFSET 		0x8 * CPU_DATA_CONTEXT_NUM
#define CPU_STACK_SIZE			0x8
#define CPU_PROCESS_OFFSET		(CPU_STACK_OFFSET + CPU_STACK_SIZE)
#define CPU_PROCESS_SIZE		0x8
#define CPU_DATA_CPU_OPS_PTR		(CPU_PROCESS_OFFSET + CPU_PROCESS_SIZE)

#define CPU_DATA_CRASH_BUF_OFFSET	(0x8 + CPU_DATA_CPU_OPS_PTR)
/* need enough space in crash buffer to save 8 registers */
#define CPU_DATA_CRASH_BUF_SIZE		64

#if CRASH_REPORTING
#define CPU_DATA_CRASH_BUF_END		(CPU_DATA_CRASH_BUF_OFFSET + \
						CPU_DATA_CRASH_BUF_SIZE)
#else
#define CPU_DATA_CRASH_BUF_END		CPU_DATA_CRASH_BUF_OFFSET
#endif

/* pcpu_data size is the data size rounded up to the platform cache line size */
#define CPU_DATA_SIZE			(((CPU_DATA_CRASH_BUF_END + \
					CACHE_WRITEBACK_GRANULE - 1) / \
						CACHE_WRITEBACK_GRANULE) * \
							CACHE_WRITEBACK_GRANULE)
#ifndef __ASSEMBLER__

#include <assert.h>
#include <stdint.h>
#include <arch_helpers.h>
#include <cassert.h>
#include <platform_def.h>

/* Offsets for the pcpu_data structure */

#if PLAT_PCPU_DATA_SIZE
#define CPU_DATA_PLAT_PCPU_OFFSET	__builtin_offsetof \
		(pcpu_data_t, platform_cpu_data)
#endif

#define SECURE 0
#define NON_SECURE 1
#define MONITOR_K 2
#define HYPERVISOR_K 3
#define SUPERVISER_K 4
#define ADMINISTRATOR_K 5
#define HYPERVISOR_U 6
#define SUPERVISER_U 7
#define ADMINISTRATOR_U 8

#define sec_state_is_valid(s) (((s) == SECURE) || ((s) == NON_SECURE))

typedef enum context_pas {
	CPU_CONTEXT_SECURE = 0,
	CPU_CONTEXT_NS,
	CPU_CONTEXT_NUM
} context_pas_t;

/*******************************************************************************
 * Function & variable prototypes
 ******************************************************************************/

/*******************************************************************************
 * Cache of frequently used per-cpu data:
 *   Pointers to non-secure, realm, and secure security state contexts
 *   Address of the crash stack
 * It is aligned to the cache line boundary to allow efficient concurrent
 * manipulation of these pointers on different cpus
 *
 * The data structure and the _cpu_data accessors should not be used directly
 * by components that have per-cpu members. The member access macros should be
 * used for this.
 ******************************************************************************/

/* Execution Residency Type 
 * 1. PCPU
 * 2. VCPU
 */
/* Execution entity type 
 * 1. kernel - monitor(3),    hypervisor(2), superviser(1),    administrator(0)
 * 2. user -   hypervisor(2), superviser(1), administrator(0), administrator(0)
 * 3. monitor(3) - Transfer stations in different worlds
 */
/* Execution Residency Data  
 * 1. global - sysreg .etc
 * 2. temporary - gpreg .etc
 */
 
/* kernel(EET)|kernel thread > pcpu data(ERD)
 * pcpu_context_t - ERD type
 * context based on the scope managed by the kernel, such as armv8:
 * 1. monitor(3) - el3 sysreg + gpreg
 * 2. hypervisor(2) - el2 sysreg + gpreg
 * 3. superviser(1) - el1 sysreg + gpreg
 * 4. administrator(0) - gpreg
 */
/* MPcore */
typedef struct pcpu_data { // kernel_data is THIS!!!
	/* pcpu context - for setup context */
	world_data_t *world_process[CPU_CONTEXT_NUM];
	uintptr_t cpu_stack;
	uintptr_t user_process; /* user_data_t <current> */
	/* cpu opeator */
	uintptr_t cpu_ops_ptr;
	/* cpu carsh */
#if CRASH_REPORTING
	u_register_t crash_buf[CPU_DATA_CRASH_BUF_SIZE >> 3];
#endif
	/* platform self defined data */
#if PLAT_PCPU_DATA_SIZE
	uint8_t platform_cpu_data[PLAT_PCPU_DATA_SIZE];
#endif	
	/* exception handler data */
	pe_exp_data_t *exp_cpu_data;
} __aligned(CACHE_WRITEBACK_GRANULE) pcpu_data_t; 

typedef enum  class_eet {
	KERNEL_CLASS,
	USER_CLASS,
	CLASS_EET_NUM
} class_eet_t;

typedef enum  user_subclass {
	IMAGE_CLASS,
	SIGNAL_CLASS,
	THREAD_CLASS,
	THREADX_CLASS,
	VM_CLASS,
	WORKQUEUE_CLASS,
	LARGED_CLASS,
	CB_CLASS,
	HOOK_CLASS,
	DISTRIBUTOR_CLASS,
	USER_SUBCLASS_NUM
} user_subclass_t;

typedef enum  kernel_subclass {
	IMAGE_CLASS,
	EXCEPTION_CLASS,
	IRQ_CLASS,
	WORKQUEUE_CLASS,
	LARGED_CLASS,
	CB_CLASS,
	HOOK_CLASS,
	DISTRIBUTOR_CLASS,
	KERNEL_SUBCLASS_NUM
} kernel_subclass_t;
	
typedef struct cpu_data_ops {
	void (*setup)(struct pcpu_context *, struct process_data *); // setup for next EL
	/* neuro is brige of current and next */
	void (*next_setup)(unsigned int, struct pcpu_context *, struct process_data *);
} cpu_data_ops_t;

typedef struct process_data_ops {
	void (*save)(unsigned int, struct pcpu_context *, struct process_data *); // secure state
	void (*restore)(unsigned int, struct pcpu_context *, struct process_data *);
} process_data_ops_t;


/* Base Class */
typedef struct process_data {
	/* MUST first */
	/* logical cpu context - for switch context */
	logical_cpu_context_t cpu_context;
	/* The same class can reuse context and stack and page table
	 * class(8), subclass(8), concurrency&affinity(16+[32]), max concurrency == core number 
	 */
	/* The executing entity is PROCESS, PER PROCESS, or NEURO, PERCPU 
	 * So, context == &kernel_percpu_data[] OR context == &process_pcpu 
	 * (Assuming a process can only run on one core, So,
	 * If there are multiple PROCESS on a core, a fixed average workload
	 * can be set in advance for each PROCESS, for high-volume task, 
	 * "distribution-induction" algorithm can be used)
	 * stack == &kernel_stacks[] OR stack == &process_pcpu_stack
	 */
	/* class         		context[0]                      context[1]
	 * kernel			pcpu data			NULL	
	 * user|kernel-thread		user-data			vcpu(hyp)|NULL
	 */ 	 
	uintptr_t class;

	/* record the process configuration 
	 * 0: secure world(k)
	 * 1: non-secure world(k)
	 * 2: monitor(k) x 
	 * 3: hypervisor(k) x
	 * 4: superviser(k) x
	 * 5: administrator(k) x
	 * 6: hypervisor(u)
	 * 7: superviser(u)
	 * 8: administrator(u)
	 */
	unsigned int mode;	
	/* entrypoint/function/image PC, such as:
	 * 0. _start[] - EET class (kernel/user), subclass image
	 * 1. exception/irq handler - EET class kernel entrypoint, subclass exception/irq
	 * 2. signal handler - EET class user entrypoint, subclass signal
	 * 3. thread/threadX handler - EET class (kernel/user), subclass thread/threadX
	 * 4. vm handler - EET class user entrypoint, subclass vm
	 * 5. workqueue handler - EET class kernel entrypoint, subclass workqueue
	 * 6. larged handler - EET class kernel entrypoint, subclass larged
	 * 7. cb/hook/Distributor - EET class kernel entrypoint, subclass cb/hook/Distributor
	 */
	const uintptr_t handler_entry;	
	/* 
	 * 1. Initial setup environment 
	 * (if switching between different worlds and switching between el2/el1/el0 for each world)
	 * 2. Save/restore environment for switch .
	 */
	/* When performing entity switching, the "passive principle" is adopted for saving and
	 * restoring the context, which is based on the context of the person being switched
	 */
	
	const process_data_ops_t *data_ops_ptr;	
} process_data_t;

/* Derived Class of 'process_data_t' */
/* world switch needs the logical and physics context as temp. */
typedef struct world_data {
	/* MUST first */
	process_data_t base;
	pcpu_context_t *extra; /* reference to 'kernel_pcpu_context' */
} __aligned(CACHE_WRITEBACK_GRANULE) world_data_t;

/* user-hyp(EET) > vcpu data(ERD)
 * TBD pcpu_context_t and vcpu_context_t
 * TBD other need .etc
 */
typedef pcpu_context_t  vcpu_context_t;
typedef struct vcpu_data {
	/* pcpu context - for setup context */
	vcpu_context_t vcpu_context;
} __aligned(CACHE_WRITEBACK_GRANULE) vcpu_data_t;


/* user(EET) > user data(ERD)
 * logical_cpu_context_t - ERD type
 * context according to user switchable settings
 * such as gpreg
 */
typedef struct user_data {
	/* MUST first */
	process_data_t base;
#ifdef CONFIG_ARM_VCPU_SUPPORT
	vcpu_data_t vcpu_data;
#endif
	uintptr_t stack;
	/* page table memory entry, such as kernel:
	 * vspace == kernel_kvspace
	 */
	const uintptr_t vspace;
} __aligned(CACHE_WRITEBACK_GRANULE) user_data_t;

/* Derived Class of 'user_data_t' */
typedef struct utcb {
	struct process_data *process_data;
} __aligned(CACHE_WRITEBACK_GRANULE) utcb_t;


/* switch context 
 * 1. user->user,kernel, user-k, k-sync(user) - both context and stack
 * 2. user-k->user-k, k-sync, user, kernel - both context and stack
 * 3. k-sync->user, user-k, kernel, k-sync - both context and stack
 * 4. kernel - top - no context, only stack
 * 5. world ~ world, two worlds can be in same core OR differnet core
 */

/* SP_EL0 - stack address <-> handler
 * SP_ELX - context address <-> process
 */

/* Here, it is necessary to design a memory management function specifically for 
 * kernel objects to ensure that kernel objects of the same type are grouped into
 * one or consecutive regions as much as possible
 */
extern pcpu_data_t kernel_percpu_data[PLATFORM_CORE_COUNT];
extern user_data_t initserver_data;
extern world_data_t perworld_data[CPU_CONTEXT_NUM]; /* single core */
extern pcpu_context_t kernel_pcpu_context[CPU_CONTEXT_NUM];

#if TODO
/* MMU */
extern pgde_t kernel_pgd[];
extern pude_t kernel_pgu[];
extern pde_t kernel_pd[];
extern pte_t kernel_pt[];
extern vspace_t kernel_kvspace[];
extern asid_pool_t kernel_kasid[]; /* superviser */
#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
extern asid_pool_t kernel_khwasid[]; /* hypervisor */
#endif
/* SMMU */
extern spte_t kernel_spt[];
extern asid_pool_t kernel_sasid[];
#endif


#if CRASH_REPORTING
/* verify assembler offsets match data structures */
CASSERT(CPU_DATA_CRASH_BUF_OFFSET == __builtin_offsetof
	(pcpu_data_t, crash_buf),
	assert_cpu_data_crash_stack_offset_mismatch);
#endif

CASSERT(CPU_DATA_SIZE == sizeof(pcpu_data_t),
		assert_cpu_data_size_mismatch);

CASSERT(CPU_DATA_CPU_OPS_PTR == __builtin_offsetof
		(pcpu_data_t, cpu_ops_ptr),
		assert_cpu_data_cpu_ops_ptr_offset_mismatch);

#ifdef __aarch64__
void init_cpu_data_ptr(void);
/* Return the cpu_data structure for the special CPU. */
struct pcpu_data *_cpu_data_by_index(uint32_t cpu_index);

/* Return the cpu_data structure for the current CPU. */
static inline struct pcpu_data *_cpu_data(void)
{
#ifdef CONFIG_ARM_MONITOR_SUPPORT
	return (pcpu_data *)read_tpidr_el3();
#elif CONFIG_ARM_HYPERVISOR_SUPPORT
	return (pcpu_data *)read_tpidr_el2();
#elif CONFIG_ARM_SUPERVISER_SUPPORT
	return (pcpu_data *)read_tpidr_el1();
#endif
}
#else
struct pcpu_data *_cpu_data_by_index(uint32_t cpu_index);
struct pcpu_data *_cpu_data(void);
#endif
/*
 * Returns the index of the pcpu_context array for the given security state.
 * All accesses to pcpu_context should be through this helper to make sure
 * an access is not out-of-bounds. The function assumes security_state is
 * valid.
 */
static inline context_pas_t get_cpu_context_index(uint32_t security_state)
{
	if (security_state == SECURE) {
		return CPU_CONTEXT_SECURE;
	} else {
		assert(security_state == NON_SECURE);
		return CPU_CONTEXT_NS;
	}
}

/**************************************************************************
 * APIs for initialising and accessing per-cpu data
 *************************************************************************/
#define get_cpu_data(_m)		   _cpu_data()->_m
#define set_cpu_data(_m, _v)		   _cpu_data()->_m = (_v)
#define get_cpu_data_by_index(_ix, _m)	   _cpu_data_by_index(_ix)->_m
#define set_cpu_data_by_index(_ix, _m, _v) _cpu_data_by_index(_ix)->_m = (_v)
/* ((cpu_data_t *)0)->_m is a dummy to get the sizeof the struct member _m */

#define flush_cpu_data(_m)	   flush_dcache_range((uintptr_t)	  \
						&(_cpu_data()->_m), \
						sizeof(((pcpu_data_t *)0)->_m))
#define inv_cpu_data(_m)	   inv_dcache_range((uintptr_t)	  	  \
						&(_cpu_data()->_m), \
						sizeof(((pcpu_data_t *)0)->_m))
#define flush_cpu_data_by_index(_ix, _m)	\
				   flush_dcache_range((uintptr_t)	  \
					 &(_cpu_data_by_index(_ix)->_m),  \
						sizeof(((pcpu_data_t *)0)->_m))



#endif /* __ASSEMBLER__ */
#endif /* CPU_DATA_H */
