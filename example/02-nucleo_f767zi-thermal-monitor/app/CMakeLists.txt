cmake_minimum_required(VERSION 3.20.0)

# HINTS: use the workspace's Zephyr (set by west/embsk), not another tree registered on this machine
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(thermal_monitor)

target_sources(app PRIVATE src/main.c src/monitor.c src/shell_cmds.c src/thermal.c)

# SIL target (west build -b native_sim/native/64 ...): simulated devices + `sim` shell, see boards/native_sim_native_64.overlay
target_sources_ifdef(CONFIG_BOARD_NATIVE_SIM app PRIVATE src/sim/sim_devices.c src/sim/sim_shell.c)
