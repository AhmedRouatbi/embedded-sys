cmake_minimum_required(VERSION 3.20)
project(app C ASM)

option(HOST_TESTS "Build host unit tests with the native compiler instead of firmware" OFF)

if(HOST_TESTS)
  include(FetchContent)
  FetchContent_Declare(unity GIT_REPOSITORY https://github.com/ThrowTheSwitch/Unity.git GIT_TAG v2.6.1)
  FetchContent_MakeAvailable(unity)
  enable_testing()
  # One executable per test file; the functional core in src/ is compiled for the host.
  add_executable(test_build_info tests/test_build_info.c src/build_info.c)
  target_include_directories(test_build_info PRIVATE src)
  target_link_libraries(test_build_info PRIVATE unity)
  add_test(NAME build_info COMMAND test_build_info)
  return()
endif()

# ---- firmware: cmake -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi.cmake
# Copy startup, system and linker files from the vendor CMSIS pack / SDK into vendor/ (don't hand-write them).
set(VENDOR_STARTUP  ${CMAKE_SOURCE_DIR}/vendor/startup.s CACHE FILEPATH "vendor startup file")
set(VENDOR_SYSTEM   ${CMAKE_SOURCE_DIR}/vendor/system.c  CACHE FILEPATH "vendor system_<device>.c")
set(LINKER_SCRIPT   ${CMAKE_SOURCE_DIR}/vendor/device.ld CACHE FILEPATH "vendor linker script")
set(VENDOR_INCLUDES ${CMAKE_SOURCE_DIR}/vendor/include ${CMAKE_SOURCE_DIR}/vendor/CMSIS/Include)

set(APP_SOURCES src/main.c src/build_info.c)
set_source_files_properties(${APP_SOURCES} PROPERTIES COMPILE_OPTIONS "-Werror")  # strict on our code, not vendor code

add_executable(app.elf ${APP_SOURCES} ${VENDOR_STARTUP} ${VENDOR_SYSTEM})
target_include_directories(app.elf PRIVATE src ${VENDOR_INCLUDES})
target_link_options(app.elf PRIVATE -T${LINKER_SCRIPT}
  -Wl,-Map=${CMAKE_BINARY_DIR}/app.map,--gc-sections,--print-memory-usage
  --specs=nano.specs --specs=nosys.specs)
add_custom_command(TARGET app.elf POST_BUILD
  COMMAND ${CMAKE_OBJCOPY} -O ihex app.elf app.hex
  COMMAND ${CMAKE_OBJCOPY} -O binary app.elf app.bin
  COMMAND ${CMAKE_SIZE} app.elf)
