# Safety architecture and freedom from interference

This page shows the current design. When there was a choice between alternatives, record the decision in an ADR under `docs/adr/`.

## Partitions
| Partition | Contents | Level (SIL/ASIL/QM) | Threads, priority | Stack | MPU region / memory domain |
|---|---|---|---|---|---|
| safety | <monitor, fault reaction> | <SIL2> | <supervisor, prio 1> | <1 KB, guard on> | <domain safety_dom> |
| non-safety | <shell, logging, comms> | QM | | | |

## Data ownership
| Data | Writer (only one) | Readers | Protection (MPU, value + complement, CRC, mutex) |
|---|---|---|---|

## Timing
| Thread / ISR | Priority | Period / deadline | WCET budget | Watchdog heartbeat |
|---|---|---|---|---|

Per SR: detection interval + reaction latency < process safety time.

## Shared resources
| Resource (bus, peripheral, mutex, heap) | Users | Interference risk | Mitigation |
|---|---|---|---|

## Safety mechanisms in use
| Mechanism (catalog in `safety.md`) | Covers (H/SR) | Where | Diagnostic interval |
|---|---|---|---|
