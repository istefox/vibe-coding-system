---
name: rtf5-audit-write-grep-guard
description: Measured fixture recipes for audit mode's two printf guards and the grep-intersection guard in codex-reviewer.sh — mktemp call ordinals, the read-only-dir shim that fails a write after a successful mktemp, and which stderr survives
metadata:
  type: project
---

Measured on 2026-09-06 fixing the RTF cycle-5 MAJOR finding on
`staging/plugin/scripts/codex-reviewer.sh` audit mode: the two `printf ... > "$tmpfile"` writes and
the `grep -Fxf` intersection were unguarded. This is the residual that
[[rtf4-audit-mktemp-guard]] scoped and deliberately left; the four-line capture-then-`if` shape it
predicted is what shipped. Same defect class as
[[codex-audit-git-preconditions-and-path-shape]] and [[review-mode-diff-scope-exit-capture]].

**Fixture recipe 1 — failing the intersection only.** `grep -Fxf` appears exactly once in the whole
process tree (`enumerate-sources.sh` does not use it), so a PATH shim that scans `"$@"` for the
literal `-Fxf`, exits 2, and `exec /usr/bin/grep "$@"` otherwise fails precisely the line under test
and nothing else. No counter needed. Measured: exit 3, message names the grep status.

**Fixture recipe 2 — failing a write AFTER a successful mktemp.** A full filesystem is not
reproducible, but an unwritable *path* is: shim `mktemp` to print a path inside a `chmod 555`
directory and exit 0. The mktemp guard passes (status 0, non-empty variable), then bash's redirection
cannot open the file and the simple command returns 1 without running `printf`. Counting shim over a
shared counter file, forwarding to `/usr/bin/mktemp` otherwise.

**Confirmed mktemp call ordinals (process-wide, `--diff-scope` audit run):** call **3** is
`ALL_FILES_FILE`, call **4** is `CHANGED_FILES_FILE`, after `enumerate-sources.sh`'s own two. This
re-measures and confirms the ordinals recorded in [[rtf4-audit-mktemp-guard]] against a *different*
failure mode (write-fails rather than mktemp-fails), so the number is now evidence twice over.

**Which stderr survives, and why it differs per guard.** On a failed write, bash's own
`line NNN: <path>: Permission denied` reaches stderr alongside the DID-NOT-RUN line — the redirection
diagnostic is not discarded anywhere. On a failed intersection, the shim's stderr is swallowed by the
line's own `2>/dev/null`, so the captured status is the *only* evidence. A test asserting on stderr
must therefore assert on the script's own message for the grep case, never on grep's.

**All three guards write no `--out` artifact and `rm -f` both temp files before `exit 3`** — the
block runs before the `trap ... EXIT` installed further down, so nothing else would clean them up.
CX33's "leak no temp file" assertion already pins that property for the mktemp pair.
