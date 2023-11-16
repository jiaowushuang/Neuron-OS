#
# Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
#
# SPDX-License-Identifier: GPL-2.0-only
#

cmake_minimum_required(VERSION 3.8.2)


# Helper function for converting a filename to an absolute path. It first converts to
# an absolute path based in the current source directory, and if the results in a file
# that doesn't exist it returns an absolute path based from the binary directory
# This file check is done at generation time and is considered safe as source files
# should not be being added as part of the build step (except into the build directory)
function(get_absolute_source_or_binary output input)
    get_filename_component(test "${input}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    if(NOT EXISTS "${test}")
        get_filename_component(test "${input}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
    endif()
    set("${output}" "${test}" PARENT_SCOPE)
endfunction(get_absolute_source_or_binary)

function(get_absolute_list_source_or_binary output input)
    get_filename_component(test "${input}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_LIST_DIR}")
    if(NOT EXISTS "${test}")
        get_absolute_source_or_binary(test ${input})
    endif()
    set("${output}" "${test}" PARENT_SCOPE)
endfunction()

# Generates a custom command that preprocesses an input file into an output file
# Uses the current compilation settings as well as any EXTRA_FLAGS provided. Can also
# be given any EXTRA_DEPS to depend upon
# A target with the name `output_target` will be generated to create a target based dependency
# for the output file
# Output and input files will be converted to absolute paths based on the following rules
#  * Output is assumed to be in CMAKE_CURRENT_BINARY_DIR
#  * Input is assumed to be in CMAKE_CURRENT_SOURCE_DIR if it resolves to a file that exists
#    otherwise it is assumed to be in CMAKE_CURRENT_BINARY_DIR
function(cppfile output output_target input)
    cmake_parse_arguments(PARSE_ARGV 3 "CPP" "" "EXACT_NAME" "EXTRA_DEPS;EXTRA_FLAGS")
    if(NOT "${CPP_UNPARSED_ARGUMENTS}" STREQUAL "")
        message(FATAL_ERROR "Unknown arguments to cppfile: ${CPP_UNPARSED_ARGUMENTS}")
    endif()
    get_absolute_source_or_binary(input "${input}")
    set(file_copy_name "${output_target}_temp.c")
    # If EXACT_NAME then we copy the input file to the name given by the caller. Otherwise
    # generate a rule for copying the input file to a default name.
    if(CPP_EXACT_NAME)
        set(file_copy_name ${CPP_EXACT_NAME})
    endif()
    add_custom_command(
        OUTPUT ${file_copy_name}
        COMMAND
            ${CMAKE_COMMAND} -E copy ${input} ${CMAKE_CURRENT_BINARY_DIR}/${file_copy_name}
        COMMENT "Creating C input file for preprocessor"
        DEPENDS ${CPP_EXTRA_DEPS} ${input}
    )
    add_custom_target(${output_target}_copy_in DEPENDS ${file_copy_name})
    # Now generate an object library to persuade cmake to just do compilation and not try
    # and link our 'object' files
    add_library(${output_target}_temp_lib OBJECT ${file_copy_name})
    add_dependencies(${output_target}_temp_lib ${output_target}_copy_in)
    # Give the preprecess flag
    target_compile_options(${output_target}_temp_lib PRIVATE -E)
    # Give any other flags from the user
    target_compile_options(${output_target}_temp_lib PRIVATE ${CPP_EXTRA_FLAGS})
    # Now copy from the random name cmake gave our object file into the one desired by the user
    add_custom_command(
        OUTPUT ${output}
        COMMAND
            ${CMAKE_COMMAND} -E copy $<TARGET_OBJECTS:${output_target}_temp_lib> ${output}
        DEPENDS ${output_target}_temp_lib $<TARGET_OBJECTS:${output_target}_temp_lib>
    )
    add_custom_target(${output_target} DEPENDS ${output})
endfunction(cppfile)

function(set_ifndef variable value)
  if(NOT ${variable})
    set(${variable} ${value} ${ARGN} PARENT_SCOPE)
  endif()
endfunction()

# Defines a target for a 'configuration' library, which generates a header based
# upon current state of cache/variables and a provided template string. Additionally
# the generated library gets added to a known global list of 'configuration' libraries
# This list can be used if someone wants all the configurations
function(add_config_library config_dir config_file)
    add_custom_target(${INTERFACE_KCONFIG_TGT} DEPENDS "${config_file}")
    add_library(${INTERFACE_KAUTOCONFIG_TGT} INTERFACE)
    target_include_directories(${INTERFACE_KAUTOCONFIG_TGT} INTERFACE "${config_dir}")
    add_dependencies(${INTERFACE_KAUTOCONFIG_TGT} ${INTERFACE_KCONFIG_TGT} ${config_file})
endfunction(add_config_library)

# This rule tries to emulate an 'autoconf' header. autoconf generated headers
# were previously used as configuration, so this rule provides a way for previous
# applications and libraries to build without modification. The config_list
# is a list of 'prefix' values that have been passed to add_config_library
# This generates a library with ${targetname} that when linked against
# will allow code to simply #include <autoconf.h>
function(generate_autoconf targetname config_list)
    set(link_list "")
    set(gen_list "")
    set(config_header_contents "\n#pragma once\n\n")
    foreach(config IN LISTS config_list)
        list(APPEND link_list "${config}_Config")
        get_generated_files(gens ${config}_Gen)
        list(APPEND gen_list ${gens})
        string(APPEND config_header_contents "#include <${config}/gen_config.h>\n")
    endforeach()
    set(config_dir "${CMAKE_CURRENT_BINARY_DIR}/autoconf")
    set(config_file "${config_dir}/autoconf.h")

    file(GENERATE OUTPUT "${config_file}" CONTENT "${config_header_contents}")
    add_custom_target(${targetname}_Gen DEPENDS "${config_file}")
    add_library(${targetname} INTERFACE)
    target_link_libraries(${targetname} INTERFACE ${link_list})
    target_include_directories(${targetname} INTERFACE "${config_dir}")
    add_dependencies(${targetname} ${targetname}_Gen ${config_file})
    # Set our GENERATED_FILES property to include the GENERATED_FILES of all of our input
    # configurations, as well as the files we generated
    set_property(
        TARGET ${targetname}_Gen
        APPEND
        PROPERTY GENERATED_FILES "${config_file}" ${gen_list}
    )
endfunction(generate_autoconf)

# Macro that allows for appending to a specified list only if all the supplied conditions are true
macro(list_append_if list dep)
    set(list_append_local_list ${${list}})
    set(list_append_valid ON)
    foreach(truth IN ITEMS ${dep})
        string(
            REGEX
            REPLACE
                " +"
                ";"
                truth
                "${truth}"
        )
        if(NOT (${truth}))
            set(list_append_valid OFF)
            break()
        endif()
    endforeach()
    if(list_append_valid)
        list(APPEND list_append_local_list ${ARGN})
    endif()
    set(${list} ${list_append_local_list} PARENT_SCOPE)
endmacro(list_append_if)

# Checks if a file is older than its dependencies
# Will set `stale` to TRUE if outfile doesn't exist,
# or if outfile is older than any file in `deps_list`.
# Will also set `stale` to TRUE if the arguments given to this macro
# change compared to the previous invocation.
# stale: A variable to overwrite with TRUE or FALSE
# outfile: A value that is a valid file path
# deps_list: A variable that holds a list of file paths
# arg_cache: A variable that holds a file to store arguments to
# e.g:
#  set(dts_list "filea" "fileb" "filec")
#  set(KernelDTBPath "${CMAKE_CURRENT_BINARY_DIR}/kernel.dtb")
#  check_outfile_stale(regen ${KernelDTBPath} dts_list ${CMAKE_CURRENT_BINARY_DIR}/dts.cmd
#  if (regen)
#    regen_file(${KernelDTBPath})
#  endif()
#
# The above call will set regen to TRUE if the file referred
# to by KernelDTBPath doesn't exist, or is older than any files
# in KernelDTSIntermediate or if regen, ${KernelDTBPath} and dts_list resolve to different files.
macro(check_outfile_stale stale outfile deps_list arg_cache)
    set(_outfile_command "${stale} ${outfile} ${${deps_list}}")
    if(NOT EXISTS "${arg_cache}")
        set(_prev_command "")
    else()
        file(READ "${arg_cache}" _prev_command)
    endif()
    if(NOT "${_outfile_command}" STREQUAL "${_prev_command}")
        set(${stale} TRUE)
    else()
        set(${stale} FALSE)
    endif()
    if(EXISTS ${outfile} AND NOT ${stale})
        set(${stale} FALSE)
        foreach(dep IN LISTS ${deps_list})
            if("${dep}" IS_NEWER_THAN "${outfile}")
                set(${stale} TRUE)
                break()
            endif()
        endforeach()
    else()
        set(${stale} TRUE)
    endif()
    if(${stale})
        file(WRITE "${arg_cache}" "${_outfile_command}")
    endif()
endmacro()

# This macro only works when cmake is invoked with -P (script mode) on a kernel
# verified configuration. The result is configuring and building a verified kernel.
# CMAKE_ARGC and CMAKE_ARGV# contain command line argument information.
# It runs the following commands to produce kernel.elf and kernel_all_pp.c:
# cmake -G Ninja ${args} -C ${CMAKE_ARGV2} ${CMAKE_CURRENT_LIST_DIR}/..
# ninja kernel.elf
# ninja kernel_all_pp_wrapper
macro(cmake_script_build_kernel)
    if(NOT "${CMAKE_ARGC}" STREQUAL "")
        set(args "")
        foreach(i RANGE 3 ${CMAKE_ARGC})
            if("${CMAKE_ARGV${i}}" STREQUAL "FORCE")
                # Consume arg and force reinit of build dir by deleting CMakeCache.txt
                file(REMOVE CMakeCache.txt)
                file(REMOVE gcc.cmake)
            else()
                list(APPEND args ${CMAKE_ARGV${i}})
            endif()
        endforeach()
        execute_process(
            COMMAND
                cmake -G Ninja ${args} -C ${CMAKE_ARGV2} ${CMAKE_CURRENT_LIST_DIR}/..
            INPUT_FILE /dev/stdin
            OUTPUT_FILE /dev/stdout
            ERROR_FILE /dev/stderr
        )
        execute_process(
            COMMAND ninja kernel.elf
            INPUT_FILE /dev/stdin
            OUTPUT_FILE /dev/stdout
            ERROR_FILE /dev/stderr
        )
        execute_process(
            COMMAND ninja ${KERNEL_ALL_PP_WARPPER_TGT}
            INPUT_FILE /dev/stdin
            OUTPUT_FILE /dev/stdout
            ERROR_FILE /dev/stderr
        )
        return()
    endif()
endmacro()

# import_kconfig(<prefix> <kconfig_fragment> [<keys>])
#
# Parse a KConfig fragment (typically with extension .config) and
# introduce all the symbols that are prefixed with 'prefix' into the
# CMake namespace. List all created variable names in the 'keys'
# output variable if present.
function(import_kconfig prefix kconfig_fragment)
  # Parse the lines prefixed with 'prefix' in ${kconfig_fragment}
  file(
    STRINGS
    ${kconfig_fragment}
    DOT_CONFIG_LIST
    REGEX "^${prefix}"
    ENCODING "UTF-8"
  )

  foreach (CONFIG ${DOT_CONFIG_LIST})
    # CONFIG could look like: CONFIG_NET_BUF=y

    # Match the first part, the variable name
    string(REGEX MATCH "[^=]+" CONF_VARIABLE_NAME ${CONFIG})

    # Match the second part, variable value
    string(REGEX MATCH "=(.+$)" CONF_VARIABLE_VALUE ${CONFIG})
    # The variable name match we just did included the '=' symbol. To just get the
    # part on the RHS we use match group 1
    set(CONF_VARIABLE_VALUE ${CMAKE_MATCH_1})

    if("${CONF_VARIABLE_VALUE}" MATCHES "^\"(.*)\"$") # Is surrounded by quotes
      set(CONF_VARIABLE_VALUE ${CMAKE_MATCH_1})
    endif()

    set("${CONF_VARIABLE_NAME}" "${CONF_VARIABLE_VALUE}" PARENT_SCOPE)
    list(APPEND keys "${CONF_VARIABLE_NAME}")
  endforeach()

  foreach(outvar ${ARGN})
    set(${outvar} "${keys}" PARENT_SCOPE)
  endforeach()
endfunction()