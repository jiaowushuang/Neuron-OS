/*
 * Copyright (c) 2014-2016, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <platform_def.h>

#include <cassert.h>
#include <cpu_data.h>

/* The per_cpu_ptr_cache_t space allocation */
pcpu_data_t kernel_percpu_data[PLATFORM_CORE_COUNT];
user_data_t initserver_data;
/*
 * Following arrays will be used for context management.
 * There are 2 instances, for the Secure and Non-Secure contexts.
 */
pcpu_context_t kernel_pcpu_context[CPU_CONTEXT_NUM];
world_data_t perworld_data[CPU_CONTEXT_NUM]; /* single core */



