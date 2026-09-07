---
name: rtf7-audit-outwrite-guard
description: Measured facts for audit mode's empty-scope --out write guard in codex-reviewer.sh — the four --out write sites and how CX41 isolates one, the shim-free fixture, and the two plant-needle traps (three copies of the bare condition line, "empty findings array" also living in the prompt text)
metadata:
  type: project
---

Measured on 2026-09-06 fixing the RTF cycle-7 MAJOR finding on
`staging/plugin/scripts/codex-reviewer.sh` audit mode: the empty-scope short circuit's own
`printf '[]\n' > "$OUT"` captured no status. Last unguarded write in the chain that
[[rtf4-audit-mktemp-guard]] and [[rtf5-audit-write-grep-guard]] walked; same defect class as
[[codex-audit-git-preconditions-and-path-shape]] and [[review-mode-diff-scope-exit-capture]].

**The unguarded failure, measured against the pre-fix script.** An unwritable `--out` (a path inside
a `chmod 555` directory) on the empty-scope path produced **exit 0 with NO artifact on disk at all** —
not an empty file, nothing. The only evidence was bash's own
`line 360: <path>: Permission denied`, on stderr, which this file's CHECKER contract says callers
never branch on. This one bites harder than the temp-file writes the earlier cycles fixed: those
corrupted a derivation, this one breaks the exit-0 *promise* itself. Verified consumer (rule 17),
not assumed: `deep-refactor/SKILL.md`'s audit dispatch says "Exit `0` → parse `<tmp-<d>.json>` as the
`FINDINGS_SCHEMA` array", so a failed write reads as a clean, zero-finding dimension.

**ADR-0193 §D3 does not forbid the guard, and the comment now says so.** §D3's sentence is "An empty
file list is **not** exit 3: it is exit 0 with an empty `findings` array". That governs the empty
RESULT, not the write carrying it. The original one-line comment ended "— never exit 3 (ADR-0193
§D3)", which a future reader could act on by deleting the guard; it was extended in place to scope
the claim. Worth doing wherever a guard sits under a comment that reads as forbidding it.

**Four `--out` write sites, and `rc -eq 3` plus "no artifact" isolates none of them.** This one plus
the three python formatters (review, diagnose, audit), all failing identically against an unwritable
path. CX41 isolates this one two ways: the message tail `empty findings array`, emitted nowhere
else, and **the stub codex's PROMPT LOG staying empty**, which proves the run short-circuited before
`codex exec` and so cannot have died in a formatter. The empty-prompt-log check is the cheap,
reusable way to prove a shell-level path was taken rather than a post-codex one.

**The fixture needs no shim — the only one in this block that does not.** CX30's healthy repository
is clean, so `--diff-scope uncommitted` reaches the empty-scope branch by the front door (CX33's
control already asserts that), and the sole injected condition is `--out` inside a `chmod 555`
directory. Restore the mode (`chmod 755`) before the suite's EXIT trap runs or `$WORK` cannot be
removed, exactly as CX34 does.

**Two plant-needle traps here, both hit while writing the declaration.** (1) The bare condition line
`if [ "$_write_rc" -ne 0 ]; then` now has **three** copies in the file (two intersection writes plus
this one), so as a needle it is BADPLANT — `plant-check.sh` requires exactly one match. The needle
must span the condition *and* the first words of the message. (2) `plant-check.sh` unescapes the
REPLACEMENT but not the needle, so `\n` in a replacement becomes a real newline: any replacement
quoting `printf '[]\n'` needs `'[]\\n'`. Avoided entirely by picking a needle/replacement pair
containing no backslash — worth doing on purpose. Also note `empty findings array` appears in the
audit PROMPT text ("return an empty findings array"), so that phrase alone is not unique in the file.

**Sibling gap left unfixed, deliberately (bounded scope, reported).** Review mode's own empty-diff
branch has the identical defect: the `{ echo ... } > "$OUT"` heredoc block before `exit 0` captures
no status, so an unwritable `--out` there also exits 0 with no report. Same four-line shape fixes it.
