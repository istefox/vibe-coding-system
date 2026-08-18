# Capture sources

## Contents

- Source 1 — the current session (heuristics)
- Source 2 — code markers
- Source 3 — git history
- Source 4 — review artifacts
- Source 5 — project map
- Deduplication
- What never becomes an entry

## Source 1 — the current session

The only source that cannot be rebuilt afterwards. Once the context is compacted it is gone,
which is why this skill is run *before* `/clear` and not after.

Re-read the conversation from the start of the session and look for these nine signals.

**1. A command that failed and was never made to pass.**
A non-zero exit, a build error, a red test whose fix was not confirmed later in the session.
→ P1 if it is a test or a build; P2 otherwise. Quote the actual error, not a paraphrase.

**2. A stack trace or runtime exception.**
Even if it happened in a throwaway script: it says something about the code.
→ Entry with the file and line from the trace.

**3. A workaround stated as temporary.**
Phrasings: "for now", "temporarily", "as a stopgap", "we'll do it properly later", "per ora",
"provvisorio", "poi lo sistemiamo". A temporary fix with no entry is permanent by default.
→ P2, `Open Issues`, reference the file that carries the workaround.

**4. Scope explicitly cut.**
"Let's skip the tests for now", "only the happy path", "I'll handle the edge case later",
"non serve gestire questo caso adesso".
→ P2 in `Open Issues` if the gap is a defect, P3 in `Backlog / To Add` if it is a feature.

**5. An assumption that was never verified.**
Anything said in the form "assuming X", "should be", "presumably", where the check never
happened. Especially anything assumed about an external API's behaviour.
→ P2, and phrase the entry as the verification to perform, not as the assumption.

**6. A question from the assistant the user never answered.**
It was left hanging because the work moved on. It is still open.
→ `Blocked / Decisions Needed`, phrased as the decision to take.

**7. A decision taken in chat and never written down.**
An architectural choice discussed and adopted with no ADR.
→ `Blocked / Decisions Needed` if still reversible, otherwise an entry to write the ADR.

**8. A TODO the user dictated in words.**
"Remind me to…", "we still need to…", "manca ancora…". Take it verbatim, do not improve it.
→ Section and priority as stated; ask if the priority is unclear.

**9. Something fixed here that is broken elsewhere too.**
The same defect pattern in a file that was not touched.
→ P2, one entry per file, and say which fix it mirrors.

**Confidence rule.** For each candidate ask: could the user point at the exact moment in the
session this came from? If not, drop it. A ledger that accumulates plausible-sounding entries
stops being read within a week, and a ledger nobody reads is worse than none.

## Source 2 — code markers

`scripts/scan.sh` emits `MARKER path line kind text`.

- `FIXME` and `BUG` → `Open Issues`, P2 by default, P1 if the text mentions data, security,
  crash or corruption.
- `HACK` and `XXX` → `Open Issues`, P2, technical debt.
- `TODO` → `Backlog / To Add`, P3, unless the text names a defect.

Use the marker's own text as the entry text if it is a full sentence; otherwise write what the
surrounding code actually needs. A marker already tracked by an entry is not a new candidate.

## Source 3 — git history

`GITFILE` and `GITLOG` records are **context, not candidates**. Never open an entry just
because a file changed. Their use is:

- a file with a high recent-commit count and an open P2 entry → evidence to raise the priority;
- a `revert:` with no follow-up commit → a real candidate, P2, "reverted X, root cause unknown";
- a `fix:` touching the same file as an open entry → check whether that entry is now closable.

## Source 4 — review artifacts

Look for, in order: `docs/reviews/`, `docs/reports/`, `.claude/reports/`, and the chain
manifest. Import findings that were **not** fixed, keeping the original severity mapping:
critical/high → P1, medium → P2, low → P3, and note the report in the entry text.

Security findings are import-only. This skill records them; fixing them is
`security-audit`'s and the fixing agents' job, never this one's.

## Source 5 — project map

From the `MAP` records plus a look at the tree. Populate: entry point, main modules with a
three-word gloss each, build and test commands (prefer `.claude/test-cmd` when present), the
key ADRs, and the invariants stated in `CLAUDE.md`.

Keep it under fifteen lines. This section answers "what is this project" for a session that
starts cold — it is not documentation, and it must not duplicate `CLAUDE.md`.

Refresh it only where reality has moved: an unchanged map is a valid outcome.

## Deduplication

Two candidates are the same issue when they point at the same file *and* describe the same
symptom, whatever the wording. Check in this order, and stop at the first hit:

1. Same ID already present → update in place.
2. Same file reference and semantically equal symptom → update in place.
3. A marker whose file and line match an existing `src:marker` entry → update the line number
   only.
4. Otherwise → new entry.

When updating rather than adding, `opened:` is preserved. That date is the only thing that
makes ageing visible.

## What never becomes an entry

- Anything fixed and verified inside the same session.
- Style opinions with no defect behind them.
- A *new local entry* duplicating a `PROJECT.md` roadmap feature — that file owns the order of
  work. This is not an exclusion of roadmap items from the ledger: an item that is also an open
  GitHub issue appears in the `GitHub Issues` section with a pointer to its phase. What never
  becomes an entry is a second, hand-written copy of a roadmap row.
- Generic wishes ("improve performance", "add more tests") with no file and no symptom.
- Anything in a gitignored or vendored path.
