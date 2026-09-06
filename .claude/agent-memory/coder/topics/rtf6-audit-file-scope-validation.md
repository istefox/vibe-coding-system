---
name: rtf6-audit-file-scope-validation
description: Measured blast radius of validating a finding's `file` against FILE_LIST in codex-reviewer.sh audit mode — the six stub-payload assertions it invalidates, the CX13 hyphen constraint on fixture basenames, and the 2>&1 that was hiding the formatter's stderr
metadata:
  type: project
---

Measured on 2026-09-06 fixing the RTF cycle-6 MAJOR finding `ad0a3fd5` on
`staging/plugin/scripts/codex-reviewer.sh` (audit mode): the model-supplied `file` was normalised
to absolute but never checked against the audited scope, and `deep-refactor/SKILL.md` forwards that
value into an edit-capable agent's dispatch prompt without re-validating it.

**Validating `file` invalidates every stub payload that names a fabricated path — six assertions,
not one.** The brief predicted CX29 only. Measured with a control build (HEAD's script and the
edited one run against identical scratch checkouts of the whole repo, same fixture, same CWD):
baseline `PASS=35 FAIL=0`, edited `PASS=29 FAIL=6` — CX11, CX12, CX13, CX18, CX19, CX29. All six
trace to three payload literals (`src/A.swift`, `src/B.swift`, `src/Sec.swift`) and one absolute
literal (`/already/absolute/src/B.swift`) that do not exist in the repository the suite audits (its
own CWD). CX12/CX13 fail transitively: they read `$CX11_OUT`, which is never written once CX11's
run exits 3. Before assuming a scope check breaks one assertion, grep the whole suite for `"file"`
in payload heredocs — a stub payload is shared across assertion blocks far more often than the
block comments suggest.

**A fixture path for these assertions has to satisfy CX13's id regex, not just be in scope.** CX13
pins `^<dimension>-[^-]+-.{3}$` on the synthesised id, whose middle segment is
`os.path.basename(file)`. Any replacement fixture file whose basename contains a hyphen
(`codex-reviewer.sh`, most scripts in this repo) makes CX13 fail for a second, unrelated reason.
Hyphen-free files that ARE in `enumerate-sources.sh`'s output here: `CLAUDE.md`, `PROJECT.md`,
`SPEC.md`.

**`python3 -c "..." 2>&1` was sending the audit formatter's diagnostics to a stream the script says
it never uses.** All three mode formatters carried the trailing `2>&1`, so every `sys.stderr.write`
inside them landed on the script's stdout — which `codex-audit-mode.test.sh`'s own `cr()` helper
discards (`>/dev/null`), and whose header comment states codex-reviewer.sh "never touches stdout ...
the exit code is the signal, not stdout". Removed on the audit invocation only (review and diagnose
were out of scope for that fix). If a future assertion on a formatter message comes back empty from
`CR_ERR`, this redirect is the first thing to check — the message is not missing, it is on the other
stream.

**`os.path.realpath` on both sides is what makes the membership test survive macOS.** The allow-set
entries and the finding's path are both realpath-resolved, so a scratch repo under `/var/...`
(symlink to `/private/var`) compares correctly. The consequence is that the emitted `file` is now
the realpath'd form: under a symlinked checkout prefix it will differ from the plain
`REPO_ROOT + path` string that Gate 1's Claude-side findings carry, and those two would not dedup.
Not reachable from `/Users/...` checkouts, where realpath is identity — but it is the trade-off that
`file` and the allow-set are canonicalised together rather than emitted raw. See
[[codex-audit-git-preconditions-and-path-shape]] for why `file` is absolute at all.
