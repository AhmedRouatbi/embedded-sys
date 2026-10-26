# Docs, git, CI & release

> Load when: documenting (phase 8), committing/branching, setting up CI, versioning, preparing a release (phase 9).
> Profile keys: `platform`, `safety`, `autocommit`, `graphify`, `features` (bootloader-ota).

## Documentation that earns its keep

| Doc | Content | Update when |
|---|---|---|
| `README.md` | what it is, board/MCU, how to build/test/flash/log (copy from the `embsk` block), wiring table, known limits | interfaces or commands change |
| `docs/SPEC.md` | requirements, budgets, failure modes (`spec-plan.md`) | requirements change |
| `docs/adr/NNNN-title.md` | one decision each: context, options, decision, consequences (`templates/ADR.md`) | a non-obvious choice is made or reversed |
| `docs/hw/` | pin map, schematic refs, datasheet notes (markdown extracts, section numbers) | hardware revision |
| `docs/generated/` | resolved DTS/Kconfig/map (`embsk export`) — never hand-edited | every build that changes DT/Kconfig |
| `graphify-out/wiki/` | auto architecture wiki (`graphify export wiki`) | milestones/releases |
| `CHANGELOG.md` | user-visible changes per version (Keep a Changelog) | every release |
| Safety docs | `safety.md` artifacts | per change for safety functions |

Rules: document **why** (decisions, datasheet reasons, limits), not what the code says. Code comments cite datasheet sections. Diagrams as Mermaid in markdown (`graphify export callflow-html` for call-flow views). Stale docs are worse than none — the review checks that docs match the change.

## Git workflow

- Trunk-based: short branches `feat/<area>-<thing>`, `fix/<area>-<bug>`; rebase on main; small PRs (≲ 400 changed lines excluding generated files).
- One task = one commit that builds and passes host tests. Message: `<area>: <imperative summary> (REQ-n)` + body with *why*, verification level, risk. Example: `imu: add BMI270 burst read over SPI (REQ-4)`.
- Never mix refactor + behaviour change; never commit `build*/`, `twister-out*/`, `artifacts/*.txt`, keys, `.env`.
- `.gitignore`: `build*/ twister-out*/ artifacts/*.txt graphify-out/cache/ *.pem *.key .env`.
- Auto-commit only when the profile says `autocommit on`; otherwise propose the message and let the user commit.
- Zephyr workspace: pin the manifest (`west.yml` revisions = tags/SHAs, not branches) for reproducible builds; application-as-manifest workspace topology recommended (Zephyr docs call it "T2"; unrelated to this skill's tiers).
- `git bisect run embsk verify` to find regressions.

## CI for firmware (GitHub Actions example, Zephyr)

```yaml
name: firmware
on: [push, pull_request]
jobs:
  build-test:
    runs-on: ubuntu-24.04
    container: ghcr.io/zephyrproject-rtos/ci:<pin-a-version>   # SDK + west + twister deps
    steps:
      - uses: actions/checkout@v4
        with: { path: app }
      - run: west init -l app && west update --narrow -o=--depth=1
      - run: west twister -T app/tests -p native_sim/native/64 --inline-logs        # L2
      - run: west build -b <board> app -p always -- -DCONFIG_COMPILER_WARNINGS_AS_ERRORS=y  # L1
      - run: west build -d build -t rom_report > rom.txt && west build -d build -t ram_report > ram.txt
      - uses: actions/upload-artifact@v4
        with: { name: fw-<board>, path: "build/zephyr/zephyr.*\nrom.txt\nram.txt" }
```
- Bare metal: container with `gcc-arm-none-eabi` + cmake/ninja; host tests with `ctest`; cppcheck/clang-tidy step (L3).
- Add a size gate (fail if flash/RAM grows > N % without a label), static analysis on changed files, and (later) a self-hosted runner with a board for L5 (`twister --device-testing`).
- Cache west modules; pin container and SDK versions; CI is the source of truth for "it builds".

## Versioning

- SemVer for the firmware: MAJOR (breaking protocol/storage/partition change), MINOR (feature), PATCH (fix).
- Zephyr: `VERSION` file in the app dir (`VERSION_MAJOR = 1`, `VERSION_MINOR = 2`, `PATCHLEVEL = 0`, `VERSION_TWEAK = 0`, `EXTRAVERSION =`) → `#include <zephyr/app_version.h>` gives `APP_VERSION_STRING`; MCUboot signs with `CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION` (keep it equal to the app version).
- Embed build metadata: version + git describe + build date in a const struct (and in the boot log line) — the field must be able to tell which image runs.

## Release checklist (T2 or on request)

1. Spec/ADRs/CHANGELOG updated; version bumped in `VERSION` (+ security counter if anti-rollback).
2. CI green on the release commit: L1 all boards, L2 all suites, L3 clean, size within budget.
3. L4/L5 on real hardware for this exact image (`artifacts/` evidence attached), including: cold boot, brown-out, watchdog reset recovery, OTA from previous release + revert test (`boot-ota-security.md`).
4. Release config: production signing key, debug shells/logs per policy, asserts per safety analysis, debug lock plan.
5. Artifacts: `zephyr.signed.hex/.bin` (or `app.hex/.elf`), the `.elf` with symbols (archived, not shipped), map file, SHA-256 of every artifact, SBOM (`west spdx`), release notes.
6. Tag `vX.Y.Z` (signed tag), archive artifacts with the tag.
7. Rollout: internal units → small field cohort → staged % (OTA campaign), with health metrics (boot count, reset causes, crash logs) and a stop/rollback criterion defined **before** starting.
8. Production programming: scripted, reproducible flash + verify + provisioning per unit (serial number, keys), logs kept per unit — never manual flashing.

## Anti-patterns

- "Release" = whatever is in `build/` on someone's laptop.
- Unpinned west manifests; CI using `main` of Zephyr.
- Shipping without the matching `.elf` archived (crash addresses become undecodable).
- Docs re-describing code; ADRs written months after the decision.

## Sources
agent-skills `documentation-and-adrs`, `git-workflow-and-versioning`, `ci-cd-and-automation`, `shipping-and-launch`, `deprecation-and-migration`; LibreEmbed `embedded-testing` (CI), `firmware-update`; Zephyr build system (`VERSION`, sysbuild).
