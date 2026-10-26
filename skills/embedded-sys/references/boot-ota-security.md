# Bootloader, OTA & device security

> Load when: bootloader/MCUboot, flash partitions, firmware update (OTA/DFU), image signing, secure boot, debug-port locking, keys/secrets, threat modelling. Always tier T2.
> Profile keys: `features` (bootloader-ota, secure-boot), `platform`, `safety`.

Everything here can brick units in the field. Rule: **no change to partitions, bootloader, keys, option bytes, RDP/APPROTECT or fuses without an explicit user decision and a recovery path written down first.**

## Update architecture — pick, then write an ADR

| Scheme | Flash cost | Rollback | Notes |
|---|---|---|---|
| Single slot + serial recovery bootloader | ~1× app | no (recover by cable) | cheapest; field updates risky |
| A/B swap (MCUboot swap-using-offset/move/scratch) | ~2× app + scratch/trailer | **yes**, test boot + confirm | default for OTA |
| Overwrite-only | ~2× app | no | simpler, faster, no revert |
| Direct-XIP A/B | 2× app, no copy | with revert variant | needs position-specific images per slot |
| External flash secondary slot | app in internal + copy in QSPI | yes | encrypt image at rest if external flash is readable |

## MCUboot with Zephyr (sysbuild)

```
sysbuild.conf:
  SB_CONFIG_BOOTLOADER_MCUBOOT=y
  SB_CONFIG_MCUBOOT_MODE_SWAP_USING_OFFSET=y      # or _MOVE / _SCRATCH / _OVERWRITE_ONLY / _DIRECT_XIP
  SB_CONFIG_BOOT_SIGNATURE_TYPE_ECDSA_P256=y      # or _ED25519 / _RSA
  SB_CONFIG_BOOT_SIGNATURE_KEY_FILE="\${APP_DIR}/keys/signing-key.pem"   # NEVER the default dev key in production
build:  west build --sysbuild -b <board> <app>
```
- Partitions come from DT `fixed-partitions` (`boot_partition`, `slot0_partition`, `slot1_partition`, optional `scratch_partition`, `storage_partition`); chosen `zephyr,code-partition = &slot0_partition`. Check sizes: app ≤ slot − trailer; storage outside slots.
- Images are signed at build (`zephyr.signed.bin/.hex`); manual: `west sign -t imgtool -- --key <pem>` or `imgtool sign --key k.pem --header-size 0x200 --align 8 --version 1.2.3 --slot-size <sz> in.bin out.bin`.
- App must **confirm** after a successful self-test, or MCUboot reverts on next reset: `boot_write_img_confirmed()` (`<zephyr/dfu/mcuboot.h>`), only after the checks that prove the new image works (connectivity up, sensors OK, watchdog fed by all threads).
- Transport: MCUmgr/SMP (`CONFIG_MCUMGR=y`, `CONFIG_MCUMGR_GRP_IMG=y`, BT/UART/UDP transport) with `mcumgr`/`smpmgr`/nRF Connect Device Manager; or your own protocol writing slot1 via `flash_img` + `boot_request_upgrade()`.

## Update protocol rules (any bootloader)

1. Authenticate before trusting: signature over header + image (ECDSA P-256/Ed25519), public key in the bootloader (or hash of it in OTP).
2. Anti-rollback: monotonic security counter / version in the signed header; refuse older images unless explicitly allowed.
3. Integrity in transit and at rest: hash per chunk optional, full-image hash mandatory before marking pending.
4. Power-fail safe at every step: write to the inactive slot only, mark pending last, bootloader swap is resumable.
5. Test boot + confirm + automatic revert (boot counter or MCUboot test mode). Watchdog active during the bootloader and first boot.
6. Flash writes respect write-block size/alignment (`flash_get_write_block_size()`), erase granularity, and don't stall real-time work.
7. Version reported over the management interface; release notes tie version ↔ git hash ↔ image hash.

## Custom bootloader (bare metal, when MCUboot doesn't fit)

- Keep it tiny and rarely changed; it can't be updated safely in most designs.
- Boot decision: check boot flags (RTC backup register / no-init RAM with magic + CRC) → validate app (vector table sanity: SP within RAM, reset vector within app flash, odd/Thumb) → verify signature/CRC → jump.
- Jump sequence: disable interrupts, de-init peripherals and SysTick, clear pending IRQs, set `SCB->VTOR` to app base, set MSP from app vector[0], `__DSB(); __ISB();`, branch to vector[1].
- Recovery path that doesn't depend on the app (button-held serial/USB DFU, ROM bootloader pin).

## Device security baseline

| Area | Do |
|---|---|
| Debug port | lock in production (STM32 RDP level 1, nRF APPROTECT, NXP debug auth) — level 2/permanent locks are irreversible: user decision + documented RMA path |
| Secure boot | root of trust in ROM/OTP or immutable bootloader; every stage verifies the next |
| Keys | per-device keys/certs provisioned in manufacturing, stored in secure element / TrustZone (TF-M, PSA Crypto `psa_*`) / protected flash; never in git, never in logs; dev keys clearly marked and rejected by production bootloaders |
| TrustZone (M33/M55) | TF-M (`board/<soc>/ns` targets in Zephyr) for crypto/storage/attestation; NS app talks via PSA APIs |
| Comms | TLS 1.2+/DTLS with certificate validation (Zephyr mbedTLS/PSA); no plaintext credentials; unique credentials per device |
| Input | every byte from radio/USB/UART/network is hostile: bounds-check lengths, validate state transitions, fuzz parsers on host (`native_sim` + libFuzzer) |
| Release config | logging of secrets off, shells off or authenticated, test commands removed, `CONFIG_ASSERT` per policy, stack protection on |
| Supply chain | pin west manifest revisions, review module updates, SBOM (`west spdx`), track CVEs for Zephyr/mbedTLS/MCUboot versions in use |

Threat model in one table per product (asset · attacker · entry point · mitigation) — required for EU CRA / ETSI EN 303 645 / IEC 62443 style compliance; record it as an ADR.

## Review checklist (T2)

- Partition map vs. image size vs. bootloader expectations; storage not inside a slot.
- Signing key: production key path, not the MCUboot sample key; key not committed.
- Confirm logic runs only after real health checks; revert path tested on hardware (flash bad image → device returns to old one).
- Version/security counter bumped; downgrade refused.
- Power cut during download and during swap tested (or reasoned with the bootloader's documented guarantees).
- Debug lock / RDP changes are separate, explicit, reversible-or-approved steps.

## Anti-patterns

- Shipping with the MCUboot default signing key or `BOOT_SIGNATURE_TYPE_NONE`.
- Confirming the image at the start of `main()`.
- OTA that erases the running slot first; no watchdog during update.
- Setting permanent readout protection from an agent session.
- Secrets in `prj.conf`, overlays or source.

## Sources
LibreEmbed `bootloader-design`, `firmware-update`, `safety-critical`; agent-skills `security-and-hardening`; MCUboot docs; Zephyr `share/sysbuild`, `subsys/dfu`, `subsys/mgmt/mcumgr`.
