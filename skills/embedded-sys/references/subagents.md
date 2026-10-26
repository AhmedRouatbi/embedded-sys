# Subagents — roles, parallelism, per-tool mechanics

> Load when: the profile has `subagents on` and a task has independent parts, or for fresh-context review.
> Profile keys: `subagents`, `safety`.

Subagents buy two things: **parallel wall-clock** and **fresh context**. They cost tokens and coordination. Use the smallest team that helps; expand in small batches.

## Roles (cards in `$SKILL_DIR/agents/`)

| Role | Writes? | Context to give | Returns |
|---|---|---|---|
| `fw-scout` | no | question + where to look | file:line facts, symbols, DT nodes, datasheet sections — no dumps |
| `fw-builder` | yes, **only its listed files** | one task card: goal, files, test, verify command, REQ ids | diff summary + verify output |
| `fw-verifier` | no (only `artifacts/`) | commands from the AGENTS.md block, expected log lines | PASS/FAIL per level, evidence paths |
| `fw-reviewer` | no | diff + `docs/SPEC.md` excerpt, **no author reasoning** | `review.md` format report |
| `fw-safety` | no | diff + safety reqs + standard/level | MISRA/hazard/traceability findings |

## When to spawn

- Map: 2–3 `fw-scout`s on independent questions (e.g. "DT for the sensor bus", "how logging is wired", "existing ring buffer helpers").
- Build: `fw-builder`s only for tasks touching **disjoint files**. Same file or same header → sequential, or separate git worktrees (`git worktree add ../wt-<task> -b task/<n>`), merged by you.
- Verify: one `fw-verifier` runs builds/tests while you continue; hardware access (flash, probe, serial port) is **single-owner** — never two agents on one probe/port.
- Review: always one `fw-reviewer` with fresh context; plus `fw-safety` when `safety ≠ none` and tier T2.
- Don't spawn for: T0 changes, a single small task, anything needing the user's hardware OK mid-way (keep that in the main session).

## Pi (persistent agents)

```text
spawn_agent  task_name="scout_dt"   fork_turns="none"  message="<fw-scout card>\n\nQUESTION: ..."
spawn_agent  task_name="review_1"   fork_turns="none"  message="<fw-reviewer card>\n\nDIFF: ...\nCONTRACT: ..."
spawn_agent  task_name="build_t3"   fork_turns="2"     message="<fw-builder card>\n\nTASK: ..."   # small fork = recent plan context
wait_agent   {}            # ANY finished   | {target:"review_1"} | {all:true}
followup_task target="build_t3" message="fix finding 2 from review_1"
```

- `fork_turns: "none"` for reviewers/scouts (fresh, cheap); a small number for builders that need the plan.
- Agents share cwd/filesystem: parallel writers need disjoint paths or worktrees; there is no edit lock.
- `delegate` = blocking one-shot (good for a single scout question). Don't use it as a fallback if `spawn_agent` fails to start — report the runtime error (e.g. bwrap/user-namespace sandbox failures need an OS fix) and continue sequentially.
- Pi workflow: `workflow_run embedded "<task>"` runs plan → execute → verify → review with loops (`pi-workflows/embedded.yaml`).

## Claude Code

- Install copies the cards to `~/.claude/agents/` (frontmatter `name/description/tools/model`). Invoke via the Task tool: *"Use the fw-reviewer agent on the staged diff against docs/SPEC.md"*.
- Subagents start with isolated context by default — ideal for `fw-reviewer`.
- Parallel: several Task calls in one message; same disjoint-files rule.
- Headless parallel builders: `claude -p "<card + task>" --permission-mode acceptEdits` inside separate worktrees.

## Codex / tools without subagents

- Run roles sequentially in the main session. For review, re-read only the diff + spec and apply `review.md` as if you'd never seen the code.
- Parallel or fresh-context alternative: headless processes in worktrees — `codex exec -C ../wt-t3 --sandbox workspace-write "<card + task>"`; reviews read-only: `codex exec --sandbox read-only - < /tmp/review-prompt.md` (prompt via stdin file, never shell-interpolated).

## Task card format (what you hand a builder)

```
TASK t3: SPI driver for BMI270 accel read (REQ-4, REQ-5)
FILES (only these): src/imu.c, src/imu.h, tests/src/test_imu_conv.c
CONTEXT: DT node &spi1 / bmi270@0 (docs/generated/zephyr-dts.txt:L812); use Zephyr sensor API.
TEST FIRST: tests/src/test_imu_conv.c — raw→m/s² conversion incl. ±16g saturation.
VERIFY: west build -b native_sim/native/64 -d build-test tests && ./build-test/zephyr/zephyr.exe
DONE WHEN: test passes + `west build -b <board>` passes; report size delta.
RULES: coding.md; no flashing; no files outside FILES.
```

## Anti-patterns

- Two agents editing the same file or holding the same probe/serial port.
- Passing the reviewer your conclusion ("check that my fix is correct") — pass artifact + contract.
- Spawning 8 agents for a 3-file change.
- Letting subagent output dumps flow into the main context — ask for facts + paths.

## Sources
Pi subagents extension (Codex multi-agent v2 contract); agent-skills `doubt-driven-development`, `incremental-implementation`; Claude Code subagents.
