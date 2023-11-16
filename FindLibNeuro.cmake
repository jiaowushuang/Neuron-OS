set(KERNEL_PATH "${CMAKE_CURRENT_LIST_DIR}" CACHE STRING "")
set(KERNEL_HELPERS_PATH "${CMAKE_CURRENT_LIST_DIR}/scripts/cmake/helpers.cmake" CACHE STRING "")
mark_as_advanced(KERNEL_PATH KERNEL_HELPERS_PATH)

macro(import_neuro_kernel)
    add_subdirectory(${KERNEL_PATH} ${CMAKE_BINARY_DIR}/kernel)
endmacro()


include(FindPackageHandleStandardArgs)
FIND_PACKAGE_HANDLE_STANDARD_ARGS(
    neuro
    DEFAULT_MSG
    KERNEL_PATH
    KERNEL_HELPERS_PATH
)
