# Deviation log

Every analyzer suppression or rule exception needs a row here, and the code must cite it:
`/* MISRA C:2012 Rule 11.4 deviation DEV-1: <reason> */`. Anonymous suppressions are not allowed.
Mandatory MISRA rules can't be deviated. Only a human approves a deviation.

| ID | Rule (standard, category) | Location | Reason | Risk + mitigation | Approver, date | Status |
|---|---|---|---|---|---|---|
| DEV-1 | <MISRA C:2012 Rule 11.4 (advisory)> | <src/hw/regs.c:12> | <MMIO base address from datasheet cast to pointer> | <alignment checked by static assert; address from DT macro> | <name, YYYY-MM-DD> | proposed / approved / removed |
