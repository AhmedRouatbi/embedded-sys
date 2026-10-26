# Hazard analysis / FMEA-lite

Standard / level: <from the `embsk` block, e.g. IEC 61508 SIL2> · Status: draft | approved (<date>, <who>)
The agent proposes rows; humans own the severity ratings and the approval. This page doesn't claim compliance.

Sev: 1 negligible · 2 marginal · 3 critical · 4 catastrophic. Replace this with your standard's scheme if it has its own: ISO 26262 rates S0–S3, E0–E4 and C0–C3 and derives the ASIL from them.

| ID | Function | Failure mode | Effect | Sev | Detection | Mechanism / safe state | Reaction time | SR |
|---|---|---|---|---|---|---|---|---|
| H-1 | Heater control | output stuck on | overheat | 4 | temp > limit, plausibility vs. 2nd sensor | cut relay via independent GPIO, latch fault | < 500 ms | SR-1 |
| H-2 | <function> | <stuck / lost / late / wrong value / spurious> | <effect at system level> | | <how firmware sees it> | <reaction, safe state> | <budget> | |

Mechanism ideas: see the catalog in `safety.md`. Every row with Sev ≥ 3 needs a matching `SR-n` in `SRS.md`.
