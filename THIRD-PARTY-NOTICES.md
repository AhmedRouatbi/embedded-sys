# Third-party notices

`embedded-sys` merges ideas, structure and adapted text from four open-source projects. Their reference files were rewritten (Zephyr-first, de-duplicated) rather than vendored. No upstream source file is shipped as is.

| Project | License | Copyright | Used for | Where it lives here |
|---|---|---|---|---|
| [LibreEmbed-Claude-Code](https://github.com/Ormus-Solutions/LibreEmbed-Claude-Code) | MIT | Copyright (c) 2025-2026 Hermetic Ormus | embedded domain knowledge; the flash-confirmation hook | `skills/embedded-sys/references/*` (rewritten); `hooks/flash-guard.sh` (adapted from `libre-embed-hooks`) |
| [ponytail](https://github.com/DietrichGebert/ponytail) | MIT | Copyright (c) 2026 DietrichGebert | "smallest complete change" ladder, review format, `shortcut:` convention | `references/coding.md`, `references/review.md` |
| [agent-skills](https://github.com/addyosmani/agent-skills) | MIT | Copyright (c) 2025 Addy Osmani | process: spec, plan, TDD, debugging, docs/ADR, git, CI, shipping, constraint- and doubt-driven review | `SKILL.md` phases, `references/spec-plan.md`, `testing-verification.md`, `debugging.md`, `docs-release.md`, `safety.md`, `context-graphify.md` |
| [graphify](https://github.com/Graphify-Labs/graphify) | Apache-2.0 | the graphify authors (Graphify-Labs) | code-graph navigation. graphify is **called as an external CLI** (`uv tool install graphifyy`); its usage guide was condensed into our own text, and no graphify code is included | `references/context-graphify.md` |

Each reference file ends with a `## Sources` section naming the upstream skills it draws on.

## MIT License (LibreEmbed-Claude-Code, ponytail, agent-skills)

The following notice applies to the material adapted from the three MIT-licensed projects above, with their respective copyright lines:

```
MIT License

Copyright (c) 2025-2026 Hermetic Ormus          (LibreEmbed-Claude-Code)
Copyright (c) 2026 DietrichGebert               (ponytail)
Copyright (c) 2025 Addy Osmani                  (agent-skills)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Apache License 2.0 (graphify)

graphify is licensed under the Apache License, Version 2.0: <https://github.com/Graphify-Labs/graphify/blob/main/LICENSE>. This repository doesn't redistribute graphify. `references/context-graphify.md` describes how to use its CLI, in our own words.

## Example code

The Zephyr template `main.cpp` (`skills/embedded-sys/templates/zephyr-app/app/src/main.cpp`, copied into `example/01-zephyr-template/`) is a shortened version of Zephyr's `samples/basic/blinky`: Copyright (c) 2016 Intel Corporation, Apache-2.0 (header kept in the file). It reached this repo through a Zephyr training project. The Zephyr RTOS itself (Apache-2.0) is fetched by `west`, not included.
