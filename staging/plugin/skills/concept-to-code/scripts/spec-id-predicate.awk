# spec-id-predicate.awk — THE definition of a SPEC requirement declaration (ADR-0072, issue #171).
#
# Loaded as an additional awk program file, never copied:
#   awk -f plan-task-predicate.awk -f <this> -f <caller.awk> <spec>
#
# DEPENDS ON plan-task-predicate.awk, which must be loaded FIRST — heading_level() and
# is_checklist_item() come from there and are deliberately not redefined here (awk rejects a
# duplicate function definition). Two shared files rather than one because they answer questions
# about different documents: that one is about a PLAN's tasks, this one about a SPEC's requirements.
#
# Two consumers, and they must never disagree about what a declaration looks like:
#   spec-coverage.sh       reads (a CHECKER, never writes)
#   spec-normalize-ids.sh  repairs (the only writer)
# A repair keyed on a different rule than the check would either miss what the check rejects or
# rewrite what it accepts. That is the whole reason this file exists rather than a second copy.
#
# Bash 3.2 / POSIX awk clean: no gensub, no length(array), no --re-interval dependency.

# The three headings ADR-0048 recognises as opening a requirements section. Case-insensitive,
# prefix match, H2 or deeper.
function is_spec_section_heading(l,   lvl, rest, ll) {
  lvl = heading_level(l)
  if (lvl < 2) return 0
  rest = l
  sub(/^#+[ \t]+/, "", rest)
  ll = tolower(rest)
  return (ll ~ /^success criteria/) || (ll ~ /^acceptance criteria/) || (ll ~ /^definition of done/)
}

# A NEAR-MISS: a plain bullet, inside a recognised section, whose text begins with a well-formed
# R-NN token. It declares a requirement in a form the checker cannot read.
#
# This is the exact shape that produced issue #171 — a SPEC with 17 of these passed the coverage
# gate silently, because the parser only ever examined checklist items, so the tokens landed in
# neither the declared set nor the malformed set nor the out-of-section set. Nothing to report is
# indistinguishable from nothing found (rule 5/8 of .claude/context.md), and this is the line where
# that stopped being true.
#
# The caller supplies the in-section state: this predicate deliberately does not track it, so the
# section-scanning loop stays in one place per consumer.
#
# THE INVARIANT THIS PREDICATE IS BOUND BY (ADR-0072 §D4): every line it matches must become a line
# spec-coverage.sh READS once the marker is added. A detection the repair cannot make readable is
# worse than no detection — it reports a problem, rewrites the file, and the gate still fails.
#
# A bold-wrapped id (`- **R-01** — …`) IS matched here (ADR-0122, issue #291). It used to be
# excluded, and the exclusion was never about bold being unrepairable — it was about the checker
# being unable to read the REPAIRED line: item_text() strips the checklist marker and then requires
# `R-` immediately, so `- [ ] **R-01**` was invisible to it too. strip_emphasis() below is called by
# BOTH is_near_miss_bullet() here and by spec-coverage.sh's own extraction sites, so the invariant
# now holds by construction rather than by staying out of the way: the repaired line is readable
# because both sides strip the same leading emphasis run before testing for `R-NN`.
function strip_emphasis(s) {
  sub(/^[*_]+/, "", s)
  return s
}
function is_near_miss_bullet(l,   t) {
  if (is_checklist_item(l)) return 0
  if (l !~ /^[ \t]*[-*][ \t]/) return 0
  t = l
  sub(/^[ \t]*[-*][ \t]+/, "", t)
  t = strip_emphasis(t)
  return t ~ /^R-[0-9][0-9]([^0-9]|$)/
}

# The repair: the same line, as a checklist item. Content is untouched — only the marker is added,
# which is why this is normalisation and not regeneration (ADR-0072 §D1).
function to_checklist_item(l,   indent, rest) {
  indent = ""
  if (match(l, /^[ \t]*/)) indent = substr(l, 1, RLENGTH)
  rest = l
  sub(/^[ \t]*[-*][ \t]+/, "", rest)
  return indent "- [ ] " rest
}
