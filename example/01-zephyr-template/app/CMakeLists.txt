cmake_minimum_required(VERSION 3.20.0)

# HINTS: use the workspace's Zephyr (set by west/embsk), not another tree registered on this machine
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(my_zephyr_app)

target_sources(app PRIVATE src/main.cpp)
