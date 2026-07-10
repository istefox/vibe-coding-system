#!/usr/bin/env bash
# Round-trip harness for the ADR-0012 agent-notes contract: inject / harvest / persistence.
# Isolated: drives agent-notes-harvest.sh against a fixture store via AGENT_NOTES_ROOT;
# never touches the real store. 3.2-clean: no assoc array, no mapfile, no ${v^^}, no <().
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

H="$HOME/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh"
[ -x "$H" ] || { echo "FAIL: helper not executable: $H"; echo "PASS=0 FAIL=1"; exit 1; }

FIX="$TMP/memory"
export AGENT_NOTES_ROOT="$FIX/agent-notes"
mkdir -p "$AGENT_NOTES_ROOT"
# fixture MEMORY.md (sibling of the store) to prove the helper never writes it
printf '# Memory Index\n- [x](y.md) z\n' >"$FIX/MEMORY.md"
cp "$FIX/MEMORY.md" "$TMP/mem.ref"

# 1. inject — absent store
out=$("$H" inject architect)
echo "$out" | grep -q 'PRIOR AGENT NOTES: none yet' \
  && ok "1 inject: absent store -> none yet" || bad "1 inject absent (got: $out)"

# 2. inject — present store
printf '## seed\n- [arch] seeded note\n' >"$AGENT_NOTES_ROOT/architect.md"
out=$("$H" inject architect)
if echo "$out" | grep -q 'PRIOR AGENT NOTES (read-only' && echo "$out" | grep -q 'seeded note'; then
  ok "2 inject: present store -> block + content"
else
  bad "2 inject present (got: $out)"
fi

# 3. harvest — well-formed (2 bullets) -> appended
printf 'body\n\nDURABLE NOTES:\n- [arch] note A (ctx)\n- [risk] note B\n' | "$H" harvest reviewer >/dev/null
if grep -q 'note A' "$AGENT_NOTES_ROOT/reviewer.md" 2>/dev/null && grep -q 'note B' "$AGENT_NOTES_ROOT/reviewer.md" 2>/dev/null; then
  ok "3 harvest: well-formed -> 2 notes appended"
else
  bad "3 harvest well-formed"
fi

# 4. harvest — DURABLE NOTES: none -> nothing written
printf 'body\nDURABLE NOTES: none\n' | "$H" harvest debugger >/dev/null
[ ! -e "$AGENT_NOTES_ROOT/debugger.md" ] && ok "4 harvest: none -> no file written" || bad "4 harvest none (file created)"

# 5. harvest — truncated mid-bullet -> partial dropped, complete kept
printf 'body\nDURABLE NOTES:\n- [perf] complete one\n- [ar' | "$H" harvest tester >/dev/null
if grep -q 'complete one' "$AGENT_NOTES_ROOT/tester.md" 2>/dev/null && ! grep -q '\[ar' "$AGENT_NOTES_ROOT/tester.md" 2>/dev/null; then
  ok "5 harvest: truncated bullet dropped, complete kept"
else
  bad "5 harvest truncated (out: $(cat "$AGENT_NOTES_ROOT/tester.md" 2>/dev/null))"
fi

# 5b. harvest — header + only a truncated bullet -> nothing written
printf 'body\nDURABLE NOTES:\n- [ar' | "$H" harvest tester2 >/dev/null
[ ! -e "$AGENT_NOTES_ROOT/tester2.md" ] && ok "5b harvest: only-truncated-bullet -> nothing" || bad "5b harvest truncated-only (file created)"

# 6. persistence — MEMORY.md byte-identical (never written by the helper)
cmp -s "$FIX/MEMORY.md" "$TMP/mem.ref" \
  && ok "6 persistence: MEMORY.md byte-identical (never written)" || bad "6 persistence: MEMORY.md changed"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
