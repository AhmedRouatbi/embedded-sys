# Peripherals — buses, DMA, sensors, ADC, displays

> Load when: I2C/SPI/UART/CAN/USB/ADC/PWM/DMA work, sensor bring-up/calibration, displays.
> Profile keys: `platform`, `features` (can, usb, sensors, display, dsp), `debugger`.

Bring-up order for any new part: **power + reset → bus electrical (scope/logic analyzer) → read ID register → configure → read data → validate against physics → stress (rate, length, errors)**. Read the part's datasheet register map and timing section first; cite them in comments.

## Zephyr APIs first

| Bus | DT spec + API | Notes |
|---|---|---|
| I2C | `I2C_DT_SPEC_GET`, `i2c_write_read_dt`, `i2c_reg_read_byte_dt`, `i2c_burst_read_dt` | `CONFIG_I2C=y`; shell `i2c scan i2c@...` (`CONFIG_I2C_SHELL`) |
| SPI | `SPI_DT_SPEC_GET(node, SPI_WORD_SET(8) \| SPI_MODE_CPOL \| SPI_MODE_CPHA, 0)`, `spi_transceive_dt` | CS via `cs-gpios` on the bus node |
| UART | polling `uart_poll_out`, IRQ `uart_irq_callback_user_data_set`, **async** `uart_callback_set` + `uart_rx_enable` (DMA) | async API for > 115200 baud or bursts |
| CAN | `can_add_rx_filter`, `can_send`, `can_set_bitrate` / DT `bitrate`/`bus-speed` | `can_get_state` + state change callback |
| USB device | `usbd_*` (device stack next), CDC ACM via DT `zephyr,cdc-acm-uart` | `-S cdc-acm-console` |
| ADC | `ADC_DT_SPEC_GET`, `adc_channel_setup_dt`, `adc_read_dt`, `adc_raw_to_millivolts_dt` | channel config in DT `channel@n` |
| PWM / GPIO | `PWM_DT_SPEC_GET`, `pwm_set_dt`; `GPIO_DT_SPEC_GET`, `gpio_pin_configure_dt`, `gpio_pin_interrupt_configure_dt` | |
| Sensor | `sensor_sample_fetch` + `sensor_channel_get` (or the newer read/decode API) | check for an in-tree driver: `rg -l "<part>" $ZEPHYR_BASE/drivers/sensor` |

Bare metal: vendor LL/HAL if the project uses it, otherwise registers per RM; same electrical rules.

## I2C

- 7-bit address in APIs (datasheets sometimes print the 8-bit R/W form: shift right by 1). Address pins (SA0/AD0) change it — check the schematic.
- Pull-ups: 2.2–4.7 kΩ typical at 100/400 kHz; rise time limits from bus capacitance (I2C spec: 1000 ns @100 kHz, 300 ns @400 kHz). Internal MCU pull-ups are too weak for 400 kHz.
- Clock stretching: some masters/bit-bang implementations don't support it; slow sensors need it.
- Stuck bus (SDA held low after reset mid-transfer): clock SCL 9 times as GPIO then STOP (Zephyr `i2c_recover_bus()` where supported).
- Repeated-start reads (`write_read`), not write + separate read, unless the datasheet says so.

## SPI

| Mode | CPOL | CPHA | Idle clock | Sample edge |
|---|---|---|---|---|
| 0 | 0 | 0 | low | rising |
| 1 | 0 | 1 | low | falling |
| 2 | 1 | 0 | high | falling |
| 3 | 1 | 1 | high | rising |

- All `0xFF` reads → MISO floating/CS not asserted/wrong mode; all `0x00` → part in reset or not powered.
- Many sensors: register address MSB = read flag; multi-byte auto-increment bit; dummy byte before data on some parts.
- CS setup/hold times and max SCK from the datasheet; long wires → lower SCK.

## UART

- Baud error < 2 % total (both ends); verify the actual peripheral clock (wrong HSE value is the #1 cause of garbage).
- RX: interrupt per byte is fine ≤ 115200 for short messages; above that or for bursts use DMA circular buffer + IDLE-line detection (Zephyr async API does this).
- Ring buffer between ISR and parser (`ring_buf` in Zephyr), size ≥ worst-case burst during the parser's longest preemption; count and log overruns.
- Flow control (RTS/CTS) for modems/BLE/Wi-Fi coprocessors at high baud.
- Framing: length-prefixed or delimiter (COBS/SLIP) + CRC; never trust lengths from the wire without bounds checks.

## CAN / CAN FD

- Bit timing from the controller clock: sample point ~87.5 % (CANopen/automotive), same nominal bit rate on all nodes; Zephyr computes timing from `bitrate` + `sample-point` DT props.
- 120 Ω termination at both ends only. One node alone on a bus sees ACK errors → error-passive (normal on the bench without a second node or loopback mode).
- Filters: accept only needed IDs; overflowing RX FIFO loses frames silently unless you count it.
- Handle bus-off: recovery policy (auto vs. manual `can_recover`), log state changes.

## USB

- Enumeration failures: wrong 48 MHz clock (USB needs ±0.25 %; use HSE/CRS, not raw HSI), D+ pull-up, VBUS sensing config, descriptor lengths, endpoint max packet size vs. speed.
- CDC ACM: host must open the port (DTR) before you assume a reader exists; don't block on TX when nobody reads.

## DMA

- Buffers: correct alignment (word, or cache-line 32 B on M7/M55), lifetime (static or owned by a live thread — never a returning function's stack).
- M7/M55 data cache: clean D-cache before memory→peripheral, invalidate after peripheral→memory, or place buffers in a non-cacheable region (Zephyr `__nocache` with `CONFIG_NOCACHE_MEMORY=y`, DT `zephyr,memory-attr`).
- Double-buffering (half/full complete callbacks) for continuous streams; process one half while DMA fills the other; detect overrun.
- Check DMA request mapping/stream/channel against the RM table (Zephyr: DT `dmas = <&dma1 2 ...>`).

## ADC

- Sampling time vs. source impedance (datasheet table); add a buffer/cap for high-impedance dividers.
- Calibrate at boot if the part supports it (Zephyr drivers usually do); use the internal reference/VREFINT to correct supply variation.
- Oversample + average for noise; median filter for spikes; DMA + timer trigger for fixed-rate sampling (jitter-free).

## Sensors

- Check DRDY/status before reading; use the data-ready interrupt rather than polling fast.
- Burst-read all axes in one transaction (coherent sample); handle endianness and sign extension (`sys_get_le16`, `(int16_t)` casts).
- Calibration: ≥ 2 points (offset + gain); temperature compensation where the datasheet shows drift; store calibration with a version + CRC (Zephyr `settings`/NVS).
- Validate against physics: accelerometer at rest ≈ 9.81 m/s² magnitude, temperature within range; plausibility checks catch wiring and conversion bugs.
- Filters sized to the response-time requirement: moving average window = latency; complementary/Kalman/Madgwick for IMU fusion — use a proven implementation, unit-test it on host with recorded data.

## Displays

- Use Zephyr `display` API/LVGL (`CONFIG_LVGL`) or vendor driver; framebuffer size = W×H×bpp — check RAM budget; partial updates + DMA for SPI panels; backlight via PWM.

## Anti-patterns

- Polling a status bit without a timeout.
- Ignoring NACK/`-EIO` returns and using stale data.
- Per-byte UART interrupts at 1 Mbaud; DMA into cached RAM without maintenance.
- Single-point calibration; calibration constants hard-coded from one unit.
- Writing a sensor driver when Zephyr already has one.

## Sources
LibreEmbed `communication-buses`, `sensor-integration`, `iot-protocols` (UART framing); Zephyr driver APIs (`include/zephyr/drivers`); NXP UM10204 I2C spec; ISO 11898 CAN.
