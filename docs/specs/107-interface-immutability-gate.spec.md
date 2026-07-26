# SPEC — Interface immutability gate

Source: GitHub issue #107

## Objectives
1. Let a project declare a protected public surface.
2. Report any removal or signature change to that surface in a diff.
3. Stay completely inert when no declaration exists.

## Scope
In: a `.claude/protected-interfaces` file convention; a check script; a call in c2c Step 6; architect population at Gate 2; a new test file in both CI registries.
Out: language-server-grade signature parsing; multi-version API support.

## Stack
Bash 3.2, diff-driven, no language server.

## Architecture
- New: `.claude/protected-interfaces` — one entry per line, an exact signature or a path glob, `#` comments allowed.
- New: check script under `staging/plugin/scripts/`.
- Modified: `concept-to-code/SKILL.md` Step 6, before the review closes.
- Modified: the architect's Gate 2 instructions — populate the file when the plan declares a public surface.
- New: test file in both CI registries.

## Data model
One protected entry per line. Blank lines and `#` comments ignored.

## API / Interfaces
`<script> --root <dir> [--diff]` → `PROTECTED<TAB><entry><TAB><file>:<line><TAB>removed|changed` lines. Exit 0 always; the caller decides severity. Absent declaration file → allow-and-exit with no output, the same inert-by-construction design that keeps `write-scope-enforce.sh` harmless outside its one call site.

## UI flows
Findings surface in the Step 6 review output.

## Edge cases
- No `.claude/protected-interfaces` → no output, exit 0.
- An **added** function is never reported: accrete, don't destroy.
- A moved-but-identical signature should not be reported as removed if the entry is a signature rather than a path.
- A comment-only or blank-line file behaves as absent.

## Success criteria
- [ ] With no declaration file, the check produces no output and exits 0.
- [ ] A removed protected function is reported with `file:line`.
- [ ] An added function is not reported.
- [ ] A signature change to a protected entry is reported.
- [ ] The new test file is registered in BOTH CI registries.
