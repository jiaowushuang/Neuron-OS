/*
 * Set up the page tables for the generic and platform-specific memory regions.
 * The size of the Trusted SRAM seen by the BL image must be specified as well
 * as an array specifying the generic memory regions which can be;
 * - Code section;
 * - Read-only data section;
 * - Init code section, if applicable
 * - Coherent memory region, if applicable.
 */
void __init setup_page_tables(const mmap_region_t *bl_regions,
			      const mmap_region_t *plat_regions)
{
#if LOG_LEVEL >= LOG_LEVEL_VERBOSE
	const mmap_region_t *regions = bl_regions;

	while (regions->size != 0U) {
		VERBOSE("Region: 0x%lx - 0x%lx has attributes 0x%x\n",
				regions->base_va,
				regions->base_va + regions->size,
				regions->attr);
		regions++;
	}
#endif
	/*
	 * Map the Trusted SRAM with appropriate memory attributes.
	 * Subsequent mappings will adjust the attributes for specific regions.
	 */
	mmap_add(bl_regions);

	/* Now (re-)map the platform-specific memory regions */
	mmap_add(plat_regions);

	/* Create the page tables to reflect the above mappings */
	init_xlat_tables();
}