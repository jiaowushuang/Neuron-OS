#
# Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
#
# SPDX-License-Identifier: GPL-2.0-only
#

cmake_minimum_required(VERSION 3.7.2)

function(find_new_file var_name file_name)
    find_file(
        ${var_name} "${file_name}"
        PATHS "${CMAKE_CURRENT_SOURCE_DIR}"
        CMAKE_FIND_ROOT_PATH_BOTH ${ARGV}
    )
    if("${${var_name}}" STREQUAL "${var_name}-NOTFOUND")
        message(FATAL_ERROR "Failed to find required file ${file_name}")
    endif()
    mark_as_advanced(FORCE ${var_name})
endfunction(find_new_file)


# Adds files to the global sources list, but only if the supplied dependencies are met.
# A dependency lists can be specified with DEP and CFILES are added to c_sources whilst
# ASMFILES are added to asm_sources. An PREFIX can be given as path to prefix to each
# C and ASM file given
function(add_sources)
    cmake_parse_arguments(PARSE_ARGV 0 "ADD" "" "DEP;PREFIX" "CFILES;ASMFILES")
    if(NOT "${ADD_UNPARSED_ARGUMENTS}" STREQUAL "")
        message(FATAL_ERROR "Unknown arguments to add_c_sources: ${ADD_UNPARSED_ARGUMENTS}")
    endif()
    # Need to prefix files with the CMAKE_CURRENT_SOURCE_DIR as we use these
    # in custom commands whose working directory is not the source directory
    # Also need to ensure that if an additional prefix wasn't specified by the
    # caller, that we don't add an additional /, as this will screw up file sorting
    if(NOT "${ADD_PREFIX}" STREQUAL "")
        set(ADD_PREFIX "${ADD_PREFIX}/")
    endif()
    set(ADD_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/${ADD_PREFIX}")
    foreach(file IN LISTS ADD_CFILES)
        list(APPEND NEW_C_FILES "${ADD_PREFIX}${file}")
    endforeach()
    foreach(file IN LISTS ADD_ASMFILES)
        list(APPEND NEW_ASM_FILES "${ADD_PREFIX}${file}")
    endforeach()
    list_append_if(C_FILES "${ADD_DEP}" ${NEW_C_FILES})
    list_append_if(ASM_FILES "${ADD_DEP}" ${NEW_ASM_FILES})
endfunction(add_sources)


