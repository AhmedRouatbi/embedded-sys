# Host tests: the thermal core from ../src, compiled for native_sim (no board, no HAL modules).
cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(thermal_tests)

target_include_directories(app PRIVATE ../src)
target_sources(app PRIVATE src/test_thermal.c ../src/thermal.c)
