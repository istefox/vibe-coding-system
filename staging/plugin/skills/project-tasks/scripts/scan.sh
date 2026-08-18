#!/usr/bin/env bash
# scan.sh — deterministic evidence collector for the project-tasks skill.
#
# Emits TSV on stdout, one record per line, first column = record type.
# Never writes anything. Never guesses: every record is an observation.
#
# Usage:
#   bash scan.sh [--root DIR] [--ledger FILE] [--max-markers N]
#
# Record types:
#   MARKER   path  line  kind   text          code marker found in source
#   GITFILE  path  count                      commits touching path (last 30 days)
#   GITLOG   sha   subject                    recent fix:/revert: commits
#   STALE    id    ref   reason               ledger entry whose evidence is gone
#   MAP      key   value                      project map fact
#   NOTE     text                             scan-level note (truncation, skipped dir)

set -uo pipefail

ROOT=""
LEDGER=""
MAX_MARKERS=200

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        ROOT="${2:-}"; shift 2 ;;
    --ledger)      LEDGER="${2:-}"; shift 2 ;;
    --max-markers) MAX_MARKERS="${2:-200}"; shift 2 ;;
    -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
    *) printf 'scan.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# --- resolve root ------------------------------------------------------------
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -z "$ROOT" ] && ROOT="$PWD"
fi

if [ ! -d "$ROOT" ]; then
  printf 'scan.sh: root is not a directory: %s\n' "$ROOT" >&2
  exit 2
fi
cd "$ROOT" || exit 2

# A directory with no VCS, no manifest and no source files is almost certainly
# not a project root. Fail loud rather than emit a confidently empty scan.
if [ ! -d .git ] \
   && [ -z "$(ls -1 package.json pyproject.toml requirements.txt Package.swift Cargo.toml go.mod Makefile 2>/dev/null)" ] \
   && [ -z "$(find . -maxdepth 2 -type f \( -name '*.ts' -o -name '*.js' -o -name '*.py' -o -name '*.swift' -o -name '*.go' -o -name '*.rs' \) -print -quit 2>/dev/null)" ]; then
  printf 'scan.sh: %s does not look like a project root (no .git, no manifest, no sources)\n' "$ROOT" >&2
  exit 3
fi

[ -z "$LEDGER" ] && LEDGER="$ROOT/TODO.md"

# Directories that are never interesting and would flood the output.
PRUNE_DIRS='.git node_modules .venv venv __pycache__ build dist .build DerivedData target vendor .next .nuxt out coverage .mypy_cache .pytest_cache .remember .claude-cache'

emit() { printf '%s\n' "$*"; }
tab() { printf '%s\t' "$@"; }

# --- 1. code markers ---------------------------------------------------------
# Two-part predicate (ADR-0153 D9). A line contributes a marker only when BOTH
# hold, and each half is required by a different measured false positive:
#
#   1. the keyword is in DECLARATION form, colon immediately after it, and
#      preceded by a non-word character so `bugCount` and `TODOS` stay out;
#   2. a comment leader appears EARLIER on the same line, so a keyword written
#      in flowing markdown prose is not a marker.
#
# Half 1 alone admitted `NOT A BUG (ADR-0059 ...)` and `echo NONEMPTY-BUG`, both
# inside `#` comments. Half 2 alone admitted three backticked `TODO:`/`XXX:`
# mentions in a SPEC's prose. Measured 2026-08-17, VCS-023.
#
# The leader is required BEFORE the keyword rather than at the start of the
# line: `foo(); // TODO: fix` is the common real shape and a start-anchored
# predicate drops it. `(.*[^A-Za-z_])?` is what keeps the character immediately
# preceding the keyword a non-word one even when the leader is far to its left;
# a bare `.*` there would readmit `# fooTODO:`.
#
# `*` is ANCHORED and the other leaders are not. ADR-0153 D9 lists `*` in the
# leader set without an anchor, and applied that way it does not achieve the
# ADR's own stated result: measured on this repository, `**declaration form**`
# in a SPEC's flowing prose supplies a `*` and readmits the very line D9 names
# as one of the three cases the leader half rejects. `*` only means "comment"
# as a C block continuation, which is a line-start shape, so it is anchored
# here. The other six can appear after code and must not be.
#
# Both the rg path and the grep fallback take this one expression, and
# selftest.sh's "grep fallback finds the same markers" is what catches a
# divergence. Keep it POSIX ERE: no lookaround, no \b. The leading `^` inside
# the alternation is an anchor in both engines, verified 2026-08-18 against BSD
# grep -E on macOS and against rg, with identical verdicts on nine shapes.
MARKER_RE='(^[[:space:]]*\*|//|#|--|/\*|<!--|;)(.*[^A-Za-z_])?(TODO|FIXME|HACK|XXX|BUG):'

scan_markers() {
  if command -v rg >/dev/null 2>&1; then
    local globs=()
    for d in $PRUNE_DIRS; do globs+=( --glob "!$d/**" ); done
    rg --no-messages --line-number --no-heading --color never \
       --max-columns 300 "${globs[@]}" \
       --glob '!TODO.md' --glob '!*.lock' --glob '!*.min.*' \
       -e "$MARKER_RE" . 2>/dev/null || true
  else
    local prune=()
    for d in $PRUNE_DIRS; do prune+=( -name "$d" -o ); done
    # shellcheck disable=SC2086
    find . \( "${prune[@]}" -false \) -prune -o -type f -print 2>/dev/null \
      | grep -v -e '/TODO\.md$' -e '\.lock$' -e '\.min\.' \
      | while IFS= read -r f; do
          grep -InE "$MARKER_RE" -- "$f" 2>/dev/null | sed "s|^|$f:|"
        done
  fi
}

marker_count=0
truncated=0
while IFS= read -r raw; do
  [ -z "$raw" ] && continue
  # raw looks like: ./path/to/file.ts:88:    // FIXME: leaks on retry
  path="${raw%%:*}"; rest="${raw#*:}"
  line="${rest%%:*}"; text="${rest#*:}"
  case "$line" in ''|*[!0-9]*) continue ;; esac
  # Classify on the declaration form, not on the bare keyword: a line matched on
  # `TODO:` must not be recorded as a BUG because the word appears earlier in it.
  kind="$(printf '%s' "$text" | grep -oE '(TODO|FIXME|HACK|XXX|BUG):' | head -1 | tr -d ':')"
  [ -z "$kind" ] && kind="TODO"
  # collapse whitespace and strip common comment leaders for readability
  text="$(printf '%s' "$text" \
    | sed -e 's/^[[:space:]]*//' -e 's|^[/#*-]*[[:space:]]*||' -e 's/[[:space:]]\{2,\}/ /g' \
    | cut -c1-200)"
  marker_count=$((marker_count + 1))
  if [ "$marker_count" -gt "$MAX_MARKERS" ]; then truncated=1; continue; fi
  emit "MARKER	${path#./}	$line	$kind	$text"
done <<EOF
$(scan_markers)
EOF

if [ "$truncated" -eq 1 ]; then
  emit "NOTE	marker scan truncated at $MAX_MARKERS of $marker_count hits — report the cap to the user, do not present the list as complete"
fi

# --- 2. recent git activity --------------------------------------------------
if [ -d .git ] && command -v git >/dev/null 2>&1; then
  git log --since='30 days ago' --name-only --pretty=format: 2>/dev/null \
    | grep -v '^$' | sort | uniq -c | sort -rn | head -25 \
    | while read -r count path; do emit "GITFILE	$path	$count"; done

  git log --since='30 days ago' --pretty=format:'%h	%s' 2>/dev/null \
    | grep -iE '^[^	]+	(fix|revert|hotfix)' | head -15 \
    | while IFS=$'\t' read -r sha subject; do emit "GITLOG	$sha	$subject"; done
fi

# --- 3. stale ledger references ---------------------------------------------
# An open entry that points at a file:line which no longer exists, or at a code
# marker that has been removed, is a close candidate. Never auto-closed here:
# this script only reports the evidence.
if [ -f "$LEDGER" ]; then
  grep -nE '^- \[[ -]\] ' "$LEDGER" 2>/dev/null | while IFS= read -r entry; do
    id="$(printf '%s' "$entry" | grep -oE '`[A-Z]+-[0-9]+`' | head -1 | tr -d '`')"
    [ -z "$id" ] && continue
    ref="$(printf '%s' "$entry" | grep -oE '`[^`]+\.[A-Za-z0-9]+(:[0-9]+)?`' | head -1 | tr -d '`')"
    [ -z "$ref" ] && continue
    file="${ref%%:*}"
    lineno="$(printf '%s' "$ref" | grep -oE ':[0-9]+$' | tr -d ':')"
    if [ ! -f "$file" ]; then
      emit "STALE	$id	$ref	file-missing"
      continue
    fi
    if [ -n "$lineno" ]; then
      total="$(wc -l < "$file" | tr -d ' ')"
      if [ "$lineno" -gt "$total" ]; then
        emit "STALE	$id	$ref	line-out-of-range"
        continue
      fi
    fi
    if printf '%s' "$entry" | grep -q 'src:marker'; then
      if ! grep -qE "$MARKER_RE" -- "$file" 2>/dev/null; then
        emit "STALE	$id	$ref	marker-gone"
      fi
    fi
  done
fi

# --- 4. project map facts ----------------------------------------------------
map() { emit "MAP	$1	$2"; }

[ -d .git ] && map vcs "git branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
map root "$ROOT"

if [ -f package.json ]; then
  map manifest package.json
  for key in main test build dev lint typecheck; do
    val="$(grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" package.json | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
    [ -n "$val" ] && map "npm.$key" "$val"
  done
fi
[ -f pyproject.toml ]  && map manifest pyproject.toml
[ -f requirements.txt ] && map manifest requirements.txt
[ -f Package.swift ]   && map manifest Package.swift
[ -f Cargo.toml ]      && map manifest Cargo.toml
[ -f go.mod ]          && map manifest go.mod
[ -f Makefile ]        && map manifest Makefile

# TOFU-trusted test command used across the vibe-coding chain.
[ -f .claude/test-cmd ] && map test-cmd "$(head -1 .claude/test-cmd)"

for candidate in src/main.ts src/main.js src/index.ts src/index.js src/main.py main.py app/main.py \
                 src/App.swift Sources/main.swift cmd/main.go src/main.rs; do
  [ -f "$candidate" ] && map entrypoint "$candidate"
done

for d in src app lib Sources packages services; do
  [ -d "$d" ] && map source-dir "$d"
done

if [ -d docs/architecture ]; then
  find docs/architecture -maxdepth 1 -name 'ADR-*.md' 2>/dev/null | sort | tail -10 \
    | while IFS= read -r adr; do
        title="$(grep -m1 '^# ' "$adr" 2>/dev/null | sed 's/^# //')"
        map adr "${adr##*/}${title:+ — $title}"
      done
fi

for report in docs/reviews docs/reports .claude/reports; do
  [ -d "$report" ] && map review-dir "$report"
done

[ -f CLAUDE.md ] && map context CLAUDE.md
[ -f PROJECT.md ] && map roadmap PROJECT.md
[ -f "$LEDGER" ] && map ledger "${LEDGER#$ROOT/}" || map ledger "absent — create from template"

exit 0
