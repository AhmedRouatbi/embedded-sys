# Safety requirements (SRS)

Standard / level: <from the `embsk` block> · Status: draft | approved (<date>, <who>)
The agent derives SRs from `hazards.md`; humans approve them. Each SR must be testable. Tag its code `/* SR-n */` and name its tests `test_srn_*`.

| ID | Requirement (testable, with numbers) | Level | Safe state | Fault reaction time (< process safety time) | Hazard | Verification |
|---|---|---|---|---|---|---|
| SR-1 | <When T > 85 °C on 2 consecutive samples, the heater output shall be off within 500 ms and stay off until power cycle> | <SIL2> | <relay off, fault latched> | < 500 ms (PST 2 s) | H-1 | `test_sr1_overtemp_cuts_relay` + fault injection (sensor open/stuck) |

## Assumptions of use / external measures
- <e.g. independent thermal fuse in hardware; BOR level set; watchdog clocked from LSI>
