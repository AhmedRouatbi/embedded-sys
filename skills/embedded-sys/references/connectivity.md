# Connectivity — BLE, Wi-Fi, Ethernet/IP, MQTT/CoAP/LwM2M, LoRaWAN, Thread

> Load when: radio or network features; choosing a protocol; connection stability, throughput or power problems on a link.
> Profile keys: `features` (ble, wifi, ethernet, lora), `platform`, `safety`.

Use the platform stack, don't write protocol code: Zephyr has BLE host/controller, IP stack (sockets), MQTT, CoAP, LwM2M, HTTP, TLS (mbedTLS/PSA), OpenThread, LoRaWAN (LoRaMac-node), Wi-Fi management. Start from the matching `samples/` app on your board, trim it.

## Protocol choice

| Constraint | MQTT/TCP | CoAP/UDP | LwM2M | BLE GATT | LoRaWAN | Thread/Matter | NB-IoT/LTE-M |
|---|---|---|---|---|---|---|---|
| Years on a coin cell/AA | no | maybe | maybe | yes (peripheral) | yes | maybe (SED) | maybe (PSM/eDRX) |
| Direct internet | yes | yes | yes | no (via phone/gateway) | via gateway | via border router | yes |
| Range | Wi-Fi/Eth | Wi-Fi/Eth | any IP | ~10–50 m | km | mesh | cellular |
| Throughput > 1 kbps | yes | yes | yes | yes | **no** | yes | yes |
| Device management + FOTA built in | no | no | **yes** | via SMP | partial (FUOTA) | Matter OTA | via LwM2M |

Write the choice + reason as an ADR. The cheapest link that meets range, rate and power wins.

## BLE (Zephyr host)

- Config: `CONFIG_BT=y`, `CONFIG_BT_PERIPHERAL=y` (or `_CENTRAL`), `CONFIG_BT_DEVICE_NAME`; GATT services with `BT_GATT_SERVICE_DEFINE`; notify via `bt_gatt_notify` only when the CCC is enabled.
- Design GATT around use cases, few characteristics, explicit max lengths, little-endian packed payloads documented in the spec; standard services (Battery, DIS, ESS) where they fit.
- Connection parameters:

| Param | Low power | Low latency |
|---|---|---|
| Interval min/max | 1000–2000 ms | 7.5–15 ms |
| Peripheral latency | 4 | 0 |
| Supervision timeout | 6000 ms | 1000 ms |
  Rule: timeout ≥ (1 + latency) × max_interval × 2 (spec minimum), use ×4 margin; phones override requests (iOS: aim 30–50 ms when responsiveness matters).
- Throughput: request MTU (`CONFIG_BT_L2CAP_TX_MTU=247`, `bt_gatt_exchange_mtu`), data length extension (`CONFIG_BT_CTLR_DATA_LENGTH_MAX=251`), 2M PHY; notifications without response.
- Security: LE Secure Connections, bonding stored via `settings`; characteristics with `BT_GATT_PERM_*_ENCRYPT/AUTHEN` for anything sensitive; no "Just Works" for control of actuators.
- Advertising interval vs. discovery time vs. current: 100 ms fast for 30 s after button/boot, then 1–2 s.
- Multi-core SoCs (nRF53): controller on the network core (`hci_ipc` image via sysbuild).

## IP (Wi-Fi / Ethernet / cellular)

- Zephyr sockets API (`zsock_*` or POSIX names), `net_mgmt` events for link up/down and DHCP; never assume the network is up at boot — state machine with back-off reconnect (exponential + jitter).
- Wi-Fi: credentials from provisioning stored with `settings` (encrypted where available), never compiled in; `CONFIG_WIFI=y` + `net wifi` shell for bring-up.
- TLS: mbedTLS/PSA with CA cert validation and SNI; time source (SNTP) for cert validity; RAM cost of TLS (~30–50 KB) goes into the budget.
- Buffers: `CONFIG_NET_PKT_RX_COUNT`, `CONFIG_NET_BUF_RX_COUNT` sized for bursts; watch `net stats`.

## MQTT

- QoS 0 telemetry, QoS 1 for commands/events that must arrive (idempotent handlers — duplicates happen), QoS 2 rarely worth it.
- Keep-alive below NAT idle timeout (≤ 60 s typical) — "reconnects every few minutes" is usually NAT.
- LWT (`<prefix>/<id>/status` = `offline`, retained) + publish `online` retained after connect.
- Topics: `<org>/<product>/<device-id>/<direction>/<thing>`; device subscribes only to its own command topics; no wildcards for commands.
- Payload: CBOR/compact binary or JSON with a schema version field; bound sizes.

## CoAP / LwM2M

- CoAP CON for must-arrive, NON for telemetry; Observe for push; block-wise for payloads > MTU; DTLS (PSK or certs).
- LwM2M (Zephyr `CONFIG_LWM2M=y`): standard objects (Device 3, Connectivity 4, Firmware Update 5, IPSO sensors 33xx) give management + FOTA for free; queue mode for sleepy devices.

## LoRaWAN

- Airtime grows ~2× per SF step; EU868 1 % duty cycle → at SF12 ~1 uplink per 2–3 min max. Small payloads (≤ 11 B at SF12 DR0 in EU868), ADR on for static devices, confirmed uplinks sparingly.
- Class A for sensors; B/C only for downlink-latency needs (more power).
- OTAA join with keys provisioned per device; store DevNonce/frame counters across resets (or join again correctly).
- Field ≠ lab: verify link margin (RSSI/SNR) at the real install site.

## Thread / Matter

- OpenThread in Zephyr (`CONFIG_NET_L2_OPENTHREAD=y`); sleepy end devices for battery; border router for IP reach. Matter = Thread/Wi-Fi + certification process; use the vendor SDK flavour (nRF Connect SDK, ESP-Matter) rather than raw upstream.

## Robustness checklist (any link)

- Link down is a normal state: queue or drop with a policy, back-off reconnect, no busy loops, watchdog not tied to connectivity.
- Every received field validated (length, range, state); parsers fuzzed on host.
- Time-outs on every request; correlation ids for request/response.
- Radio activity + crypto counted in the power budget (measure TX/RX current and duration).
- OTA over the link → `boot-ota-security.md`.

## Anti-patterns

- Hard-coded Wi-Fi/cloud credentials; skipping certificate validation "for now".
- Reconnect loops without back-off draining the battery.
- Huge JSON payloads over BLE/LoRa; sending at a fixed rate when on-change would do.
- Blocking network calls from the system work-queue or a high-priority thread.

## Sources
LibreEmbed `iot-protocols`; Zephyr `subsys/bluetooth`, `subsys/net`, `samples/net`, `samples/bluetooth`; LoRa Alliance regional parameters (EU868).
