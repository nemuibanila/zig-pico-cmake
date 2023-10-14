cmake_minimum_required(VERSION 3.27)


# Path to Pico SDK
set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})

# Initialize the Pico SDK
include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)
project(mlem)
pico_sdk_init()
add_executable(mlem)

# Adjust libraries as needed
target_link_libraries(mlem pico_stdlib pico_cyw43_arch_none ${CMAKE_SOURCE_DIR}/zig-out/mlem.o)

# Generate binary
pico_add_extra_outputs(mlem)
