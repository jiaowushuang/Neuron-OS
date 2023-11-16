cmake_minimum_required(VERSION 3.14)

# 生成kconfig
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/generated/kconfig)
set(KCONFIG_GEN_PATH "${CMAKE_CURRENT_BINARY_DIR}/generated/kconfig")
set(KCONFIG_PATH ${WORKSPACE_PATH}/scripts/kconfig)
set(KCONFIG_ROOT_FILES ${WORKSPACE_PATH}/Kconfig)

set(DONTCONFIG ${CMAKE_BINARY_DIR}/.config)
set(KCONFIG_SOURCES_TXT ${KCONFIG_GEN_PATH}/sources.txt)


set(kconfig_target_for_menuconfig
    ${KCONFIG_PATH}/menuconfig.py
)
set(kconfig_target_for_guiconfig
    ${KCONFIG_PATH}/guiconfig.py
)


set(AUTOCONF_H ${KCONFIG_GEN_PATH}/autoconf.h)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${AUTOCONF_H})

# 环境变量设置
set(ENV{srctree}            ${WORKSPACE_PATH})
set(ENV{KERNELVERSION}      ${KERNELVERSION})
set(ENV{KCONFIG_CONFIG}     ${DONTCONFIG})
set(ENV{PYTHON_COMMAND}  ${PYTHON_COMMAND})
set(ENV{ARCH}      ${ARCH_PREFIX})
set(ENV{CPU}      ${CPU_PREFIX})
set(ENV{PLATFORM}      ${PLATFORM_PREFIX})
set(ENV{ARCH_DIR}  ${ARCH_PATH})
set(ENV{SOC_DIR}   ${SOC_PATH})
set(ENV{BOARD_DIR} ${PLAT_PATH})
set(ENV{CMAKE_BINARY_DIR} ${CMAKE_BINARY_DIR})

set(KCONFIG_ENV_SETTINGS
    PYTHON_COMMAND=${PYTHON_COMMAND}
    srctree=${WORKSPACE_PATH}
    KERNELVERSION=${KERNELVERSION}
    KCONFIG_CONFIG=${DONTCONFIG}
    ARCH=$ENV{ARCH}
    CPU=$ENV{CPU}
    PLATFORM=$ENV{PLATFORM}
    ARCH_DIR=$ENV{ARCH_DIR}
    SOC_DIR=$ENV{SOC_DIR}
    BOARD_DIR=$ENV{BOARD_DIR}
    CMAKE_BINARY_DIR=$ENV{CMAKE_BINARY_DIR}
)

foreach(kconfig_target
    menuconfig
    guiconfig
    )
  add_custom_target(
    ${kconfig_target}
    ${CMAKE_COMMAND} -E env
    ${KCONFIG_ENV_SETTINGS}
    ${PYTHON_COMMAND}
    ${kconfig_target_for_${kconfig_target}}
    ${KCONFIG_ROOT_FILES}
    WORKING_DIRECTORY
    ${KCONFIG_GEN_PATH}
    USES_TERMINAL
    )  
endforeach()

set(KCONFIG_PREDEFINED_FILES
    ${KCONFIG_DEF_FILES}
)

execute_process(
  COMMAND
  ${PYTHON_COMMAND}
  ${KCONFIG_PATH}/kconfig.py
  ${KCONFIG_ROOT_FILES}
  ${DONTCONFIG}
  ${AUTOCONF_H}
  ${KCONFIG_SOURCES_TXT}
  ${KCONFIG_PREDEFINED_FILES}
  WORKING_DIRECTORY ${WORKSPACE_PATH}
  # The working directory is set to the app dir such that the user
  # can use relative paths in CONF_FILE, e.g. CONF_FILE=nrf5.conf
  RESULT_VARIABLE error
  )
if(NOT "${error}" STREQUAL "0")
  message(FATAL_ERROR "command failed with return code: ${error}")
endif()

file(STRINGS ${KCONFIG_SOURCES_TXT} parsed_kconfig_sources_list)
# automake if property is old
foreach(kconfig_input
    ${KCONFIG_PREDEFINED_FILES}
    ${DONTCONFIG}
    ${parsed_kconfig_sources_list}
    )
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${kconfig_input})
endforeach()

# Parse the lines prefixed with CONFIG_ in the .config file from Kconfig
import_kconfig(CONFIG_ ${DONTCONFIG})
add_config_library(${KCONFIG_GEN_PATH} ${AUTOCONF_H})

# 生成DTS
include(${WORKSPACE_PATH}/plat/${CONFIG_PLATFORM}/config.cmake)
if(DEFINED DTS_FILES AND (NOT "${DTS_FILES}" STREQUAL ""))
    set(DTS_FILES_TMP "${CMAKE_CURRENT_BINARY_DIR}/kernel.dts")
    set(
        DTB_FILES "${CMAKE_CURRENT_BINARY_DIR}/kernel.dtb"
        CACHE INTERNAL "Location of kernel DTB file"
    )
    set(COMPATIBILITY_OUTPUT_FILE "${CMAKE_CURRENT_BINARY_DIR}/kernel_compat.txt")
    set(DEVICE_OUTPUT_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/dtb/devices_gen.h")
    set(
        PLATFORM_YAML_OUTPUT_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/dtb/platform_gen.yaml"
        CACHE INTERNAL "Location of platform YAML description"
    )
    set(
        PLATFORM_JSON_OUTPUT_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/dtb/platform_gen.json"
        CACHE INTERNAL "Location of platform JSON description"
    )
    set(DTS_CONFIG_FILE "${CMAKE_CURRENT_SOURCE_DIR}/scripts/dts/hardware.yml")
    set(DTS_CONFIG_SCHEMA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/scripts/dts/hardware_schema.yml")

    set(
        DTS_OVERLAY_FILES ""
        CACHE FILEPATH "Provide an additional overlay to append to the selected platform's \
        device tree during build time"
    )
    if(NOT "${DTS_OVERLAY_FILES}" STREQUAL "")
        if(NOT EXISTS ${DTS_OVERLAY_FILES})
            message(FATAL_ERROR "Can't open external overlay file '${DTS_OVERLAY_FILES}'!")
        endif()
        list(APPEND DTS_FILES "${DTS_OVERLAY_FILES}")
        message(STATUS "Using ${DTS_OVERLAY_FILES} overlay")
    endif()

    find_program(DTC_TOOL dtc)
    if("${DTC_TOOL}" STREQUAL "DTC_TOOL-NOTFOUND")
        message(FATAL_ERROR "Cannot find 'dtc' program.")
    endif()
    find_program(STAT_TOOL stat)
    if("${STAT_TOOL}" STREQUAL "STAT_TOOL-NOTFOUND")
        message(FATAL_ERROR "Cannot find 'stat' program.")
    endif()
    mark_as_advanced(DTC_TOOL STAT_TOOL)
    # Generate final DTS based on Linux DTS + overlay[s]
    foreach(entry ${DTS_FILES})
        get_absolute_source_or_binary(dts_tmp ${entry})
        list(APPEND dts_list "${dts_tmp}")
        list(APPEND DTC_INCLUDE_FLAG_FOR_DTS "-include ${dts_tmp}")
    endforeach()

    check_outfile_stale(regen ${DTB_FILES} dts_list ${CMAKE_CURRENT_BINARY_DIR}/dts.cmd)
    if(regen)
        file(REMOVE "${DTS_FILES_TMP}")
        foreach(entry ${dts_list})
            file(READ ${entry} CONTENTS)
            file(APPEND "${DTS_FILES_TMP}" "${CONTENTS}")
        endforeach()
        # Compile DTS to DTB
        execute_process(
            COMMAND
                ${DTC_TOOL} -q -I dts -O dtb -o ${DTB_FILES} ${DTS_FILES_TMP}
            RESULT_VARIABLE error
        )
        if(error)
            message(FATAL_ERROR "Failed to compile DTS to DTB: ${DTB_FILES}")
        endif()
        # The macOS and GNU coreutils `stat` utilities have different interfaces.
        # Check if we're using the macOS version, otherwise assume GNU coreutils.
        # CMAKE_HOST_APPLE is a built-in CMake variable.
        if(CMAKE_HOST_APPLE AND "${STAT_TOOL}" STREQUAL "/usr/bin/stat")
            set(STAT_ARGS "-f%z")
        else()
            set(STAT_ARGS "-c '%s'")
        endif()
        # Track the size of the DTB for downstream tools
        execute_process(
            COMMAND ${STAT_TOOL} ${STAT_ARGS} ${DTB_FILES}
            OUTPUT_VARIABLE DTB_FILES_SIZE
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE error
        )
        if(error)
            message(FATAL_ERROR "Failed to determine DTB_FILES_SIZE: ${DTB_FILES}")
        endif()
        string(
            REPLACE
                "\'"
                ""
                DTB_FILES_SIZE
                ${DTB_FILES_SIZE}
        )
        set(DTB_FILES_SIZE "${DTB_FILES_SIZE}" CACHE INTERNAL "Size of DTB blob, in bytes")
    endif()

    set(deps ${DTB_FILES} ${DTS_CONFIG_FILE} ${DTS_CONFIG_SCHEMA_FILE} ${HARDWARE_GEN_FILE})
    check_outfile_stale(regen ${DEVICE_OUTPUT_FILE} deps ${CMAKE_CURRENT_BINARY_DIR}/gen_header.cmd)
    if(regen)
        # Generate devices_gen header based on DTB
        message(STATUS "${DEVICE_OUTPUT_FILE} is out of date. Regenerating from DTB...")
        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated/dtb/")
        execute_process(
            COMMAND
                ${PYTHON_COMMAND} "${HARDWARE_GEN_FILE}" --dtb "${DTB_FILES}" --compat-strings
                --compat-strings-out "${COMPATIBILITY_OUTPUT_FILE}" --c-header --header-out
                "${DEVICE_OUTPUT_FILE}" --hardware-config "${DTS_CONFIG_FILE}" --hardware-schema
                "${DTS_CONFIG_SCHEMA_FILE}" --yaml --yaml-out "${PLATFORM_YAML_OUTPUT_FILE}" --arch
                "${CONFIG_KERNEL_ARCH}" --addrspace-max "${CONFIG_PADDR_BITS_TOP}" --json --json-out
                "${PLATFORM_JSON_OUTPUT_FILE}"
            RESULT_VARIABLE error
        )
        if(error)
            message(FATAL_ERROR "Failed to generate from DTB: ${DEVICE_OUTPUT_FILE}")
        endif()
    endif()
    file(READ "${COMPATIBILITY_OUTPUT_FILE}" compatibility_strings)


    # Mark all file dependencies as CMake rerun dependencies.
    set(cmake_deps ${deps} ${DTS_FILES_TMP} ${DTS_FILES} ${COMPATIBILITY_OUTPUT_FILE})
    # automake if property is old
    set_property(
        DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        APPEND
        PROPERTY CMAKE_CONFIGURE_DEPENDS ${cmake_deps}
    )
endif()




