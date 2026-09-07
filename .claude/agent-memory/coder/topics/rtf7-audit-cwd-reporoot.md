---
name: rtf7-audit-cwd-reporoot
description: Measured shape of the single shared `codex exec` invocation in codex-reviewer.sh, why the working-directory fix is a subshell `cd` and not codex's own `--cd` flag or absolute paths, and the stub-codex facts the CX42 regression rests on
metadata:
  type: project
---

Measured on 2026-09-06 fixing the RTF cycle-7 MAJOR finding on
`staging/plugin/scripts/codex-reviewer.sh` audit mode: the prompt's audited paths are repo-relative
while `codex exec` inherited the CALLER's cwd. Same family as
[[codex-audit-git-preconditions-and-path-shape]] (which is where the relative-in/absolute-out
contract is recorded) and [[rtf7-audit-outwrite-guard]].

**The `codex exec` call site is ONE line shared by all three modes, and REPO_ROOT exists in only
one of them.** Any fix at that site has to be mode-neutral: `set -u` is on and `REPO_ROOT` is
assigned inside the `elif [ "$MODE" = "audit" ]` branch, so naming it at the invocation would abort
review and diagnose with an unbound-variable error. The shape that works is a variable initialised
beside `DIFF_CONTENT`/`FILE_LIST` (`CODEX_CWD="$PWD"` — the cwd the process already inherits, so
review and diagnose are byte-identical) and overwritten in the audit branch. This generalises: any
future per-mode argument to `codex exec` needs the same default-then-override, not a conditional at
the call site.

**The bug is a FALSE CLEAN AUDIT, not a crash, and that is why it survived seven review cycles.**
Measured against the pre-fix script from `<repo>/sub/deep` on a two-file tracked tree: stub-codex
cwd was the nested directory, 2 of 2 audited paths resolved to files that do not exist, exit 0,
empty findings array. Identical, from outside, to a dimension with nothing to report — and
`deep-refactor/SKILL.md` then records the dimension as audited. A nested path (`sub/deep/x.swift`
read from `<repo>/sub/deep`) is the sharp fixture: it looks for `sub/deep/sub/deep/x.swift` and
cannot collide with anything real, where a root-level path is only wrong by one level.

**Option A (subshell `cd`), not codex's own `--cd`, and not Option B (absolute paths).** All three
were live-checked before choosing:

- `codex exec` in codex-cli 0.153.4 DOES have `-C, --cd <DIR>` ("use the specified directory as its
  working root"), and the default working root is the process cwd — measured, not assumed: running
  `codex exec` from a non-git directory refuses with "Not inside a trusted directory", before any
  model call. So the subshell `cd` reaches the same setting the flag names.
- The flag was rejected because this suite NEVER calls real codex (standing repo rule), so an
  assertion on it could only pin that the flag was PASSED — an instruction to a third-party binary
  (rule 16). A subshell `cd` is an OS-level fact the stub can record with `pwd -P`, which is what
  makes CX42 a behavioural assertion instead of a string check.
- Option B (emit absolute paths into the prompt) was rejected for blast radius: the model would
  then return absolute `file` values, and the audit formatter's id digest is DELIBERATELY keyed on
  the repo-relative value so the same tree yields the same ids from any checkout. Option B makes
  ids checkout-dependent, and the ALLOWED_FILES join would need reworking too.

**Verified the subshell does not move anything else.** `--out` is written by the python formatters,
which run OUTSIDE the subshell: a RELATIVE `--out` still lands in the caller's cwd (measured, run
from a nested dir with `--out relative-out.json`). Everything inside the subshell — `$SCHEMA_FILE`,
`$RAW_OUT`, `$PROMPT_FILE` — is an absolute `mktemp` path. If a future change moves a formatter or a
temp-file creation inside those parentheses, that property is the first thing to re-check.

**The stub codex's argument parser treats any unrecognised token as the PROMPT** (last one wins), so
adding a flag to the real invocation without teaching the stub about it happens to work only because
the prompt is the last argument. It would break silently the moment the prompt stops being last.
CX42 needed no parser change (no new flag), only a third log — the cwd — recorded with `pwd -P`,
because `mktemp -d` hands back `/var/...` on macOS while `git rev-parse --show-toplevel` resolves it
to `/private/var/...` and the two spellings would not compare equal.

**Pre-existing, unrelated RED found while verifying (dated snapshot, not a claim about today):**
`spec-coverage.test.sh` RS7 reported 8 of 201 rows diverging from the frozen baseline on this
branch, all UNCOVERED -> UNSCOPED on archived specs (222-vendor-deployed-only-skills,
365-scope-and-bound-the-autopilot-run, 394-skill-fences-rely-on-word-splitting,
410-order-the-manifest-completed-transit, project-tasks-vendored-bilateral-ledger). The direction
rules out an additive test edit as the cause: UNSCOPED means the spec's scoped test-file set lost a
member, and adding lines to a file scoped to a different feature cannot remove one. `RS7` prints
only a count — the diverging rows are recoverable by re-running
`spec-coverage-baseline-rows.sh --rows` per (spec, plan) pair and diffing against
`spec-coverage-scope-baseline.tsv`, which is what that harness does internally.
