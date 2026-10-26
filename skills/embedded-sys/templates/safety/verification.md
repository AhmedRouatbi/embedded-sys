# Safety verification report

Commit: <sha> · Date: <YYYY-MM-DD> · Standard / level: <...>
Tools and versions: <compiler, analyzer, coverage tool>
This page records evidence only. Compliance is for humans and assessors to decide.

## Requirements
| SR | Implementation (file:function) | Tests | Fault path tested | Level reached (L1–L5) | Result | Evidence |
|---|---|---|---|---|---|---|
| SR-1 | <src/core/thermal.c:thermal_check()> | `test_sr1_overtemp_cuts_relay` | <yes: sensor open, stuck-high> | <L4 SIL> | PASS | <artifacts/test.txt> |

## Traceability gaps
<Output of the matrix commands in `safety.md` §Traceability: SRs with no code or no test, and SR tags that aren't in SRS.md. "none" if clean.>

## Structural coverage
| Scope | Statement | Branch | MC/DC | Target (CONSTRAINTS.md) | Tool |
|---|---|---|---|---|---|

## Static analysis
| Tool + config | Mandatory | Required | Advisory | Deviations (DEV ids) | Output |
|---|---|---|---|---|---|
| <cppcheck --addon=misra> | 0 | 0 | <n> | <DEV-1> | `artifacts/sca.txt` |

## Resources and timing
| Item | Budget | Measured | Evidence |
|---|---|---|---|
| Stack margin per thread | ≥ 30 % | | |
| Fault reaction time SR-1 | < 500 ms | | |

## Reviews
| Change / PR | fw-reviewer | fw-safety | Human reviewer (independence) | AI-generated code flagged |
|---|---|---|---|---|

## Open issues
- <...>
