#!/bin/bash
# agent-tool-parameter-names.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash agent-tool-parameter-names.test.sh
#
# Covers issue #180: the Agent tool and the Workflow API are two different mechanisms with two
# different parameter sets, and staging/plugin/skills/*/SKILL.md mixes their notations at several
# sites — using Workflow's `agentType`/`effort` keys on what is, by its own surrounding prose or
# call syntax, an Agent-tool dispatch. The Agent tool's real parameters are `subagent_type`,
# `model`, `isolation`, `prompt`, `description`, `run_in_background`. There is no `effort` and no
# `agentType` on that tool at all (ADR-0068 Measured facts). The Workflow API's `agent(prompt,
# opts)` legitimately carries `agentType` and `effort` in `opts` — those sites must NOT be flagged.
#
# concept-to-code/SKILL.md is internally inconsistent about this: line 1587 and line 481 both
# write the correct kwargs form `Agent(subagent_type="...", ...)`, while lines 614, 2966 and 2969
# write the wrong object-literal form `Agent({ agentType: "...", ... })`. That inconsistency
# inside one file is the evidence that `agentType` in Agent-tool context is a defect, not house
# shorthand for the Agent tool's own `subagent_type`.
#
# ---------------------------------------------------------------------------------------------
# Two independent detection layers, because prose about "the Agent tool" comes in two shapes in
# this codebase and neither shape alone covers every known-bad site:
#
#   Zone 1 — literal object-literal calls: a paragraph containing the literal substring
#   `Agent({` (capital A, open paren, open brace — never matches Workflow's lowercase
#   `agent(\`...\`, { ... })` form). This is a TRUE ALLOWLIST: every identifier used as a key in
#   the object header (the text between `Agent({` and the first `prompt:` field) is extracted and
#   compared against {subagent_type, model, isolation, prompt, description, run_in_background}.
#   Any key outside that set is flagged — not just the two named-bad keys — so the next invented
#   key (the ADR-0043 direction lesson, applied here) is caught too, not only `agentType`/`effort`.
#
#   Zone 2 — prose instructions that never spell the call out as a literal `Agent({...})` block
#   (e.g. a numbered dispatch step inside a section titled "Fallback — Agent-tool batch
#   dispatch", or a sentence naming "this `Agent` call"). There is no extractable "parameter set"
#   for free-form prose the way there is for an object literal, so THIS LAYER IS A DENYLIST of
#   the two known-bad keys (`agentType`, `effort`), scoped to text units judged to be about the
#   Agent tool by two independent markers:
#     (a) a heading (any `#`-line) whose text, with backticks stripped, contains "Agent tool" or
#         "Agent-tool" — the block from that heading to the next heading is in-scope; or
#     (b) a paragraph (blank-line-delimited) whose text, with backticks stripped, contains
#         "Agent tool", "Agent-tool", "Agent call", or the literal Agent-tool-only parameter name
#         `subagent_type` — a paragraph that already names a real Agent-tool parameter is
#         unambiguously about the Agent tool, regardless of whether it also says the word "Agent".
#   A full allowlist over discovered prose keys was attempted and rejected: free text has no
#   delimited "key set" to enumerate the way an object literal does, and any regex trying to
#   extract "the parameters this paragraph pins" from prose over-fires on ordinary sentences
#   (e.g. "Budget: <n> lines" inside a dispatch brief reads as a key-value pair to a generic
#   extractor). The denylist is named explicitly as the fallback the SPEC anticipated, not shipped
#   quietly as if it were the intended design.
#
# Every non-vacuity / positive-twin assertion is MANDATORY per the ADR-0043 direction lesson and
# the ADR-0039 cfile=/dev/null correction: a detector that reports nothing must be distinguishable
# from a corpus that contains nothing, and a detector must be shown to both fire on a violation
# and stay silent on the correct form it must never flag.
#
# ---------------------------------------------------------------------------------------------
# Issue #180 part 2 — the rest of the tool-parameter sweep, beyond the Agent tool covered above.
#
#   Zone C (Skill tool) — an ALLOWLIST, same reasoning as zone 1. The Skill tool's real schema is
#   named parameters only (`skill` required, `args` optional) — there is no positional form. Three
#   sites in this repository call it positionally anyway (`Skill(concept-to-code, "resume
#   <manifest-path>")` and siblings); five-plus other sites in the SAME repository use the correct
#   named form, which is the internal-inconsistency evidence this file already uses for zone 1.
#
#   Zone D (EnterPlanMode) and Zone E (mcp__github__create_pull_request) are FORWARD GUARDS, not
#   fix evidence: every real occurrence in the corpus today is already correct (EnterPlanMode is
#   never called with a parameter; the one create_pull_request instruction block names only
#   schema-valid fields). Their assertions are currently green and are labelled as such — see the
#   ADR-0031 "two always-PASS assertions labeled in the plan" precedent, reapplied here so a green
#   run is never mistaken for evidence that something was fixed.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ==============================================================================================
# The scanner. Written to a temp file rather than a permanent scripts/ file — this repo's
# convention (worktree-isolation-contract.test.sh, hook-hardening.test.sh, etc.) is inline
# `python3 -c` / heredoc-to-temp-file for one-off structural parses, never a checked-in .py helper.
# ==============================================================================================
SCANNER="$TMP/agent_zone_scan.py"
cat > "$SCANNER" <<'PYEOF'
import re
import sys

ALLOWLIST_ZONE1 = {
    "subagent_type", "model", "isolation", "prompt", "description", "run_in_background",
}

KEY_RE = re.compile(r'(?:^|[{(,\s])([A-Za-z_][A-Za-z0-9_]*)\s*:')
BAD_RE = re.compile(r'(?:^|[^A-Za-z])(agentType|effort)\s*:')
# Heading marker is intentionally broad: a heading naming "Agent tool"/"Agent-tool" is a section
# title, never an incidental cross-reference, so the whole block it introduces is safely in-scope.
HEADING_MARKER_RE = re.compile(r'Agent[ -]tool')
# Paragraph marker is intentionally narrower than the heading one. A bare "Agent tool"/"Agent-tool"
# substring inside an ordinary paragraph can be an incidental cross-reference to a DIFFERENT
# section's name (e.g. "Proceed to Fallback (Agent-tool batch dispatch)" while discussing an
# unrelated, correctly-formed Workflow dispatch a few lines above) rather than a claim that THIS
# paragraph's own dispatch goes through the Agent tool. Only phrasings that assert the call itself
# uses the Agent tool are trusted at paragraph scope.
MARKER_RE = re.compile(r'using the Agent tool|Agent[ -]tool calls|Agent call|subagent_type')
HEADING_RE = re.compile(r'^#{1,6}\s')


def split_paragraphs(lines):
    paras = []
    cur = []
    cur_start = None
    for i, line in enumerate(lines, start=1):
        if line.strip() == "":
            if cur:
                paras.append((cur_start, cur))
                cur = []
                cur_start = None
        else:
            if cur_start is None:
                cur_start = i
            cur.append(line)
    if cur:
        paras.append((cur_start, cur))
    return paras


def zone1_scan(files):
    violations = []
    call_count = 0
    for f in files:
        try:
            with open(f) as fh:
                lines = fh.readlines()
        except Exception:
            continue
        for start, para in split_paragraphs(lines):
            joined = "".join(para)
            if "Agent({" not in joined:
                continue
            call_count += 1
            idx = joined.index("Agent({")
            sub = joined[idx:]
            p_idx = sub.find("prompt:")
            header = sub[:p_idx] if p_idx != -1 else sub
            header_body = header[len("Agent({"):]
            keys = set(m.group(1) for m in KEY_RE.finditer(header_body))
            bad_keys = keys - ALLOWLIST_ZONE1
            if bad_keys:
                line_no = start
                for j, l in enumerate(para):
                    if "Agent({" in l:
                        line_no = start + j
                        break
                for k in sorted(bad_keys):
                    violations.append((f, line_no, k))
    return violations, call_count


def zone2_scan(files):
    violations = set()
    zone_units = 0
    for f in files:
        try:
            with open(f) as fh:
                lines = fh.readlines()
        except Exception:
            continue
        n = len(lines)
        # (a) heading-scoped: heading text (backticks stripped) names the Agent tool.
        i = 0
        while i < n:
            heading_stripped = lines[i].replace('`', '')
            if HEADING_RE.match(lines[i]) and HEADING_MARKER_RE.search(heading_stripped):
                zone_units += 1
                j = i + 1
                while j < n and not HEADING_RE.match(lines[j]):
                    line_stripped = lines[j].replace('`', '')
                    for m in BAD_RE.finditer(line_stripped):
                        violations.add((f, j + 1, m.group(1)))
                    j += 1
                i = j
            else:
                i += 1
        # (b) paragraph-scoped: paragraph text (backticks stripped) names the Agent tool,
        # an Agent-tool call, or the Agent-tool-only parameter `subagent_type`.
        for start, para in split_paragraphs(lines):
            joined_stripped = "".join(para).replace('`', '')
            if MARKER_RE.search(joined_stripped):
                zone_units += 1
                for k, l in enumerate(para):
                    line_stripped = l.replace('`', '')
                    for m in BAD_RE.finditer(line_stripped):
                        violations.add((f, start + k, m.group(1)))
    return sorted(violations), zone_units


# ==================================================================================================
# Skill-tool zone (issue #180 sweep, part 2). Real schema: named parameters only, `skill` (required)
# and `args` (optional) — there is NO positional form. Scoped on the literal `Skill(` (capital S,
# open paren) exactly as zone 1 scopes on literal `Agent({` — the same discrimination that keeps
# prose mentions of "the `commit` skill" or "**skill**" out of scope, since neither contains the
# substring `Skill(`.
#
# TRUE ALLOWLIST, for the same reason as zone 1: every top-level argument inside the balanced
# parens is classified as either POSITIONAL (no `name=` prefix at all — the defect this zone
# exists to catch) or NAMED with a key compared against {skill, args}. Any other key is flagged
# too, not just an invented one seen today — the ADR-0043 direction lesson, applied a second time
# in this same file.
# ==================================================================================================
ALLOWLIST_SKILL = {"skill", "args"}
NAMED_ARG_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=')


def _find_call_end(text, start_idx):
    """Return the index of the ')' that closes the '(' consumed just before start_idx,
    tracking nesting depth and skipping over quoted content (quote-aware, matches zone 1's
    quote-agnostic-but-safe approach: none of the corpus's argument values contain unescaped
    parens or commas inside quotes, this only adds robustness for a future one that might)."""
    depth = 1
    i = start_idx
    in_squote = False
    in_dquote = False
    n = len(text)
    while i < n:
        c = text[i]
        if in_dquote:
            if c == '"' and text[i - 1] != '\\':
                in_dquote = False
        elif in_squote:
            if c == "'" and text[i - 1] != '\\':
                in_squote = False
        else:
            if c == '"':
                in_dquote = True
            elif c == "'":
                in_squote = True
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def _split_top_level(s):
    """Split on commas at paren/quote depth 0."""
    parts = []
    cur = []
    depth = 0
    in_squote = False
    in_dquote = False
    n = len(s)
    i = 0
    while i < n:
        c = s[i]
        if in_dquote:
            cur.append(c)
            if c == '"' and s[i - 1] != '\\':
                in_dquote = False
        elif in_squote:
            cur.append(c)
            if c == "'" and s[i - 1] != '\\':
                in_squote = False
        else:
            if c == '"':
                in_dquote = True
                cur.append(c)
            elif c == "'":
                in_squote = True
                cur.append(c)
            elif c == '(':
                depth += 1
                cur.append(c)
            elif c == ')':
                depth -= 1
                cur.append(c)
            elif c == ',' and depth == 0:
                parts.append(''.join(cur))
                cur = []
            else:
                cur.append(c)
        i += 1
    if cur:
        parts.append(''.join(cur))
    return parts


def skill_scan(files):
    violations = []
    call_count = 0
    for f in files:
        try:
            with open(f) as fh:
                lines = fh.readlines()
        except Exception:
            continue
        for start, para in split_paragraphs(lines):
            joined = "".join(para).replace('`', '')
            search_from = 0
            while True:
                idx = joined.find("Skill(", search_from)
                if idx == -1:
                    break
                call_count += 1
                inner_start = idx + len("Skill(")
                end_idx = _find_call_end(joined, inner_start)
                if end_idx == -1:
                    search_from = inner_start
                    continue
                inner = joined[inner_start:end_idx]
                line_no = start + joined[:idx].count("\n")
                for arg in _split_top_level(inner):
                    arg_stripped = arg.strip()
                    if arg_stripped == "":
                        continue
                    m = NAMED_ARG_RE.match(arg_stripped)
                    if not m:
                        violations.append((f, line_no, "positional"))
                    else:
                        key = m.group(1)
                        if key not in ALLOWLIST_SKILL:
                            violations.append((f, line_no, key))
                search_from = end_idx + 1
    return violations, call_count


# ==================================================================================================
# EnterPlanMode zone. Real schema: takes no parameters at all. Every occurrence in the corpus today
# is a prose reference ("Call `EnterPlanMode`") with no call syntax whatsoever, so CALLCOUNT is
# legitimately 0 — this is a forward guard against a future call site that prescribes one, not
# evidence of a fix (there is nothing to fix today).
# ==================================================================================================
ENTERPLANMODE_CALL_RE = re.compile(r'EnterPlanMode\(([^()]*)\)')


def enterplanmode_scan(files):
    violations = []
    call_count = 0
    for f in files:
        try:
            with open(f) as fh:
                lines = fh.readlines()
        except Exception:
            continue
        for ln, line in enumerate(lines, start=1):
            stripped = line.replace('`', '')
            for m in ENTERPLANMODE_CALL_RE.finditer(stripped):
                call_count += 1
                if m.group(1).strip() != "":
                    violations.append((f, ln, m.group(1).strip()))
    return violations, call_count


# ==================================================================================================
# mcp__github__create_pull_request zone. Real schema fields: owner, repo, title, head, base, body,
# draft, reviewers, maintainer_can_modify. A block is identified by a line naming the tool AND
# ending in ':' (a field list follows) — this discriminates the real instruction block ("proceed
# with `mcp__github__create_pull_request`:") from a bare cross-reference ("Do NOT attempt
# `mcp__github__create_pull_request`...") that never ends in a colon and introduces no field list.
# Fields are the backtick-quoted-word-immediately-followed-by-colon tokens in the block that
# follows, matching this repo's own SKILL.md bullet convention (`` `title`: subject of... ``).
# Forward guard, like EnterPlanMode: the one real block is currently valid, so this is currently
# green and proves nothing was ever broken — the fixture pair proves the detector would catch it.
# ==================================================================================================
ALLOWLIST_PR_FIELDS = {
    "owner", "repo", "title", "head", "base", "body", "draft", "reviewers",
    "maintainer_can_modify",
}
PR_BLOCK_HEADER_RE = re.compile(r'mcp__github__create_pull_request.*:\s*$')
PR_FIELD_RE = re.compile(r'`([A-Za-z_][A-Za-z0-9_]*)`\s*:')
PR_BULLET_RE = re.compile(r'^\s*-\s')


def mcp_pr_scan(files):
    violations = []
    block_count = 0
    for f in files:
        try:
            with open(f) as fh:
                lines = fh.readlines()
        except Exception:
            continue
        n = len(lines)
        i = 0
        while i < n:
            if PR_BLOCK_HEADER_RE.search(lines[i].rstrip('\n')):
                block_count += 1
                j = i + 1
                while j < n and PR_BULLET_RE.match(lines[j]):
                    for m in PR_FIELD_RE.finditer(lines[j]):
                        field = m.group(1)
                        if field not in ALLOWLIST_PR_FIELDS:
                            violations.append((f, j + 1, field))
                    j += 1
                i = j
            else:
                i += 1
    return violations, block_count


def main():
    mode = sys.argv[1]
    files = sys.argv[2:]
    if mode == "zone1":
        violations, count = zone1_scan(files)
        for f, ln, k in violations:
            print("VIOLATION\t%s\t%d\t%s" % (f, ln, k))
        print("CALLCOUNT\t%d" % count)
    elif mode == "zone2":
        violations, count = zone2_scan(files)
        for f, ln, k in violations:
            print("VIOLATION\t%s\t%d\t%s" % (f, ln, k))
        print("ZONECOUNT\t%d" % count)
    elif mode == "skill":
        violations, count = skill_scan(files)
        for f, ln, k in violations:
            print("VIOLATION\t%s\t%d\t%s" % (f, ln, k))
        print("CALLCOUNT\t%d" % count)
    elif mode == "enterplanmode":
        violations, count = enterplanmode_scan(files)
        for f, ln, k in violations:
            print("VIOLATION\t%s\t%d\t%s" % (f, ln, k))
        print("CALLCOUNT\t%d" % count)
    elif mode == "mcp_pr":
        violations, count = mcp_pr_scan(files)
        for f, ln, k in violations:
            print("VIOLATION\t%s\t%d\t%s" % (f, ln, k))
        print("BLOCKCOUNT\t%d" % count)
    else:
        sys.stderr.write(
            "usage: agent_zone_scan.py zone1|zone2|skill|enterplanmode|mcp_pr <files...>\n"
        )
        sys.exit(2)


main()
PYEOF

# ==============================================================================================
# The real corpus.
# ==============================================================================================
CORPUS_LIST="$TMP/corpus-files.txt"
: > "$CORPUS_LIST"
for f in "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/agents/*.md; do
  [ -f "$f" ] && printf '%s\n' "$f" >> "$CORPUS_LIST"
done

# Bash 3.2-safe: build a positional-args array from the file list (no mapfile, no process sub).
CORPUS=()
while IFS= read -r line; do
  CORPUS[${#CORPUS[@]}]="$line"
done < "$CORPUS_LIST"

python3 "$SCANNER" zone1 "${CORPUS[@]}" > "$TMP/zone1.out" 2>"$TMP/zone1.err"
python3 "$SCANNER" zone2 "${CORPUS[@]}" > "$TMP/zone2.out" 2>"$TMP/zone2.err"
python3 "$SCANNER" skill "${CORPUS[@]}" > "$TMP/skill.out" 2>"$TMP/skill.err"
python3 "$SCANNER" enterplanmode "${CORPUS[@]}" > "$TMP/epm.out" 2>"$TMP/epm.err"
python3 "$SCANNER" mcp_pr "${CORPUS[@]}" > "$TMP/mcp.out" 2>"$TMP/mcp.err"

Z1_CALLCOUNT=$(grep '^CALLCOUNT' "$TMP/zone1.out" | cut -f2)
Z1_VIOLATIONS=$(grep '^VIOLATION' "$TMP/zone1.out")
Z2_ZONECOUNT=$(grep '^ZONECOUNT' "$TMP/zone2.out" | cut -f2)
Z2_VIOLATIONS=$(grep '^VIOLATION' "$TMP/zone2.out")
SKILL_CALLCOUNT=$(grep '^CALLCOUNT' "$TMP/skill.out" | cut -f2)
SKILL_VIOLATIONS=$(grep '^VIOLATION' "$TMP/skill.out")
EPM_CALLCOUNT=$(grep '^CALLCOUNT' "$TMP/epm.out" | cut -f2)
EPM_VIOLATIONS=$(grep '^VIOLATION' "$TMP/epm.out")
MCP_BLOCKCOUNT=$(grep '^BLOCKCOUNT' "$TMP/mcp.out" | cut -f2)
MCP_VIOLATIONS=$(grep '^VIOLATION' "$TMP/mcp.out")

case "$Z1_CALLCOUNT" in ''|*[!0-9]*) Z1_CALLCOUNT=0 ;; esac
case "$Z2_ZONECOUNT" in ''|*[!0-9]*) Z2_ZONECOUNT=0 ;; esac
case "$SKILL_CALLCOUNT" in ''|*[!0-9]*) SKILL_CALLCOUNT=0 ;; esac
case "$EPM_CALLCOUNT" in ''|*[!0-9]*) EPM_CALLCOUNT=0 ;; esac
case "$MCP_BLOCKCOUNT" in ''|*[!0-9]*) MCP_BLOCKCOUNT=0 ;; esac

# ==============================================================================================
# Section A — Zone 1 (literal `Agent({...})` object-literal calls). ALLOWLIST.
# ==============================================================================================
if [ "$Z1_CALLCOUNT" -ge 1 ]; then
  ok "A0: at least one literal Agent-tool object-literal call ('Agent({') was discovered across staging/ (count=$Z1_CALLCOUNT) — the extractor is not vacuous"
else
  bad "A0: zero 'Agent({' call sites discovered — the extractor is broken and every zone-1 assertion below is meaningless"
fi

if [ -z "$Z1_VIOLATIONS" ]; then
  ok "A1: every literal Agent-tool object-literal call uses only allowed keys (subagent_type|model|isolation|prompt|description|run_in_background)"
else
  bad "A1: literal Agent-tool call(s) use a key the Agent tool does not accept: $(printf '%s' "$Z1_VIOLATIONS" | awk -F'\t' '{printf "%s:%s(%s) ", $2, $3, $4}')"
fi

# A2 (forward guard, mandatory positive twin): a fixture Agent({...}) call carrying agentType
# must be flagged.
FIXTURE_A2="$TMP/fixture-a2.md"
cat > "$FIXTURE_A2" <<'EOF'
Dispatch:
```
Agent({ agentType: "coder", model: "sonnet",
        prompt: "do the thing" })
```
EOF
A2_OUT=$(python3 "$SCANNER" zone1 "$FIXTURE_A2")
if printf '%s\n' "$A2_OUT" | grep -q 'VIOLATION.*agentType'; then
  ok "A2 (forward guard): a fixture Agent({ agentType: ..., ... }) call is flagged for the disallowed key 'agentType'"
else
  bad "A2 (forward guard): the fixture Agent({ agentType: ..., ... }) call was NOT flagged — the zone-1 detector cannot be trusted"
fi

# A3 (forward guard, mandatory positive twin, TRUE ALLOWLIST proof): a fixture carrying a
# never-seen-before key ('reasoningEffort') must ALSO be flagged — proving this is an allowlist
# over the discovered parameter set, not a denylist of the two named-bad keys.
FIXTURE_A3="$TMP/fixture-a3.md"
cat > "$FIXTURE_A3" <<'EOF'
Dispatch:
```
Agent({ model: "sonnet", reasoningEffort: "high",
        prompt: "do the thing" })
```
EOF
A3_OUT=$(python3 "$SCANNER" zone1 "$FIXTURE_A3")
if printf '%s\n' "$A3_OUT" | grep -q 'VIOLATION.*reasoningEffort'; then
  ok "A3 (forward guard, allowlist proof): a fixture Agent({...}) call carrying an INVENTED key ('reasoningEffort', never named in this file) is flagged — this is an allowlist over the discovered parameter set, not a denylist of just agentType/effort"
else
  bad "A3 (forward guard): the fixture's invented key 'reasoningEffort' was NOT flagged — section A is a denylist of two known names, not a true allowlist, and cannot see the next invented key"
fi

# A4 (forward guard, mandatory positive twin — silence proof): a fixture Agent({...}) call using
# ONLY allowed keys must produce zero violations.
FIXTURE_A4="$TMP/fixture-a4.md"
cat > "$FIXTURE_A4" <<'EOF'
Dispatch:
```
Agent({ subagent_type: "coder", model: "sonnet", isolation: "worktree",
        prompt: "do the thing" })
```
EOF
A4_OUT=$(python3 "$SCANNER" zone1 "$FIXTURE_A4")
if printf '%s\n' "$A4_OUT" | grep -q '^VIOLATION'; then
  bad "A4 (forward guard, silence proof): a fixture Agent({...}) call using ONLY allowed keys was wrongly flagged"
else
  ok "A4 (forward guard, silence proof): a fixture Agent({...}) call using ONLY allowed keys (subagent_type/model/isolation/prompt) is correctly silent"
fi

# A5 (forward guard, mandatory positive twin — discrimination proof): a correctly-formed Workflow
# agent(prompt, { agentType, effort }) call must NOT be counted or flagged by zone 1 at all —
# proving the detector discriminates on call syntax (capital-A, literal brace), not on key names.
FIXTURE_A5="$TMP/fixture-a5.md"
cat > "$FIXTURE_A5" <<'EOF'
Phase 1 — Review:
```
agent(`
  do the thing
`, { agentType: "reviewer", model: "sonnet", effort: "high" })
```
EOF
A5_OUT=$(python3 "$SCANNER" zone1 "$FIXTURE_A5")
A5_COUNT=$(printf '%s\n' "$A5_OUT" | grep '^CALLCOUNT' | cut -f2)
case "$A5_COUNT" in ''|*[!0-9]*) A5_COUNT=0 ;; esac
if [ "$A5_COUNT" -eq 0 ] && ! printf '%s\n' "$A5_OUT" | grep -q '^VIOLATION'; then
  ok "A5 (forward guard, discrimination proof): a correctly-formed lowercase Workflow agent(prompt, { agentType, effort }) call is neither counted nor flagged by the zone-1 (capital-A 'Agent({') detector"
else
  bad "A5 (forward guard, discrimination proof): the zone-1 detector wrongly counted or flagged a lowercase Workflow agent(...) call — it does not discriminate call syntax"
fi

# ==============================================================================================
# Section B — Zone 2 (prose: heading-scoped "Agent-tool" sections and marker-scoped paragraphs).
# DENYLIST of the two known-bad keys, documented above as the deliberate fallback for free text —
# a full allowlist over discovered prose keys was attempted and rejected (see file header).
# ==============================================================================================
if [ "$Z2_ZONECOUNT" -ge 1 ]; then
  ok "B0: at least one Agent-tool prose zone (heading- or marker-scoped) was discovered across staging/ (count=$Z2_ZONECOUNT) — the extractor is not vacuous"
else
  bad "B0: zero Agent-tool prose zones discovered — the extractor is broken and every zone-2 assertion below is meaningless"
fi

Z2_AGENTTYPE=$(printf '%s\n' "$Z2_VIOLATIONS" | awk -F'\t' '$4=="agentType"')
Z2_EFFORT=$(printf '%s\n' "$Z2_VIOLATIONS" | awk -F'\t' '$4=="effort"')

if [ -z "$Z2_AGENTTYPE" ]; then
  ok "B1: no Agent-tool prose instruction prescribes 'agentType' — the Agent tool has no such parameter"
else
  bad "B1: an Agent-tool prose instruction prescribes 'agentType' (the Agent tool has none): $(printf '%s' "$Z2_AGENTTYPE" | awk -F'\t' '{printf "%s:%s ", $2, $3}')"
fi

if [ -z "$Z2_EFFORT" ]; then
  ok "B2: no Agent-tool prose instruction prescribes 'effort' — the Agent tool has no such parameter (ADR-0068 §D7: effort is Workflow-only)"
else
  bad "B2: an Agent-tool prose instruction prescribes 'effort' (the Agent tool has none, ADR-0068 §D7): $(printf '%s' "$Z2_EFFORT" | awk -F'\t' '{printf "%s:%s ", $2, $3}')"
fi

# B3 (forward guard, mandatory positive twin): a fixture heading naming "Agent-tool" whose body
# pins `effort` must be flagged.
FIXTURE_B3="$TMP/fixture-b3.md"
cat > "$FIXTURE_B3" <<'EOF'
#### Fallback — Agent-tool batch dispatch (fixture)

1. Dispatch `tester` for batch 1. Pin `model: "sonnet"`, `effort: "medium"` explicitly.

#### Next section
Unrelated text.
EOF
B3_OUT=$(python3 "$SCANNER" zone2 "$FIXTURE_B3")
if printf '%s\n' "$B3_OUT" | grep -q 'VIOLATION.*effort'; then
  ok "B3 (forward guard): a fixture 'Agent-tool' heading section pinning 'effort' in its body is flagged"
else
  bad "B3 (forward guard): the fixture heading-scoped 'effort' pin was NOT flagged — the zone-2 heading detector cannot be trusted"
fi

# B4 (forward guard, mandatory positive twin): a fixture paragraph naming "this `Agent` call" that
# pins `agentType` must be flagged, without any heading marker present.
FIXTURE_B4="$TMP/fixture-b4.md"
cat > "$FIXTURE_B4" <<'EOF'
Pin `agentType: "tester"`, `model: "sonnet"` explicitly on this `Agent` call, per the fixture.
EOF
B4_OUT=$(python3 "$SCANNER" zone2 "$FIXTURE_B4")
if printf '%s\n' "$B4_OUT" | grep -q 'VIOLATION.*agentType'; then
  ok "B4 (forward guard): a fixture paragraph naming 'this \`Agent\` call' and pinning 'agentType' is flagged"
else
  bad "B4 (forward guard): the fixture paragraph-scoped 'agentType' pin was NOT flagged — the zone-2 marker-paragraph detector cannot be trusted"
fi

# B5 (forward guard, mandatory positive twin — silence proof): a fixture Workflow-style paragraph
# carrying agentType/effort but NO Agent-tool marker (no "Agent tool"/"Agent call"/subagent_type
# text nearby) must NOT be flagged.
FIXTURE_B5="$TMP/fixture-b5.md"
cat > "$FIXTURE_B5" <<'EOF'
Pin both `agentType: "reviewer"` and `effort: "high"` explicitly on every agent() call in the
script — a workflow subagent with agentType but no model inherits the session model.
EOF
B5_OUT=$(python3 "$SCANNER" zone2 "$FIXTURE_B5")
if printf '%s\n' "$B5_OUT" | grep -q '^VIOLATION'; then
  bad "B5 (forward guard, silence proof): a fixture Workflow-context paragraph (no Agent-tool marker) was wrongly flagged"
else
  ok "B5 (forward guard, silence proof): a fixture Workflow-context paragraph (agent() call, no Agent-tool marker) pinning agentType/effort is correctly silent"
fi

# B6 (forward guard, silence proof, real-text regression anchor): the actual explanatory sentence
# at concept-to-code/SKILL.md:609 ("The Agent tool takes no effort-level parameter of any kind")
# names the Agent tool AND the word "effort", but never as a key:value pin (no colon touches
# "effort"). It must stay silent — a detector that fires on this sentence is matching the bare
# word "effort", not a prescription.
FIXTURE_B6="$TMP/fixture-b6.md"
cat > "$FIXTURE_B6" <<'EOF'
The Agent tool takes no effort-level parameter of any kind — the Workflow-only `opts` field that
name would suggest exists on the `agent()` call, lowercase, only. Do not add one here.
EOF
B6_OUT=$(python3 "$SCANNER" zone2 "$FIXTURE_B6")
if printf '%s\n' "$B6_OUT" | grep -q '^VIOLATION'; then
  bad "B6 (forward guard, silence proof): the real explanatory sentence about the Agent tool's missing effort parameter was wrongly flagged — the detector is matching the bare word 'effort', not a key:value prescription"
else
  ok "B6 (forward guard, silence proof): the real explanatory sentence ('The Agent tool takes no effort-level parameter...') stays silent — the detector requires a key:value prescription, not the bare word"
fi

# ==============================================================================================
# Section C — Skill tool (literal `Skill(...)` calls). TRUE ALLOWLIST over {skill, args}; a bare
# positional argument is flagged as "positional", any other named key is flagged by its own name.
# ==============================================================================================
if [ "$SKILL_CALLCOUNT" -ge 1 ]; then
  ok "C0: at least one literal Skill(...) call site was discovered across staging/ (count=$SKILL_CALLCOUNT) — the extractor is not vacuous"
else
  bad "C0: zero Skill(...) call sites discovered — the extractor is broken and every section-C assertion below is meaningless"
fi

SKILL_POSITIONAL=$(printf '%s\n' "$SKILL_VIOLATIONS" | awk -F'\t' '$4=="positional"')

if [ -z "$SKILL_VIOLATIONS" ]; then
  ok "C1: every Skill(...) call site uses only named parameters (skill=/args=), none positional and no invented key"
else
  bad "C1: Skill(...) call site(s) use a positional argument or a key the tool does not accept: $(printf '%s' "$SKILL_VIOLATIONS" | awk -F'\t' '{printf "%s:%s(%s) ", $2, $3, $4}')"
fi

# C1b: pin the exact known-bad site list (file:line), so the coder has a precise target list
# rather than only a count. A change to this set (fixed sites disappearing, or a new positional
# site appearing) must be visible here, not just in the aggregate PASS/FAIL count.
EXPECTED_POSITIONAL="$TMP/expected-positional.txt"
cat > "$EXPECTED_POSITIONAL" <<EOF
$STAGING/plugin/skills/nightly-autopilot/SKILL.md:69
$STAGING/plugin/skills/nightly-autopilot/SKILL.md:178
$STAGING/plugin/skills/project-conductor/SKILL.md:167
EOF
ACTUAL_POSITIONAL="$TMP/actual-positional.txt"
printf '%s\n' "$SKILL_POSITIONAL" | awk -F'\t' '{print $2":"$3}' | sort -u > "$ACTUAL_POSITIONAL"
sort -u "$EXPECTED_POSITIONAL" -o "$EXPECTED_POSITIONAL"
if diff -q "$EXPECTED_POSITIONAL" "$ACTUAL_POSITIONAL" >/dev/null 2>&1; then
  ok "C1b: the positional-argument violations are exactly the 3 known-bad sites (nightly-autopilot/SKILL.md:69, :178, project-conductor/SKILL.md:167) — no more, no fewer"
else
  bad "C1b: the positional-argument violation set does not match the 3 known-bad sites. expected: $(printf '%s ' $(cat "$EXPECTED_POSITIONAL")) actual: $(printf '%s ' $(cat "$ACTUAL_POSITIONAL"))"
fi

# C2 (forward guard, mandatory positive twin): a fixture positional Skill(foo, "bar") call must
# be flagged as "positional".
FIXTURE_C2="$TMP/fixture-c2.md"
cat > "$FIXTURE_C2" <<'EOF'
Dispatch: `Skill(foo, "bar")`.
EOF
C2_OUT=$(python3 "$SCANNER" skill "$FIXTURE_C2")
if printf '%s\n' "$C2_OUT" | grep -q 'VIOLATION.*positional'; then
  ok "C2 (forward guard): a fixture positional Skill(foo, \"bar\") call is flagged as 'positional'"
else
  bad "C2 (forward guard): the fixture positional Skill(foo, \"bar\") call was NOT flagged — the skill-zone detector cannot be trusted"
fi

# C3 (forward guard, mandatory positive twin — silence proof): a fixture using ONLY the real
# named form must produce zero violations.
FIXTURE_C3="$TMP/fixture-c3.md"
cat > "$FIXTURE_C3" <<'EOF'
Dispatch: `Skill(skill="foo", args="bar")`.
EOF
C3_OUT=$(python3 "$SCANNER" skill "$FIXTURE_C3")
if printf '%s\n' "$C3_OUT" | grep -q '^VIOLATION'; then
  bad "C3 (forward guard, silence proof): a fixture Skill(skill=..., args=...) call using ONLY the real named form was wrongly flagged"
else
  ok "C3 (forward guard, silence proof): a fixture Skill(skill=\"foo\", args=\"bar\") call is correctly silent"
fi

# C4 (forward guard, mandatory positive twin, TRUE ALLOWLIST proof): a fixture carrying a
# never-seen-before named key ('timeout') must ALSO be flagged — proving section C is an allowlist
# over {skill, args}, not merely a positional-only check.
FIXTURE_C4="$TMP/fixture-c4.md"
cat > "$FIXTURE_C4" <<'EOF'
Dispatch: `Skill(skill="foo", timeout=30)`.
EOF
C4_OUT=$(python3 "$SCANNER" skill "$FIXTURE_C4")
if printf '%s\n' "$C4_OUT" | grep -q 'VIOLATION.*timeout'; then
  ok "C4 (forward guard, allowlist proof): a fixture Skill(skill=\"foo\", timeout=30) call carrying an INVENTED named key ('timeout') is flagged — section C is a true allowlist over {skill, args}, not a positional-only check"
else
  bad "C4 (forward guard): the fixture's invented named key 'timeout' was NOT flagged — section C is only checking for positional form, not proving a true allowlist"
fi

# C5 (forward guard, mandatory positive twin — discrimination proof): prose mentioning the word
# "Skill" without the literal call syntax (no open paren, or the many "**skill**"/"the `commit`
# skill" references) must not be counted or flagged.
FIXTURE_C5="$TMP/fixture-c5.md"
cat > "$FIXTURE_C5" <<'EOF'
Invoke the `commit` skill, not the `Agent` tool. The **skill** here handles the push and PR steps.
EOF
C5_OUT=$(python3 "$SCANNER" skill "$FIXTURE_C5")
C5_COUNT=$(printf '%s\n' "$C5_OUT" | grep '^CALLCOUNT' | cut -f2)
case "$C5_COUNT" in ''|*[!0-9]*) C5_COUNT=0 ;; esac
if [ "$C5_COUNT" -eq 0 ] && ! printf '%s\n' "$C5_OUT" | grep -q '^VIOLATION'; then
  ok "C5 (forward guard, discrimination proof): prose naming 'the \`commit\` skill' and '**skill**' (no literal 'Skill(' call) is neither counted nor flagged"
else
  bad "C5 (forward guard, discrimination proof): the skill-zone detector wrongly counted or flagged a prose mention of the word 'skill' with no literal call syntax"
fi

# ==============================================================================================
# Section D — EnterPlanMode (forward guard). Real schema: no parameters at all. Every corpus
# occurrence today is a prose reference with no call syntax, so CALLCOUNT=0 is the correct,
# currently-green state — not evidence anything was fixed.
# ==============================================================================================
if [ -z "$EPM_VIOLATIONS" ]; then
  ok "D1 (forward guard, currently green — nothing to fix today): no EnterPlanMode(...) call site in the real corpus prescribes a parameter (found $EPM_CALLCOUNT literal call site(s) with parens; the rest are bare prose references with no call syntax at all)"
else
  bad "D1: an EnterPlanMode(...) call site prescribes a parameter, which the tool does not accept: $(printf '%s' "$EPM_VIOLATIONS" | awk -F'\t' '{printf "%s:%s(%s) ", $2, $3, $4}')"
fi

# D2 (forward guard, mandatory positive twin): a fixture EnterPlanMode(foo="bar") call must be
# flagged, proving the detector would catch a future violation.
FIXTURE_D2="$TMP/fixture-d2.md"
cat > "$FIXTURE_D2" <<'EOF'
Call `EnterPlanMode(foo="bar")` here (fixture).
EOF
D2_OUT=$(python3 "$SCANNER" enterplanmode "$FIXTURE_D2")
if printf '%s\n' "$D2_OUT" | grep -q '^VIOLATION'; then
  ok "D2 (forward guard): a fixture EnterPlanMode(foo=\"bar\") call is flagged — the tool takes no parameters"
else
  bad "D2 (forward guard): the fixture EnterPlanMode(foo=\"bar\") call was NOT flagged — the EnterPlanMode detector cannot be trusted"
fi

# D3 (forward guard, mandatory positive twin — silence proof): a bare prose reference ("Call
# `EnterPlanMode`.", no parens at all) must stay silent.
FIXTURE_D3="$TMP/fixture-d3.md"
cat > "$FIXTURE_D3" <<'EOF'
Call `EnterPlanMode`. The plan approval UI is the HITL gate (fixture).
EOF
D3_OUT=$(python3 "$SCANNER" enterplanmode "$FIXTURE_D3")
if printf '%s\n' "$D3_OUT" | grep -q '^VIOLATION'; then
  bad "D3 (forward guard, silence proof): a bare prose reference to EnterPlanMode (no call syntax) was wrongly flagged"
else
  ok "D3 (forward guard, silence proof): a bare prose reference ('Call \`EnterPlanMode\`.', no parens) is correctly silent"
fi

# ==============================================================================================
# Section E — mcp__github__create_pull_request (forward guard). Real schema fields: owner, repo,
# title, head, base, body, draft, reviewers, maintainer_can_modify. The one real instruction block
# (commit/SKILL.md) names only title/body/base/head, all valid — currently green, not fix evidence.
# ==============================================================================================
if [ "$MCP_BLOCKCOUNT" -ge 1 ]; then
  ok "E0: at least one mcp__github__create_pull_request instruction block was discovered across staging/ (count=$MCP_BLOCKCOUNT) — the extractor is not vacuous"
else
  bad "E0: zero mcp__github__create_pull_request instruction blocks discovered — the extractor is broken and every section-E assertion below is meaningless"
fi

if [ -z "$MCP_VIOLATIONS" ]; then
  ok "E1 (forward guard, currently green — nothing to fix today): every field named in a real mcp__github__create_pull_request instruction block is one the tool accepts"
else
  bad "E1: an mcp__github__create_pull_request instruction block names a field the tool does not accept: $(printf '%s' "$MCP_VIOLATIONS" | awk -F'\t' '{printf "%s:%s(%s) ", $2, $3, $4}')"
fi

# E2 (forward guard, mandatory positive twin): a fixture block naming an invented field
# ('assignee') must be flagged.
FIXTURE_E2="$TMP/fixture-e2.md"
cat > "$FIXTURE_E2" <<'EOF'
1. proceed with `mcp__github__create_pull_request`:
   - `title`: subject of the commit message
   - `assignee`: the fixture's invented field
EOF
E2_OUT=$(python3 "$SCANNER" mcp_pr "$FIXTURE_E2")
if printf '%s\n' "$E2_OUT" | grep -q 'VIOLATION.*assignee'; then
  ok "E2 (forward guard): a fixture block naming the invented field 'assignee' is flagged"
else
  bad "E2 (forward guard): the fixture block's invented field 'assignee' was NOT flagged — the mcp__github__create_pull_request detector cannot be trusted"
fi

# E3 (forward guard, mandatory positive twin — silence proof): a fixture block naming only
# schema-valid fields must stay silent.
FIXTURE_E3="$TMP/fixture-e3.md"
cat > "$FIXTURE_E3" <<'EOF'
1. proceed with `mcp__github__create_pull_request`:
   - `title`: subject of the commit message
   - `body`: body of the commit message
   - `base`: `$default_branch`, `head`: `$branch_name`
   - `draft`: false
EOF
E3_OUT=$(python3 "$SCANNER" mcp_pr "$FIXTURE_E3")
if printf '%s\n' "$E3_OUT" | grep -q '^VIOLATION'; then
  bad "E3 (forward guard, silence proof): a fixture block naming only schema-valid fields (title/body/base/head/draft) was wrongly flagged"
else
  ok "E3 (forward guard, silence proof): a fixture block naming only schema-valid fields is correctly silent"
fi

# ==============================================================================================
# Report — the full flagged-site list from the real corpus, for the coder to work from.
# ==============================================================================================
echo "---- flagged sites (zone 1 — literal Agent({...}) calls) ----"
if [ -n "$Z1_VIOLATIONS" ]; then
  printf '%s\n' "$Z1_VIOLATIONS" | awk -F'\t' '{print $2":"$3" -> disallowed key: "$4}'
else
  echo "(none)"
fi

echo "---- flagged sites (zone 2 — Agent-tool prose) ----"
if [ -n "$Z2_VIOLATIONS" ]; then
  printf '%s\n' "$Z2_VIOLATIONS" | awk -F'\t' '{print $2":"$3" -> disallowed key: "$4}'
else
  echo "(none)"
fi

echo "---- flagged sites (section C — Skill(...) calls) ----"
if [ -n "$SKILL_VIOLATIONS" ]; then
  printf '%s\n' "$SKILL_VIOLATIONS" | awk -F'\t' '{print $2":"$3" -> "$4}'
else
  echo "(none)"
fi

echo "---- flagged sites (section D — EnterPlanMode) ----"
if [ -n "$EPM_VIOLATIONS" ]; then
  printf '%s\n' "$EPM_VIOLATIONS" | awk -F'\t' '{print $2":"$3" -> "$4}'
else
  echo "(none)"
fi

echo "---- flagged sites (section E — mcp__github__create_pull_request) ----"
if [ -n "$MCP_VIOLATIONS" ]; then
  printf '%s\n' "$MCP_VIOLATIONS" | awk -F'\t' '{print $2":"$3" -> "$4}'
else
  echo "(none)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
