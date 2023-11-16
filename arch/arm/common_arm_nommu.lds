/*
 * Copyright (c) 2013-2020, ARM Limited and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
 * The .data section gets copied from ROM to RAM at runtime.
 * Its LMA should be 16-byte aligned to allow efficient copying of 16-bytes
 * aligned regions in it.
 * Its VMA must be page-aligned as it marks the first read/write page.
 */
#define DATA_ALIGN	16

#include <common.ld.h>
#include <lib/xlat_tables/xlat_tables_defs.h>

#define __ASSEMBLER__

OUTPUT_FORMAT(PLATFORM_LINKER_FORMAT)
OUTPUT_ARCH(PLATFORM_LINKER_ARCH)
ENTRY(_start)

MEMORY {
    ROM (rx): ORIGIN = RO_BASE, LENGTH = RO_LIMIT - RO_BASE
    RAM (rwx): ORIGIN = RW_BASE, LENGTH = RW_LIMIT - RW_BASE
}

SECTIONS
{
    . = RO_BASE;
    ASSERT(. == ALIGN(PAGE_SIZE),
           "RO_BASE address is not aligned on a page boundary.")


    .text . : {
        __TEXT_START__ = .;
        *entrypoint.o(.text*)
        *(SORT_BY_ALIGNMENT(.text*))
        *(.vectors)
        . = ALIGN(PAGE_SIZE);
        __TEXT_END__ = .;
     } >ROM

     /* .ARM.extab and .ARM.exidx are only added because Clang need them */
     .ARM.extab . : {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
     } >ROM

     .ARM.exidx . : {
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
     } >ROM

    .rodata . : {
        __RODATA_START__ = .;
        *(SORT_BY_ALIGNMENT(.rodata*))

	RODATA_COMMON

        /*
         * No need to pad out the .rodata section to a page boundary. Next is
         * the .data section, which can mapped in ROM with the same memory
         * attributes as the .rodata section.
         *
         * Pad out to 16 bytes though as .data section needs to be 16 byte
         * aligned and lld does not align the LMA to the aligment specified
         * on the .data section.
         */
        __RODATA_END__ = .;
         . = ALIGN(16);
    } >ROM

    ASSERT(__CPU_OPS_END__ > __CPU_OPS_START__,
           "cpu_ops not defined for this platform.")

    . = RW_BASE;
    ASSERT(RW_BASE == ALIGN(PAGE_SIZE),
           "RW_BASE address is not aligned on a page boundary.")

    DATA_SECTION >RAM AT>ROM
    __DATA_RAM_START__ = __DATA_START__;
    __DATA_RAM_END__ = __DATA_END__;

    STACK_SECTION >RAM
    BSS_SECTION >RAM
    XLAT_TABLE_SECTION >RAM

    __RAM_START__ = ADDR(.data);
    __RAM_END__ = .;

    __DATA_ROM_START__ = LOADADDR(.data);
    __DATA_SIZE__ = SIZEOF(.data);

    /*
     * The .data section is the last PROGBITS section so its end marks the end
     * of actual content in Trusted ROM.
     */
    __ROM_END__ =  __DATA_ROM_START__ + __DATA_SIZE__;
    ASSERT(__ROM_END__ <= RO_LIMIT,
           " ROM content has exceeded its limit.")

    __BSS_SIZE__ = SIZEOF(.bss);

    ASSERT(. <= RW_LIMIT, "RW section has exceeded its limit.")
}
