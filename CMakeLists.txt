# 指定版本
cmake_minimum_required(VERSION 3.13...3.21) # CMAKE_VERSION

# 导入内建库
include(CheckCCompilerFlag)
include(CheckCXXCompilerFlag)

# 设置输入输出变量（全局类）
# 路径类，构建目录，安装目录，工程目录，脚本目录
set(WORKSPACE_PATH "${CMAKE_CURRENT_LIST_DIR}")

set(CMAKE_PATH "${CMAKE_CURRENT_LIST_DIR}/scripts/cmake")
set(KCONFIG_PATH "")
set(COMMAND_PATH "")
set(GENFILE_PATH "")

# 路径名称
set(SOC_PATH ${WORKSPACE_PATH}/soc)
set(ARCH_PATH ${WORKSPACE_PATH}/arch)
set(PLAT_PATH ${WORKSPACE_PATH}/plat)

# 文件类，源文件，头文件，二进制文件，cmake/py/dts/shell等脚本文件

set(C_FILES "")
set(ASM_FILES "")
set(LINKER_FILES "")
set(DTS_FILES "")
set(KCONFIG_DEF_FILES "")
set(KCONFIG_ROOT_FILES "")
set(KERNEL_LINKER_FILE "")

# 名称类，目标名，依赖名，属性名(CMAKE_前缀)，前缀/后缀，cmake控制流条件变量，命令名，脚本参数

set(KERNEL_C_WARPPER_TGT "kernel_c_warpper_tgt")
set(KERNEL_ALL_PRUNE_TGT "kernel_all_prune_tgt")
set(KERNEL_ALL_WARPPER_TGT "kernel_all_warpper_tgt")
set(KERNEL_ALL_LINKER_WARPPER_TGT "kernel_all_linker_warpper_tgt")
set(KERNEL_ALL_PP_WARPPER_TGT "kernel_all_pp_warpper_tgt")
set(INTERFACE_TGT "interface_tgt")
set(INTERFACE_GEN_TGT "interface_gen_tgt")
set(INTERFACE_KCONFIG_TGT "interface_kconfig_tgt")
set(INTERFACE_KAUTOCONFIG_TGT "interface_kautoconfig_tgt")

# 命令名称
set(PYTHON_COMMAND "python3" CACHE INTERNAL "python command name")
# 前缀名称
set(PLATFORM_PREFIX "" CACHE STRING "plat name") 
set(CPU_PREFIX "" CACHE STRING "soc name") 
set(ARCH_PREFIX "" CACHE STRING "arch name") 

# 直接导入辅助脚本
include(${CMAKE_PATH}/internal.cmake)
include(${CMAKE_PATH}/version.cmake)

# 顶层项目名称
project(
  neuro
  VERSION ${PROJECT_VERSION}
  DESCRIPTION ""
  LANGUAGES C ASM)

# 导入外部库


# 搜索辅助脚本名
function(find_scripts var file)
    find_new_file("${var}" "${file}" PATHS scripts/cmake scripts/command scripts/gen)
endfunction(find_scripts)

function(find_defconfig var file)
    find_new_file("${var}" "${file}" PATHS ${ARGV})
endfunction(find_defconfig)


# 搜索文件，设置文件类变量
find_scripts(CPP_GEN_FILE cpp_gen.sh)
find_scripts(HARDWARE_GEN_FILE hardware_gen.py)
find_scripts(CIRCULAR_INCLUDES_FILE circular_includes.py)
# 间接导出脚本名变量和导入辅助脚本
find_scripts(GLOBAL_FLAGS_FILE flags.cmake)

find_scripts(GLOBAL_HELPERS_FILE helpers.cmake)
include(${GLOBAL_HELPERS_FILE})

# 预处理命令-生成cmake变量 dts/kconfig
# 搜索默认Kconfig
find_defconfig(PLAT_DEFCONFIG_FILE ${PLATFORM_PREFIX}_defconfig ${PLAT_PATH}/*) # am335x-boneblack
# find_defconfig(SOC_DEFCONFIG_FILE ${CPU_PREFIX}_defconfig ${SOC_PATH}/*) # cortex-a9
# find_defconfig(ARCH_DEFCONFIG_FILE ${ARCH_PREFIX}_defconfig ${ARCH_PATH}/*) # ARCH_PREFIX=arm
set(KCONFIG_DEF_FILES ${PLAT_DEFCONFIG_FILE}) # ${ARCH_DEFCONFIG_FILE} ${SOC_DEFCONFIG_FILE}
include(config.cmake)

# 配置工具链
if("${TRIPLE}" STREQUAL "")
    set(TOOLCHAIN_FILES ${CMAKE_PATH}/gcc.cmake)
else()
    set(TOOLCHAIN_FILES ${CMAKE_PATH}/llvm.cmake)
endif()
include(${TOOLCHAIN_FILES})

# 调用一级子目录的所有cmake文件
file(GLOB result ${WORKSPACE_PATH}/*/config.cmake)
list(SORT result)
foreach(file ${result})
  include("${file}")
endforeach()

# 调用二级子目录的所有cmake文件
include(${WORKSPACE_PATH}/arch/${CONFIG_ARCH}/config.cmake)
include(${WORKSPACE_PATH}/soc/${CONFIG_CPU}/config.cmake)


# 通用编译选项
# Define default global flag information so that users can compile with the same basic architecture
# flags as the kernel
# Kconfig->cmake var

# CONFIG_ARCH "arm/riscv"
# CONFIG_CPU "cortex-a9"
# CONFIG_ARCH_X86,ARM(CONFIG_ARMV<armv8-a, armv7ve, armv7-a>, CONFIG_FEAT<+crc>), RISCV
# CONFIG_PLATFORM "am335x"
# CONFIG_BOARD "am335x-boneblack"
# CONFIG_KERNEL_BITS 32/64
# CONFIG_TOOLCHAIN_GCC/LLVM
# CONFIG_HAVE_FPU
# CONFIG_OPTIMISATION(-O0,-O1, -O2,-O3,-Os)
# CONFIG_OPTIMISATION_CLONE
# CONFIG_WHOLE_PROGRAM
# CONFIG_DEBUG_BUILD
# CONFIG_KERNEL_ARCH 
# CONFIG_CROSS_PREFIX
# CONFIG_PADDR_BITS_TOP (1<<40)
if(CONFIG_ARCH_X86)
    if(${CONFIG_ARCH_X86_MICRO} STREQUAL generic)
        set(BUILD_ARCH "-mtune=generic")
    else()
        set(BUILD_ARCH "-march=${CONFIG_ARCH_X86_MICRO}")
    endif()
    if(CONFIG_KERNEL_BITS STREQUAL 64)
        if(NOT CONFIG_TOOLCHAIN_LLVM)
            string(APPEND ASM_COMMON_FLAGS " -Wa,--64")
        endif()
        string(APPEND C_COMMON_FLAGS " -m64")
    else()
        if(NOT CONFIG_TOOLCHAIN_LLVM)
            string(APPEND ASM_COMMON_FLAGS " -Wa,--32")
        else()
            string(APPEND ASM_COMMON_FLAGS " -m32")
        endif()
        string(APPEND C_COMMON_FLAGS " -m32")
    endif()
endif()
if(CONFIG_ARCH_ARM)
    set(ARM_MARCH "${CONFIG_ARMV}${CONFIG_FEAT}")
    string(APPEND C_COMMON_FLAGS " -march=${ARM_MARCH}")
    string(APPEND ASM_COMMON_FLAGS " -march=${ARM_MARCH}")
    # Explicitly request ARM instead of THUMB for compilation. This option is not
    # relevant on aarch64
    if(CONFIG_KERNEL_BITS STREQUAL 32)
        string(APPEND C_COMMON_FLAGS " -marm")
    endif()
endif()
if(CONFIG_ARCH_RISCV)
    if(CONFIG_KERNEL_BITS STREQUAL 64)
        if(CONFIG_HAVE_FPU)
            string(APPEND COMMON_FLAGS " -march=rv64imafdc")
            string(APPEND COMMON_FLAGS " -mabi=lp64d")
        else()
            string(APPEND COMMON_FLAGS " -march=rv64imac")
            string(APPEND COMMON_FLAGS " -mabi=lp64")
        endif()
    else()
        string(APPEND COMMON_FLAGS " -march=rv32imac")
        string(APPEND COMMON_FLAGS " -mabi=ilp32")
    endif()
endif()
string(APPEND COMMON_FLAGS " ${BUILD_ARCH}")

string(APPEND COMMON_FLAGS " -D__KERNEL_${CONFIG_KERNEL_BITS}__")

set(
    BASE_ASM_FLAGS "${ASM_COMMON_FLAGS} ${COMMON_FLAGS}"
    CACHE INTERNAL "Default ASM flags for compilation \
    (subset of flags used by the kernel build)"
)
set(
    BASE_C_FLAGS "${C_COMMON_FLAGS} ${COMMON_FLAGS}"
    CACHE INTERNAL "Default C flags for compilation \
    (subset of flags used by the kernel)"
)
set(
    BASE_CXX_FLAGS "${CXX_COMMON_FLAGS} ${C_COMMON_FLAGS} ${COMMON_FLAGS}"
    CACHE INTERNAL "Default CXX flags for compilation"
)
if(CONFIG_ARCH_X86)
    if(CONFIG_KERNEL_BITS STREQUAL 64)
        string(APPEND COMMON_EXE_FLAGS " -Wl,-m -Wl,elf_x86_64")
    else()
        string(APPEND COMMON_EXE_FLAGS " -Wl,-m -Wl,elf_i386")
    endif()
endif()
set(
    BASE_EXE_LINKER_FLAGS "${COMMON_FLAGS} ${COMMON_EXE_FLAGS} "
    CACHE INTERNAL "Default flags for linker an elf binary application"
)

include(${GLOBAL_FLAGS_FILE})

# 内核特定编译选项
macro(set_kernel_special_flags)
    foreach(common_flag IN ITEMS ${ARGV})
        add_compile_options(${common_flag})
        string(APPEND CMAKE_EXE_LINKER_FLAGS " ${common_flag} ")
    endforeach()
endmacro(set_kernel_special_flags)
set_kernel_special_flags(-nostdlib ${CONFIG_OPTIMISATION})

if(NOT CONFIG_OPTIMISATION_CLONE AND (CMAKE_C_COMPILER_ID STREQUAL "GNU"))
    set_kernel_special_flags(-fno-partial-inlining -fno-ipa-cp -fno-ipa-sra)
endif()
if(CONFIG_WHOLE_PROGRAM)
    # KernelFWholeProgram is still an experimental feature and disabled by
    # default. Clarify if the linker step via GCC actually cares about this
    # parameter. There are also the options -flto and -fuse-linker-plugin that
    # might be a more modern approach.
    set_kernel_special_flags(-fwhole-program)
endif()
if(CONFIG_DEBUG_BUILD)
    set_kernel_special_flags(-DDEBUG -g -ggdb)
    # Pretend to CMake that we're a release build with debug info. This is because
    # we do actually allow CMake to do the final link step, so we'd like it not to
    # strip our binary
    set(CMAKE_BUILD_TYPE "RelWithDebInfo")
else()
    set(CMAKE_BUILD_TYPE "Release")
endif()

if(CONFIG_ARCH_X86 AND CONFIG_KERNEL_BITS STREQUAL 64)
    set_kernel_special_flags(-mcmodel=kernel)
endif()
if(CONFIG_ARCH_ARM)
    if(CONFIG_KERNEL_BITS STREQUAL 64)
        set_kernel_special_flags(-mgeneral-regs-only)
        if(
            (CMAKE_C_COMPILER_ID STREQUAL "GNU")
            AND (CMAKE_C_COMPILER_VERSION VERSION_GREATER_EQUAL "10.0.0")
        )
            add_compile_options(-mno-outline-atomics)
        endif()
    else()
        set_kernel_special_flags(-mfloat-abi=soft)
    endif()
endif()
if(CONFIG_ARCH_RISCV)
    set_kernel_special_flags(-mcmodel=medany)
endif()
set_kernel_special_flags(
    # The following options are gcc options, it is unclear if ld options are
    # generated automatically when gcc wraps the linking step and invokes ld.
    -fno-pic -fno-pie
)
if(
  ((CMAKE_C_COMPILER_ID STREQUAL "GNU")
   AND (CMAKE_C_COMPILER_VERSION VERSION_GREATER_EQUAL "10.0.0")
   )
  OR
  ((CMAKE_C_COMPILER_ID STREQUAL "Clang")
    AND (CMAKE_C_COMPILER_VERSION VERSION_GREATER_EQUAL "12.0.0")
  )
)
  #add_compile_options(-mno-outline-atomics)
endif()

add_compile_options(
    -std=c99
    #-----------------------------------
    # Configure warnings
    #-----------------------------------
    -Wall
    -Werror
    -Wstrict-prototypes
    -Wmissing-prototypes
    -Wnested-externs
    -Wmissing-declarations
    -Wundef
    -Wpointer-arith
    -Wno-nonnull
    #-----------------------------------
    # Configure compiler settings.
    #-----------------------------------
    -nostdinc # Do not use any system include paths, only use those given
              # explicitly by the "-I <path>" parameters.
    -ffreestanding # implies "-fno-builtin". Execution will not start at main().
                   # No assumptions about the meaning of function names from the
                   # standard library are made, except for memcpy(), memmove(),
                   # memset() and memcmp(). __builtin_trap() will call abort().
    -fno-stack-protector
    -fno-asynchronous-unwind-tables
    # GCC < 10 and clang < 11 put uninitialized global variables into a 'COMMON'
    # section unless '-fno-common' is specified. The linker will put anything
    # from 'COMMON' as the end of the '.bss' if nothing else is specified in the
    # linker script. Besides making the variable placement look odd, this also
    # tends to waste a page because we puts large aligned block at the end.
    # Eventually, GCC 10 and clang 11 made '-fno-common' the default, see
    # - https://gcc.gnu.org/gcc-10/changes.html
    # - https://releases.llvm.org/11.0.0/tools/clang/docs/ReleaseNotes.html
    -fno-common
)

string(
    APPEND CMAKE_EXE_LINKER_FLAGS
    # set_kernel_special_flags adds "-nostdlib", it's the GCC linker step counterpart
    # for "-ffreestanding" and makes GCC not use the standard system startup
    # files or libraries. This also excludes GCC's helper library libgcc. Any
    # libraries that are to be linked must be specified explicitly. Tests have
    # shown that this parameter doesn't prevent GCC from adding paths from a
    # "-L <path>" argument to the linker invocation for the standard libs, and
    # there seems no option that prevents this apart from providing an entirely
    # different specs file via -specs=<file>. Note that "-Wl,-nostdlib" is not
    # used here, because it is not needed. It makes the linker use library
    # directories specified on the command line only and ignore any SEARCH_DIR
    # set in a linker script. We provide our own linker scripts, and these
    # don't set SEARCH_DIR.
    " -static" # Implies "-no-pie" (and overrides "-pie"). The ld 2.37 docs say
               # "-no-pie" is a linker option, but passing "-Wl,-no-pie" fails.
    " -Wl,--build-id=none" # Ensure reproducible builds
    " -Wl,-n" # Disable page alignment of sections
)
if(CONFIG_ARCH_X86)
    add_compile_options(-mno-mmx -mno-sse -mno-sse2 -mno-3dnow)
endif()

# 收集静态源文件（非生成）
list(SORT C_FILES)
# list(APPEND C_FILE "")
# 收集静态头文件（非生成）
include_directories(
  "include"
)

# 生成接口目标
include_directories($<TARGET_PROPERTY:${INTERFACE_KAUTOCONFIG_TGT},INTERFACE_INCLUDE_DIRECTORIES>)
add_custom_target(
    ${INTERFACE_GEN_TGT}
    DEPENDS
    ${INTERFACE_KCONFIG_TGT}
    ${INTERFACE_KAUTOCONFIG_TGT}
)
add_custom_target(${INTERFACE_TGT} DEPENDS ${INTERFACE_GEN_TGT})

# 生成仅源文件目标
add_custom_command(
    OUTPUT kernel_all.c
    COMMAND
        "${CPP_GEN_FILE}" ${C_FILES} > kernel_all.c
    DEPENDS "${CPP_GEN_FILE}" ${C_FILES}
    COMMENT "Concatenating C files"
    VERBATIM
)
add_custom_target(${KERNEL_C_WARPPER_TGT} DEPENDS kernel_all.c)

# 生成源文件和头文件目标（该目标后续还要修改，例如替换/校验kernel_all_pp_prune.c某些字段，还要生成某些文件）可选
cppfile(
    kernel_all_pp_prune.c
    ${KERNEL_ALL_PRUNE_TGT}
    kernel_all.c
    EXTRA_FLAGS
    -CC
    EXTRA_DEPS
    ${KERNEL_C_WARPPER_TGT}
    ${INTERFACE_TGT}
)

# 生成版本文件
configure_file(version.h.in ${CMAKE_CURRENT_BINARY_DIR}/include/generated/version.h)
# 生成源文件和头文件目标（最终）
set(CPPExtraFlags "-I${CMAKE_CURRENT_BINARY_DIR}/generated")

cppfile(
    kernel_all.i
    ${KERNEL_ALL_WARPPER_TGT}
    kernel_all.c
    EXTRA_DEPS
    ${KERNEL_C_WARPPER_TGT}
    ${INTERFACE_TGT}
    EXTRA_FLAGS
    -CC
    "${CPPExtraFlags}"
    # The circular_includes script relies upon parsing out exactly 'kernel_all_copy.c' as
    # a special case so we must ask cppfile to use this input name
    EXACT_NAME kernel_all_copy.c
)
set_property(SOURCE kernel_all.i PROPERTY LANGUAGE C)

# 搜索链接文件
if(CONFIG_ARCH_ARM)
    set(LINKER_FILES "${ARCH_PATH}/arm/common_arm.lds")
elseif(CONFIG_ARCH_RISCV)
    set(LINKER_FILES "${ARCH_PATH}/riscv/common_riscv.lds")
else()
    set(LINKER_FILES "${PLAT_PATH}/${CONFIG_PLATFORM}/linker.lds")
endif()
set(KERNEL_LINKER_FILE "${CMAKE_CURRENT_BINARY_DIR}/linker.lds_pp")

# 生成源文件和头文件和链接文件目标（最终）
cppfile(
    "${KERNEL_LINKER_FILE}"
    ${KERNEL_ALL_LINKER_WARPPER_TGT}
    "${LINKER_FILES}"
    EXTRA_DEPS
    ${INTERFACE_TGT}
    EXTRA_FLAGS
    -CC
    -P
    "${CPPExtraFlags}"
)

# 删除头文件循环包含
add_custom_command(
    OUTPUT circular_includes_valid
    COMMAND ${CIRCULAR_INCLUDES_FILE} --ignore kernel_all_copy.c < kernel_all.i
    COMMAND touch circular_includes_valid
    DEPENDS ${KERNEL_ALL_WARPPER_TGT} kernel_all.i
)
add_custom_target(circular_includes DEPENDS circular_includes_valid)

# 将生成的最终文件拷贝到某个文件中
add_custom_command(
    OUTPUT kernel_all_pp.c
    COMMAND
        ${CMAKE_COMMAND} -E copy kernel_all.i kernel_all_pp.c
    DEPENDS ${KERNEL_ALL_WARPPER_TGT} kernel_all.i
)

add_custom_target(${KERNEL_ALL_PP_WARPPER_TGT} DEPENDS kernel_all_pp.c)

# 定义最终二进制目标
add_executable(kernel.elf EXCLUDE_FROM_ALL ${ASM_FILES} kernel_all.c)
# 生成的头文件目录
# target_include_directories(kernel.elf PRIVATE ${GENFILE_PATH})
target_include_directories(kernel.elf PRIVATE include)
target_include_directories(kernel.elf PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_link_libraries(kernel.elf PRIVATE ${INTERFACE_KAUTOCONFIG_TGT})
set_property(TARGET kernel.elf APPEND_STRING PROPERTY LINK_FLAGS " -Wl,-T ${KERNEL_LINKER_FILE} ")
set_target_properties(kernel.elf PROPERTIES LINK_DEPENDS "${KERNEL_LINKER_FILE}")
add_dependencies(kernel.elf circular_includes)

# 伪命令
add_custom_target(
  cclean
  COMMAND ${CMAKE_COMMAND} -P ${CMAKE_PATH}/rm.cmake
  # Equivalent to rm -rf build/*
)

# 测试
# Only do these if this is the main project, and not if it is included through add_subdirectory
if(CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME)

  # Optionally set things like CMAKE_CXX_STANDARD, CMAKE_POSITION_INDEPENDENT_CODE here

  # Let's ensure -std=c++xx instead of -std=g++xx
  set(CMAKE_CXX_EXTENSIONS OFF)

  # Let's nicely support folders in IDEs
  set_property(GLOBAL PROPERTY USE_FOLDERS ON)

  # Testing only available if this is the main app
  # Note this needs to be done in the main CMakeLists
  # since it calls enable_testing, which must be in the
  # main CMakeLists.
  include(CTest)

  # Docs only available if this is the main app
  find_package(Doxygen)
  if(Doxygen_FOUND)
    add_subdirectory(manual)
  else()
    message(STATUS "Doxygen not found, not building docs")
  endif()
endif()


# Testing only available if this is the main app
# Emergency override MODERN_CMAKE_BUILD_TESTING provided as well
if((CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME OR MODERN_CMAKE_BUILD_TESTING)
   AND BUILD_TESTING)
  add_subdirectory(tests)
endif()

# 安装头文件和二进制文件
# The following commands setup the install target for copying generated files and
# compilation outputs to an install location: CMAKE_INSTALL_PREFIX.
# CMAKE_INSTALL_PREFIX can be set on the cmake command line.
# The install target is only created if this is the top level project.
# We don't currently support creating install targets if the kernel is
# imported in another project.
if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_CURRENT_SOURCE_DIR}")
    # Install kernel.elf to bin/kernel.elf
    install(TARGETS kernel.elf RUNTIME DESTINATION bin) # ${CMAKE_INSTALL_PREFIX}/bin
    install(
        DIRECTORY
            "${CMAKE_CURRENT_BINARY_DIR}/generated" # ${CMAKE_INSTALL_PREFIX}/libneuro/include
        DESTINATION libneuro/include
        FILES_MATCHING
        PATTERN "*.h"
    )
endif()

