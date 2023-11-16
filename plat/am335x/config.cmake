
list(APPEND DTS_FILES "scripts/dts/${CONFIG_BOARD}.dts")
    if("${CONFIG_BOARD}" STREQUAL "am335x-boneblack")
        list(APPEND DTS_FILES "plat/am335x/overlay-am335x-boneblack.dts")
    endif()
list(APPEND DTS_FILES "plat/am335x/overlay-am335x.dts")