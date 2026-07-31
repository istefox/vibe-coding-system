#!/bin/bash
# review-triage-fix: cross-cycle finding state (deterministic).
#   diff   <state-file>  : stdin TSV "sev<TAB>loc<TAB>problem"
#       → per-finding "id<TAB>sev<TAB>loc<TAB>{NEW|STILL-OPEN|REGRESSED}",
#         then RESOLVED rows, then COUNTS line, then CONVERGENCE line. No write.
#   commit <state-file>  : stdin TSV "sev<TAB>loc<TAB>problem<TAB>status"
#         (status open|resolved) → write JSON state; gitignore it if in a git tree.
set -u
sub="${1:-}"; SF="${2:-}"
if [ -z "$sub" ] || [ -z "$SF" ]; then
  echo "usage: triage-state.sh diff|commit <state-file>" >&2; exit 2
fi
fid(){ # "sev|loc|problem" → first 8 hex of sha256 (whitespace-normalized)
  # sed (not `tr -s ' \t'`): on BSD/macOS tr's \t handling is unreliable.
  # Collapse runs of whitespace, strip spaces around the | joins, trim ends —
  # so the same finding hashes identically regardless of incidental spacing.
  local s; s=$(printf '%s' "$1" | sed 's/[[:space:]][[:space:]]*/ /g; s/ *| */|/g; s/^ //; s/ $//')
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$s" | shasum -a 256 | awk '{print substr($1,1,8)}'
  else printf '%s' "$s" | sha256sum | awk '{print substr($1,1,8)}'; fi
}
case "$sub" in
diff)
  # Load previous state into a temp file: "id<TAB>status" per line
  PSTATE=$(mktemp); : > "$PSTATE"
  if [ -f "$SF" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.[] | "\(.id)\t\(.status)"' "$SF" 2>/dev/null > "$PSTATE"
  fi
  # Read stdin findings, compute per-finding status, accumulate output
  FINDINGS=$(cat)
  OUT=$(mktemp); : > "$OUT"
  newc=0; openc=0; regc=0
  SEEN=$(mktemp); : > "$SEEN"
  while IFS=$'\t' read -r sev loc prob; do
    [ -z "${sev}${loc}${prob}" ] && continue
    id=$(fid "$sev|$loc|$prob")
    printf '%s\n' "$id" >> "$SEEN"
    p=$(grep -m1 "^${id}	" "$PSTATE" | awk -F'\t' '{print $2}')
    if   [ -z "$p" ];           then st=NEW;        newc=$((newc+1))
    elif [ "$p" = "resolved" ]; then st=REGRESSED;  regc=$((regc+1))
    else                             st=STILL-OPEN; openc=$((openc+1)); fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$sev" "$loc" "$st" >> "$OUT"
  done <<EOF
$FINDINGS
EOF
  resc=0; prevopen=0
  while IFS=$'\t' read -r pid pst; do
    [ -z "$pid" ] && continue
    [ "$pst" = "open" ] && prevopen=$((prevopen+1))
    if [ "$pst" = "open" ] && ! grep -q -x "$pid" "$SEEN" 2>/dev/null; then
      printf '%s\t-\t-\tRESOLVED\n' "$pid" >> "$OUT"; resc=$((resc+1))
    fi
  done < "$PSTATE"
  cat "$OUT"
  curopen=$((openc+regc+newc))
  printf 'COUNTS\tresolved=%s\topen=%s\tnew=%s\tregressed=%s\n' "$resc" "$curopen" "$newc" "$regc"
  if   [ "$curopen" -eq 0 ]; then
    printf 'CONVERGENCE\tclean: 0 open\n'
  elif [ "$prevopen" -gt 0 ] && [ "$curopen" -lt "$prevopen" ] && [ "$regc" -eq 0 ]; then
    printf 'CONVERGENCE\tconverge: %s→%s open\n' "$prevopen" "$curopen"
  elif [ "$resc" -gt 0 ] && [ "$newc" -gt 0 ]; then
    printf 'CONVERGENCE\toscillates: %s resolved, %s new\n' "$resc" "$newc"
  else
    printf 'CONVERGENCE\tstable: %s open\n' "$curopen"
  fi
  rm -f "$PSTATE" "$OUT" "$SEEN"
  ;;
commit)
  command -v jq >/dev/null 2>&1 || { echo "triage-state: jq missing" >&2; exit 1; }
  tmp=$(mktemp); echo '[]' > "$tmp"
  while IFS=$'\t' read -r sev loc prob status; do
    [ -z "${sev}${loc}${prob}" ] && continue
    case "$status" in open|resolved) ;; *) status=open;; esac
    id=$(fid "$sev|$loc|$prob")
    jq --arg id "$id" --arg s "$sev" --arg l "$loc" --arg st "$status" \
       '. += [{id:$id,sev:$s,loc:$l,status:$st}]' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
  done
  mkdir -p "$(dirname "$SF")" 2>/dev/null || true
  mv "$tmp" "$SF"
  d=$(cd "$(dirname "$SF")" 2>/dev/null && pwd) || exit 0
  if command -v git >/dev/null 2>&1 && git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Use --show-prefix (repo-relative, no path canonicalization) instead of
    # string-subtracting --show-toplevel: on macOS $TMPDIR is /var → /private/var
    # symlinked, so a literal prefix-strip would mismatch and corrupt the entry.
    top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)
    pref=$(git -C "$d" rev-parse --show-prefix 2>/dev/null)
    if [ -n "$top" ]; then
      gi="$top/.gitignore"
      # A GLOB, never the resolved per-branch path (issue #250). The state file is per-branch by
      # design, so appending its literal name left one entry behind per branch, forever: the branch
      # is deleted at merge, the .gitignore line is not. It also defeated its own purpose — a
      # per-branch line protects exactly one branch, and the NEXT branch is unprotected until its
      # own cycle appends its own line. One glob covers every branch including the first cycle on a
      # new one, and never grows.
      glob="${pref}.triage-fix-last-*.json"
      # `git check-ignore` answers "is this path already ignored", by ANY rule, in any file — a
      # literal grep for the glob only recognises the one line this script writes, and would append
      # a duplicate next to a broader rule a human had already added by hand. That is not
      # hypothetical: this repository's own .gitignore carried `.claude/.triage-fix-last*.json`
      # before the glob below existed.
      #
      # EXIT-CODE CONTRACT: 1 means "not ignored" and is a CLEAN result, not a failure; only 128 is
      # an error. Anything non-zero takes the append branch, which is the safe direction — the
      # append is idempotent, so the worst case is a no-op.
      # The path is passed as a BASENAME because `git -C "$d"` runs from "$d": a relative $SF would
      # be resolved against "$d" a second time and match nothing, so the check would report
      # "not ignored" for a file that is ignored. Seen live against the broader-rule fixture.
      if git -C "$d" check-ignore -q -- "$(basename "$SF")" 2>/dev/null; then
        :   # already covered by some rule — nothing to add
      elif ! { [ -f "$gi" ] && grep -F -x -q -- "$glob" "$gi" 2>/dev/null; }; then
        printf '%s\n' "$glob" >> "$gi"
      fi
    fi
  fi
  ;;
*) echo "usage: triage-state.sh diff|commit <state-file>" >&2; exit 2;;
esac
exit 0
