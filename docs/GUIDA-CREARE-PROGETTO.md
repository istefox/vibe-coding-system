# Guide — How to create a project with your Vibe Coding system

Explained simply, step by step. Nothing taken for granted.

---

## 1. What this system is (in 30 seconds)

Imagine having a **team of specialized assistants** inside Claude
Code. Each one is good at exactly one thing:

- who **designs** (architect),
- who **writes code** (coder),
- who **writes tests** (tester),
- who **finds bugs** (debugger),
- who **checks quality** (reviewer),
- who **writes documentation** (doc-writer),
- who **tidies up code** (refactorer),
- who **searches for information** (researcher).

Plus **special commands** ("skills", starting with `/`) that launch
ready-made procedures (e.g., the interview to understand what you want to build).

Plus **automatic rules** that activate on their own (e.g., when you touch a
`.py` file the Python rules kick in; after every change the code gets
formatted; secret files like `.env` are blocked).

You are the **boss**. You give orders, approve important decisions, and the
team works.

---

## 2. The 2 phases (the most important golden rule)

Building a project happens in **two separate phases**, in **two different
sessions** of Claude:

- **PHASE 1 — THINK**: decide *what* to build. A `SPEC.md` document is created
  (the project "shopping list") along with architecture decisions (ADR).
- **PHASE 2 — BUILD**: write the actual code, following what you decided
  in Phase 1.

**Why separate?** Because if you mix "thinking" and "writing code" in the same
chat, Claude gets confused (too much in its head). Between Phase 1 and Phase 2
you open a **fresh, clean session**.

> Hard words explained:
> - **SPEC.md** = the sheet that says *what* the project must do.
> - **ADR** = the sheet that says *how* a decision was made and *why*
>   (Architecture Decision Record). Found in `docs/architecture/`.
> - **HITL gate** = a point where Claude stops and waits for your OK
>   ("Human In The Loop" = there's a human in the loop). Happens before commits,
>   pushes, deploys, deletions.

---

## 3. Before you start (quick check, once)

The system is **already installed**. To make sure it works, open Claude in
any folder and type these commands (one at a time), press Enter, and check:

- `ls ~/.claude/agents/` (or ask Claude to list them) → you should see: architect,
  coder, reviewer, tester, debugger, doc-writer, refactorer, researcher. The `/agents`
  wizard was removed in CC 2.1.198.
- `/skills` → you should see the custom skills (adr-writer, claude-md-generator,
  swift-vibe, etc.).
- `/mcp` → `github` and `sequential-thinking` should be "connected".

If you see them, you are ready.

---

## 4. Creating a project — step by step

### Step 0 — Create the project folder

Open the Terminal. Type these commands **one at a time** (replace
`project-name` with the real name, no spaces):

```
mkdir -p ~/developer/project-name
```
```
cd ~/developer/project-name && git init
```
```
cd ~/developer/project-name && python3 -m venv .venv && source .venv/bin/activate
```

> What you did: created the folder, turned on "history saving" (git),
> created an isolated Python environment (venv) so you don't pollute your machine.

### Step 1 — Open Claude INSIDE the folder

```
cd ~/developer/project-name
claude
```

From here on, `/...` and `@...` commands are typed **inside Claude**, not in
the Terminal.

### Step 2 — PHASE 1: the interview (what you want to build)

Type inside Claude:

```
/interview-driver describe in one line what you want to build
```

Claude will ask you **questions, one at a time**. Answer carefully: dig into
the hard parts, don't give vague answers. At the end it writes `SPEC.md`.

> Tip: for a small project where you want to do everything at once, use
> `/project-bootstrap description` instead of `/interview-driver`: it runs
> the interview, architecture, and CLAUDE.md in sequence (stopping to ask for
> your OK between each step).

### Step 3 — Architecture decisions (ADR)

Still inside Claude, call the **architect**:

```
@"architect (agent)" read SPEC.md and write an ADR in docs/architecture/ with the main decisions and the rejected alternatives. Do not write code.
```

Read the ADR it produces. If it convinces you → **approve**. If something is
off → tell it and it will correct.

> Important: the **ADR is the plan**. For small/medium projects a separate plan
> is not needed: the ADR with its steps is enough.

### Step 4 — The project CLAUDE.md

```
/claude-md-generator
```

Creates the project `CLAUDE.md`: a sheet of instructions specific to
*this* project (commands, structure, its own rules). It inherits global rules
and does not repeat them. Check that it makes sense and is short (< ~100 lines).

### Step 5 — STOP and clean up (Phase 1 → Phase 2 transition)

You have finished "thinking". Now:

1. Make the first save in the project (in Terminal):
   ```
   cd ~/developer/project-name && git add -A && git commit -m "chore: initial spec and architecture"
   ```
2. **Close this Claude session** and **open a new one** in the same
   folder (clean session for Phase 2). Or type `/clear` inside Claude.

### Step 6 — PHASE 2: writing the code

Call the **coder**, telling it to follow the SPEC and ADR:

```
@"coder (agent)" implement the project following SPEC.md, the ADR in docs/architecture/ and CLAUDE.md. Do not commit.
```

The coder writes the code. You don't touch anything, just watch.

### Step 7 — The tests

```
@"tester (agent)" write and run tests (pytest) for the main logic, including edge cases. Do not modify production code.
```

### Step 8 — If something is broken

```
@"debugger (agent)" [paste the error or failing test here]. Find the root cause and apply the minimum fix.
```

### Step 9 — Quality check

```
@"reviewer (agent)" review the recent changes for security, correctness, performance and consistency. Output by severity.
```

It gives you a list split into BLOCKER / MAJOR / MINOR / NIT. You decide
what to apply.

### Step 10 — Documentation (optional)

```
@"doc-writer (agent)" update the README and CHANGELOG with what was done.
```

### Step 11 — Save and (optionally) open a Pull Request

In Terminal:
```
cd ~/developer/project-name && git add -A && git commit -m "feat: description of what you did"
```
For a PR (`gh` must be configured):
```
cd ~/developer/project-name && gh pr create --fill
```

> Claude will ask for confirmation before important actions (commit, push): that's
> the HITL gate. It is normal and intentional.

### Step 12 — Repeat for each new feature

For each new feature: go back to Step 6 (coder → tester → reviewer → commit).
**Between different unrelated features, type `/clear`** to clear Claude's context.

---

## 5. Quick reference — skills (`/` commands)

| Command | When to use | Triggered by... |
|---|---|---|
| `/interview-driver` | start of project/feature: understand what to build | you only (manually) |
| `/project-bootstrap` | small project: runs all of Phase 1 in sequence | you only (manually) |
| `/claude-md-generator` | create the project CLAUDE.md | manually (or automatic) |
| `/adr-writer` | write an architecture decision | automatic when needed |
| `/fastapi-react-vibe` | create a CRUD FastAPI+React piece | you only (manually) |
| `/code-review-checklist` | structured review | automatic / via reviewer |
| `/swift-vibe` | SwiftUI pattern help | automatic when needed |

> "you only (manually)" = Claude does NOT trigger it on its own, you must type it.

## 6. Quick reference — agents (`@"name (agent)"`)

| Agent | What it does | When |
|---|---|---|
| architect | designs, writes ADR, does NOT write code | start of non-trivial feature |
| coder | writes code following the ADR | after the ADR is approved |
| tester | writes and runs tests | after the coder |
| debugger | finds the root cause of bugs | when something is broken |
| reviewer | checks quality/security (read-only) | before commit |
| doc-writer | README, CHANGELOG, docstrings | when a feature is done |
| refactorer | tidies up without changing behavior | on request / after review |
| researcher | searches documentation with sources | unknown library/API |

## 7. Useful commands to know

| Command / keys | What it does |
|---|---|
| `/clear` | clears Claude's memory between different tasks |
| `/memory` | shows CLAUDE.md and loaded rules |
| `/skills` `/hooks` `/mcp` | show what is active (`/agents` wizard removed in 2.1.198; inspect `.claude/agents/`) |
| `Shift+Tab` | changes "permission mode" (plan mode, etc.) |
| `Esc` | stops Claude mid-action (without losing context) |
| `Esc Esc` or `/rewind` | goes back to a previous point |
| `! command` | runs a terminal command from inside Claude |
| `@filename` | makes Claude read a specific file |

## 8. The 7 golden rules (memorize them)

1. **Phase 1 and Phase 2 in separate sessions.** Never mix thinking and coding.
2. **`/clear` between different tasks.** Clean context = better Claude.
3. **The ADR is the plan.** If the ADR is approved, the coder can start.
4. **You approve the important things** (commit, push, deploy): that's the HITL gate.
5. **Never paste secrets in chat** (tokens, passwords). They go in `~/.zshrc` or
   config files, never in messages.
6. **If a test fails, do NOT disable it to make it pass.** Call the debugger.
7. **Long terminal commands**: paste them one at a time, short, to
   avoid them getting cut off.

## 9. What happens automatically (don't worry about it)

- Open a `.py` file → Python rules load (type hints, docstrings...).
  Same for `.swift`, `.ts/.tsx`, etc.
- Save a file → it gets **automatically formatted** (ruff/prettier).
- Try to touch `.env` or secret files → **automatically blocked**.
- Risky command → **auto** mode asks for confirmation; safe, known command →
  runs without interrupting you.

---

## 10. The full cycle, in one line

**folder + git + venv → `claude` inside → `/interview-driver` → `@architect`
(ADR) → `/claude-md-generator` → new session → `@coder` → `@tester` →
(`@debugger` if needed) → `@reviewer` → commit → repeat.**

Done. If you get lost, reopen this guide at the step where you are.
