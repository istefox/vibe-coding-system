# SPEC — claude-md-slim: whole-line content union check

Source: GitHub issue #36

## Objectives
1. Turn the ADR-0019 content-preservation hard gate from substring matching into whole-line matching so real content loss is detected (audit finding 2.8).

## Scope
In (`staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh:55`, vendored by issue #28; this script is the sole ADR-0019 content-preservation gate, run both before the HITL diff and after apply):
- Line 55 uses `grep -qF -- "$line" "$outfile"`: fixed-string but substring, not whole-line. Reproduced: an original containing `## Git` and `- npm` passes when the outputs contain only `## GitHub Actions` and `- npm install -g foo`. Duplicate original lines count as preserved when a single copy survives. ADR-0019 explicitly rejects best-effort checking.
- Switch to whole-line fixed match (`grep -qxF`), tolerating trailing-whitespace differences by trimming both sides before comparison.
- Compare per-line occurrence counts between original and union so duplicated lines must survive with the same multiplicity, or document explicitly why multiplicity is out of scope (exemption added to the SKILL text).

Out:
- Any file under `~/.claude`.
- Other claude-md-slim pipeline steps.

## Stack
Bash 3.2-compatible shell; fixtures + harness tests in docs-ci.

## Architecture
One script (`content-union-check.sh`) plus its fixtures/tests; possibly a documented exemption line in the SKILL text.

## Data model
None.

## API / Interfaces
Gate contract unchanged (exit nonzero on content loss); semantics tightened to whole-line with trailing-whitespace tolerance.

## UI flows
None.

## Edge cases
- `## Git` present only as a prefix of `## GitHub Actions` in the union: must FAIL.
- A line present twice in the original and once in the union: must FAIL, or the documented exemption is added to the SKILL text.
- Lines differing only in trailing whitespace: must still count as preserved.

## Success criteria
- [x] New fixture: original with `## Git` dropped and `## GitHub Actions` present in a rules file must FAIL the gate
- [x] New fixture: a line present twice in the original and once in the union must FAIL (or the documented exemption is added to the SKILL text)
- [x] All existing claude-md-slim tests pass
- [x] Script stays bash 3.2 clean
- [x] No file under `~/.claude` modified
