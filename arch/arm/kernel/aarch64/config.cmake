cmake_minimum_required(VERSION 3.14)

add_sources(
    DEP ""
    PREFIX arch/arm/64
    CFILES
        c_traps.c
        cache.c
        fpu.c
        gic.c
        idle.c
        mmu.c
        smmu.c
        smp.c
        thread.c 
    ASMFILES
        head.S  
        tlb.S        
        traps.S        
)