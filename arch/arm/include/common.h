/*
 * Copyright (c) 2013-2022, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef COMMON_H
#define COMMON_H

#include <utils.h>

#ifndef __ASSEMBLER__
#include <stddef.h>
#include <stdint.h>
#include <cassert.h>
#endif /* __ASSEMBLER__ */

#define UP	U(1)
#define DOWN	U(0)

/*******************************************************************************
 * Constants to identify the location of a memory region in a given memory
 * layout.
******************************************************************************/
#define TOP	U(0x1)
#define BOTTOM	U(0x0)

/*******************************************************************************
 * Constants to indicate type of exception to the common exception handler.
 ******************************************************************************/
#define SYNC_EXCEPTION_SP_EL0		U(0x0)
#define IRQ_SP_EL0			U(0x1)
#define FIQ_SP_EL0			U(0x2)
#define SERROR_SP_EL0			U(0x3)
#define SYNC_EXCEPTION_SP_ELX		U(0x4)
#define IRQ_SP_ELX			U(0x5)
#define FIQ_SP_ELX			U(0x6)
#define SERROR_SP_ELX			U(0x7)
#define SYNC_EXCEPTION_AARCH64		U(0x8)
#define IRQ_AARCH64			U(0x9)
#define FIQ_AARCH64			U(0xa)
#define SERROR_AARCH64			U(0xb)
#define SYNC_EXCEPTION_AARCH32		U(0xc)
#define IRQ_AARCH32			U(0xd)
#define FIQ_AARCH32			U(0xe)
#define SERROR_AARCH32			U(0xf)

#ifndef __ASSEMBLER__

/*
 * Declarations of linker defined symbols to help determine memory layout of
 * BL images
 */

IMPORT_SYM(uintptr_t, __TEXT_START__,		CODE_BASE);
IMPORT_SYM(uintptr_t, __TEXT_END__,		CODE_END);
IMPORT_SYM(uintptr_t, __RODATA_START__,		RO_DATA_BASE);
IMPORT_SYM(uintptr_t, __RODATA_END__,		RO_DATA_END);
IMPORT_SYM(uintptr_t, __RW_END__,		RW_END);
IMPORT_SYM(uintptr_t, __ROM_END__,		ROM_END);

IMPORT_SYM(uintptr_t, __RAM_START__,	        RAM_BASE);
IMPORT_SYM(uintptr_t, __RAM_END__,		RAM_LIMIT);


/*******************************************************************************
 * Structure used for telling the next BL how much of a particular type of
 * memory is available for its use and how much is already used.
 ******************************************************************************/
typedef struct meminfo {
	uintptr_t total_base;
	size_t total_size;
} meminfo_t;

/*******************************************************************************
 * Function & variable prototypes
 ******************************************************************************/

uintptr_t page_align(uintptr_t value, unsigned dir);

struct mmap_region;

void setup_page_tables(const struct mmap_region *bl_regions,
	   const struct mmap_region *plat_regions);

/*
* Fill a region of normal memory of size "length" in bytes with zero bytes.
*
* WARNING: This function can only operate on normal memory. This means that
*	       the MMU must be enabled when using this function. Otherwise, use
*	       zeromem.
*/
void zero_normalmem(void *mem, u_register_t length);

/*
* Fill a region of memory of size "length" in bytes with null bytes.
*
* Unlike zero_normalmem, this function has no restriction on the type of
* memory targeted and can be used for any device memory as well as normal
* memory. This function must be used instead of zero_normalmem when MMU is
* disabled.
*
* NOTE: When data cache and MMU are enabled, prefer zero_normalmem for faster
*	    zeroing.
*/
void zeromem(void *mem, u_register_t length);

#endif /*__ASSEMBLER__*/

#endif /* COMMON_H */
