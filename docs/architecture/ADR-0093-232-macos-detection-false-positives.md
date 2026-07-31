# ADR-0093 — Gate 1c fired on every meta-SPEC in this repository, and never on a macOS app

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #232 (found by the Phase 7 shakedown run, between Gate 1b and Step 2)
- **Related:** ADR-0032 (the `$HOME`-coupled CI-dark harness class, fourth instance),
  ADR-0039 (both directions per contract), ADR-0043 (a check that did not run must not read as a
  check that found nothing), ADR-0086 §rule 12 (a scan whose needle is a literal counts itself)

## Context

`detect-macos.sh` decides whether Gate 1c offers a HIG design step — window types, navigation,
Settings, menu bar, keyboard shortcuts. It greps prose for
`macos|mac os|swiftui|appkit|mac app|menu bar` after stripping fenced code, table rows and backtick
spans.

Measured over all 36 SPECs in this repository: **it fired on six, and not one of them was a macOS
UI target.**

### Two false-positive classes, and the issue named one

1. **The keyword inside a longer identifier.** `macos-ux` is a skill name, and every meta-SPEC
   about this chain names it. The issue reported this one. **Measuring found a second:
   `swiftui-pro`** — also a skill name, also in the corpus, and it **survives the narrowing #232
   itself proposed** (dropping bare `macos`), because `swiftui` is one of the keywords that
   narrowing keeps.
2. **The keyword naming the host, not the target.** `Bash 3.2 (macOS-portable, no assoc arrays)`
   says which shell, not which UI.

The script's own header already anticipated the class — it strips code spans "to avoid false
positives when SPEC.md mentions Swift/SwiftUI as keyword patterns … (not as a UI target)". The
strip covers *inside a code span*; it covers neither *inside a longer identifier* nor *naming the
host*.

### A third finding, latent

`mac app` **never matches `macOS app`** — only the literal "Mac app". The keyword was nearly dead
before this change.

## Decision

### D1 — Two boundary sets, deliberately different

- **Keyword boundaries** treat `-` as part of a word, so `macos-ux` and `swiftui-pro` are single
  tokens and never match. That closes class 1, including the instance the issue did not report.
- **Noun boundaries** treat `-` as a separator, because `window-based` and `menu-driven` are
  ordinary English and the noun inside them is still a noun.

Using the keyword set for both lost `A window-based macOS tool`. **The two halves of the fix
interfered**, and the fixtures caught it — the regex reads fine either way.

### D2 — Bare `macos`/`mac os` must keep company; the strong keywords need none

`swiftui`, `appkit`, `menu bar` declare a UI target on their own. The bare platform name does not,
so it counts only within 60 characters — either side, same sentence — of a UI noun (`app`, `window`,
`menu`, `toolbar`, `interface`, `hig`, `settings`, `ui`, `utility`).

**Measured in both directions before shipping.** Corpus false positives **6 → 0**. Genuine macOS-UI
specs still detected: a SwiftUI stack line, a menu bar utility, a `macOS app … window, toolbar`
objective, a `small macOS utility` with no framework named, an AppKit/NSWindow/HIG section, and a
UI noun placed before the platform name.

### D3 — The cost is stated as an assertion, not left to be discovered

One fixture is deliberately **not** detected: `A macOS daemon that watches a directory and writes a
log.` A headless daemon has no window, navigation or menu, so Gate 1c has nothing to offer it. That
is `M7`, labelled as the deliberate cost rather than omitted from the test.

### D4 — A CI-runnable harness, because the existing one is CI-dark

Four `detect-macos` assertions already lived in `concept-to-code/tests/run-tests.sh`, which resolves
`SKILL_DIR="$HOME/.claude/skills/…"` — the **deployed** copy. **Fourth instance of the class
ADR-0032 named by name.** All four still hold against the new script and are re-homed into section
`P` of the new hermetic harness, where they run in CI for the first time. The original file is
byte-untouched, exactly as ADR-0032 handled the same situation.

## What running it found

**An empty ERE alternative silently disables the whole rule.** A draft wrote the proximity clause as
`(…|)`, which BSD grep rejects with `empty (sub)expression` — and the corpus sweep then reported
**zero false positives while the rule was not running at all**. A check that did not run, read as a
check that found nothing, inside the measurement built to verify the fix.

`bash -n` cannot see it: the pattern is a string until grep reads it, so the script parses and fails
only at run time. Two assertions close it: `M20b` counts errors as a **third** sweep outcome
distinct from `NOT_MACOS`, and `M21` pins the construct out of the source.

**`M21`'s first draft failed on a correct file** — its needle `|)` matched the script's own header
comment explaining why not to use the construct. Rule 12, in a test written the same hour as an ADR
citing rule 12. Comment lines are now excluded.

## Verification

25 assertions in the new `macos-detect.test.sh`, registered in both CI registries.

Five defects planted, each reverted from a checksummed backup:

| plant | fires |
|---|---|
| the pre-#232 keyword list restored | **M7, M8, M9, M10, M11, M20c** |
| the two boundary sets merged | M1-M11, P1-P4, M20b, M22 |
| the empty ERE alternative reintroduced | M1-M11, P1-P4, **M20b, M21** |
| the noun-before-platform arm dropped | M6 |
| the proximity requirement dropped | M7, M11, M20c |

Full harness 54/54.

## Consequences

- **Gate 1c will now fire on strictly fewer SPECs.** Correct here — it fired on six and should have
  fired on none — but it is a detector being narrowed, and a macOS SPEC that names neither a
  framework nor a UI noun will no longer reach the gate.
- The proximity window is 60 characters and stops at a sentence boundary. A declaration split
  across two sentences is not detected. Stated rather than discovered.
- `mac app` is kept though nearly dead: it catches the literal "Mac app", which the proximity rule
  would miss (no "OS"). Neither is load-bearing alone.
- The skill-private `run-tests.sh` remains `$HOME`-coupled and CI-dark. This ADR re-homes four
  assertions out of it; it does not fix the file.
