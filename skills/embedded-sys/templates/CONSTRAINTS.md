# Quality constraints (the bar — agents may not lower it)

Changing a number here needs the owner's explicit approval in the PR.

## Floor (always)
- Build: zero warnings on project sources (`-Wall -Wextra -Werror` / `CONFIG_COMPILER_WARNINGS_AS_ERRORS=y` in CI)
- Every new branch/parser/state machine/bug fix has a host test; no skipped or deleted tests without approval
- No new analyzer suppressions without a `DEV-n` record (docs/safety/deviations.md)
- No flashing/erasing/option-byte changes by agents without explicit user OK

## Enforced with numbers
| Dimension | Threshold | Checked by |
|---|---|---|
| Coding standard (<misra-c-2012/...>) | 0 mandatory, 0 required violations in changed files | <cppcheck --addon=misra / tool> |
| Structural coverage (host) | statement ≥ <80>% · branch ≥ <70>% (safety: per standard/level) | `west twister --coverage` / gcovr |
| Stack margin | ≥ 30 % free per thread (measured) | thread analyzer log |
| Flash / RAM headroom | ≥ <20> % / ≥ <20> % | size report |
| Interrupt latency / deadlines | <event: ≤ X µs> | DWT / logic analyzer |

## Measured, not yet enforced
- <power per mode>, <boot time>

## Exceptions
| ID | What | Why | Expires |
|---|---|---|---|
