---
name: rtf8-audit-symlink-escape
description: Measured mechanics of the tracked-symlink scope escape in codex-reviewer.sh's audit ALLOWED_FILES set, why the os.sep separator is load-bearing, and the backtick trap that makes any comment in that formatter shell-executable
metadata:
  type: project
---

Measured on 2026-09-06 fixing an RTF cycle-8 SECURITY finding on
`staging/plugin/scripts/codex-reviewer.sh` (audit mode). Same file and same downstream consumer as
[[rtf6-audit-file-scope-validation]] (which added the per-finding scope check this defect walks
straight through) and [[rtf7-audit-cwd-reporoot]].

**The scope check was sound; the SET it checks against was not.** `ALLOWED_FILES` was built by
realpath-ing each `FILE_LIST` entry, and `FILE_LIST` is `git ls-files` output, which lists TRACKED
SYMLINKS beside regular files — `enumerate-sources.sh` applies no mode or extension filter, only
exclude-globs. `realpath` follows a symlink all the way through, so a tracked
`evil.md -> ../outside/secret.md` put an EXTERNAL absolute path into the allow-set. The per-finding
test then compares the finding's realpath against that set, so a finding naming `evil.md` matches
the entry the symlink itself contributed and passes **by construction**. Measured against the
pre-fix script on a 5-file scratch repo: exit 0, EMPTY stderr, `file` emitted as
`<tmp>/outside/secret.md`. The generalisable lesson: an allow-set derived by a resolution function
must be re-validated against the boundary it claims to describe — resolving and validating are not
the same operation, one level up from that same sentence in the per-finding check's own comment.

**The naive-prefix sibling is a real, reachable second shape, not a textbook caveat.** A tracked
`sneak.md -> ../<root-basename>-other/x.md` resolves to a path that `startswith(_repo_root_real)`
is TRUE for while being entirely outside the tree. Measured with the same fixture, so the guard is
`_abs == _repo_root_real or _abs.startswith(_repo_root_real + os.sep)` and the `os.sep` is the
half that stops it. Both shapes carry their own `# plant:` declaration (CX43) because the
containment test and the separator fail independently: deleting the test admits both, dropping the
`os.sep` admits only the sibling.

**A COMMENT inside the audit formatter is shell code.** All three formatters are
`python3 -c "..."` bodies in DOUBLE quotes, so backticks and `$` are expanded by the shell before
python ever sees the text. A first draft whose comment said "FILE_LIST is \`git ls-files\` output"
executed `git ls-files` and `evil.py -> ../outside/secret.py` at parse time and died with a python
SyntaxError quoting a repo filename. Every pre-existing comment in those blocks avoids backticks —
that is a constraint of the site, not a style choice, and nothing in the file said so until now.

**Excluded-entry policy is EXCLUDE-AND-CONTINUE, with a stderr note, never abort.** A tracked
symlink leaving the tree is hygiene in the repo being audited, not a reason to abandon the other
files. One consequence is deliberately left unhandled: a (pathological) repo where EVERY tracked
path escapes leaves `ALLOWED_FILES` empty and trips the pre-existing empty-allow-set guard, which
reports "the in-scope file list did not reach the audit formatter" — right outcome (exit 3, no
artifact, caller falls back to the Claude reviewer), misattributed cause. Not worth a second branch
unless it is ever observed.

**Verifying a plant here does NOT need the full `plant-check.sh` run** (371 plants, one full target-
file run each). Replicating its mutation is enough: `cp -R staging/` to a mktemp, substitute with
`re.compile(r"\s+".join(re.escape(w) for w in needle.split()))` asserting exactly one match, run the
copied test. One caveat that cost a confused minute: `plant-check.sh` copies `docs/` as well, so a
staging-ONLY sandbox reports CX26 and CX27 RED for a missing-ADR reason unrelated to any mutation —
compare against a control copy, never against the in-place run's count.
