# The easy guide to the Vibe Coding system

**Who this guide is for:** anyone who has never programmed (even a 12-year-old kid), and wants to understand **what was built** and **how to use it** without getting lost in hard words.

**What you will learn:**
1. What Claude Code is (in 1 minute)
2. The team of "programmer robots" that helps you
3. The magic tools (skills)
4. The castle guards (hooks)
5. The computer's notebook (memory)
6. How to do your first project from start to finish
7. Things NOT to do
8. Glossary of hard words

---

## 1. What Claude Code is (in 1 minute)

Imagine having a **friend who is very good at programming** and lives inside your computer. You write what you want to do and they write the code for you. It is called **Claude Code**.

But there is a problem: one friend, even a very good one, cannot do everything well. For example, they are good at writing code but maybe not the best at checking it, or writing tests, or reorganizing it.

**The solution:** instead of one friend, we built **a team of robot-friends**, each specializing in a different thing. It is called a **multi-agent system** (multi = many, agent = robot that does a specific thing).

---

## 2. The team of programmer robots

Think of a soccer team: every player has a role. Here too we have 8 "robot-players", each with their own job.

| Robot | What it does | How to remember it |
|-------|---------|-----------------|
| **architect** | Draws the plans before building (like a real architect) | "Architect" |
| **coder** | Writes the code (the bricklayer of the team) | "Code" |
| **reviewer** | Checks that the code is well made (the inspector) | "Review = check" |
| **tester** | Runs the tests (tries if everything works) | "Test = try" |
| **debugger** | Finds bugs (the bugs in the code) | "Bug = bug, debug = find-the-bug" |
| **refactorer** | Reorganizes the code without breaking it (tidies up) | "Refactor = put back together" |
| **doc-writer** | Writes the documentation (instruction manuals) | "Doc = document" |
| **researcher** | Searches for information online (the librarian) | "Research = search" |

**The team's golden rule:**
> Only the "captain" (the **orchestrator**, i.e., the main terminal session) can call the players. The players CANNOT call other players. They are like soloists.

### How do you "call" a robot?

You do not call them directly: you write what you want to the **orchestrator** (the main Claude-friend) and they decide which robot to send. It is a bit like giving an order to the coach, who then sends the right players onto the field.

---

## 3. The magic tools (skills)

Every robot can use **magic tools** called **skills** (in English this means "abilities"). They are like items in a video game: each one does something special.

Here are the 3 most important tools we built **today**:

### Tool 1: `review-triage-fix` (the check cycle)

**What it is for:** after the coder writes some code, this tool runs the reviewer to find problems, then gets the coder to fix the most serious ones, and repeats until everything is fine.

**Example:** it is like when you finish your homework, your mum checks it, tells you "there is an error here", you correct it, and then your mum checks it again.

### Tool 2: `refactor-snapshot` (the photographer)

**What it is for:** before the refactorer reorganizes the code, it takes a **photograph** of how it works. After reorganizing, it takes another photo and compares them. If the photos are the same, perfect. If they are different, it means something broke during the reorganization and it warns you.

**Example:** it is like when you tidy your room and want to make sure all your toys still work. First you try them all (photo 1), move them around, then try them all again (photo 2). If one no longer works, you broke it during the tidying.

### Tool 3: `concept-to-code` (the orchestra conductor)

**What it is for:** this is the most important tool. It takes you from the **idea** ("I want to make a dice game") to the **finished code**, going through all the steps in the right order. It automatically calls the architect, then the coder, then (if you want) the reviewer.

**Example:** it is like when you bake a cake. You cannot turn the oven on before you have the ingredients. There is an order. `concept-to-code` is the recipe that says "first do X, then Y, then Z".

---

### Other useful tools (we found or built them)

| Tool | What it does |
|-----------|---------|
| `interview-driver` | Asks you lots of questions to understand what you really want (an interview) |
| `adr-writer` | Writes a special document called an ADR (see glossary) |
| `claude-md-generator` | Creates the project "manual" (CLAUDE.md) |
| `brainstorming` | Helps you think together before starting |
| `commit` | Saves your work on Git (see glossary) |

---

## 4. The castle guards (hooks)

Imagine your computer is a castle. There are dangerous spots: for example, **deleting a file** is dangerous because if you make a mistake you lose everything.

That is why we put **automatic guards** called **hooks** (in English "hook", because they "hook onto" dangerous actions). When a robot is about to do something dangerous, the guard stops it and asks first before continuing.

**Our guards:**

- **`stop-gate`**: stops the robot before it does dangerous things (like deleting files)
- **`approve-test-cmd`**: asks before running a command that launches tests (because tests can modify files)
- **`migrate-trust-paths`**: cleans the list of "trusted friends" of the castle

You do not have to do anything for the guards: they work automatically in the background.

---

## 5. The computer's notebook (memory)

You know when a classmate tells you something and you write it in a notebook so you don't forget? Our system does exactly that, automatically.

**Where the notebook lives:**
`~/.claude/projects/.../memory/`

**What it writes:**
- Things about you (example: "Stefano prefers technical, brief answers")
- Lessons learned (example: "this bash does not support associative arrays")
- Status of ongoing projects
- Links to external systems

**When it is used:**
Every time a new session starts, the computer re-reads the notebook and remembers everything.

### The project manual: `CLAUDE.md`

Besides the general notebook, every project has its own **manual** called **`CLAUDE.md`**. It is like a video game guide: it explains the specific rules for that project.

---

## 6. STEP-BY-STEP: how to do your first project

Let's say you want to make a small guessing game. Here is how you would do it.

### Step 1: Open the terminal and type `claude`

The chat with the Claude-friend (the orchestrator) opens.

### Step 2: Launch `/concept-to-code`

Type this and press enter:

```
/concept-to-code number guessing game
```

From here on the system guides you.

### Step 3: The interview (Step 1 of the chain)

The `interview-driver` will ask you questions to understand exactly what you want:
- Which language? (Python? JavaScript?)
- How many attempts can the player make?
- Do you want the computer to suggest "higher" / "lower"?
- Do you want a score?

You answer. At the end a file called `SPEC.md` is written (the "recipe" for your project).

### Step 4: FIRST GATE — You approve the spec

The system shows you `SPEC.md` and asks: **"Is this ok?"**

If yes, continue. If no, you change it and repeat.

### Step 5: The architecture (Step 2 of the chain)

The robot **architect** is called. They read `SPEC.md` and produce 3 things:
- An **ADR** (architectural decision — see glossary)
- A file **`ARCH.md`** (how the project is organized)
- A **TDD plan** (the steps to follow)

### Step 6: SECOND GATE — You approve the architecture

The system shows you the 3 files. You check and say "ok, continue" or "change this".

### Step 7: The project manual (Step 3 of the chain)

The tool **`claude-md-generator`** is called, which writes the **project manual** (`CLAUDE.md`).

### Step 8: THIRD GATE — You approve the manual

Same thing: you check, you approve.

### Step 9: Fresh session (Step 4 of the chain — IMPORTANT)

The system tells you:

> "Now close this session and open a new one. When you are in the new one, type: `/concept-to-code resume <manifest-path>`"

**Why?** Because the current session is full of the interview questions and answers. For the next step you need "a fresh mind" (a fresh session). It is like when you have studied for 3 hours and need a break before starting the actual homework.

### Step 10: The implementation (Step 5 of the chain)

In the new session, the system calls the robot **coder** who, reading all the files (`SPEC.md`, ADR, `ARCH.md`, `CLAUDE.md`), starts writing the code.

**What the coder does specially:** before every change, it declares a **label** saying what kind of change it is making:
- `PATTERN: ADD` = I am adding new code
- `PATTERN: REMOVE` = I am deleting code
- `PATTERN: REPLACE` = I am substituting old code with new (and MUST say what it removes + what it adds)
- `PATTERN: MODIFY` = I am modifying something existing without changing structure

This label is called the **Pre-flight Pattern Classifier** and is one of the things we built today. It prevents the coder from forgetting to delete old code when replacing it with new.

### Step 11: Review (Step 6 of the chain — optional)

If you want, you launch `review-triage-fix` which runs the **reviewer** to check the code, flag problems, and gets the coder to fix the important things.

### Step 12: You are done!

Your game is ready. You try it. If it works, celebrate. If not, see below.

---

## 7. Things NOT to do (safety)

1. **NEVER delete files** without being asked. The computer cannot put back deleted things.
2. **NEVER commit secret files** (passwords, API keys, `.env` files). They are like a house key: you don't give them to anyone.
3. **NEVER disable a test** just to make it pass. A red test tells you there is a problem. Turning it off does not solve the problem, it hides it.
4. **NEVER run `rm -rf`** without thinking 3 times. It deletes everything, permanently.
5. **NEVER write directly to the `main` branch** of Git. Always on a **feature branch** (see glossary).
6. **ALWAYS ASK** before doing things you don't understand. Better to ask 10 times than break everything 1 time.

---

## 8. If something goes wrong

### Case A: the code does not work
1. Call the robot **debugger**: "find the problem in this code"
2. It tells you what is wrong and why
3. You (or the coder) fix it

### Case B: the computer says "command not found"
1. Maybe you typed a command wrong
2. Check upper/lowercase (the computer is fussy)

### Case C: tests turn red
1. It means something broke
2. Do NOT disable the tests! Find the problem.
3. Launch the **debugger** or ask the Claude-friend

### Case D: you are afraid of breaking everything
1. Before making big changes, launch **refactor-snapshot** (the photographer)
2. That way if you break something you know straight away

---

## 9. GLOSSARY — hard words explained

| Word | What it means (simple version) |
|--------|-----------------------------------|
| **agent** | A robot that does a specific thing |
| **orchestrator** | The boss-robot that calls the other robots |
| **skill** | A magic tool that a robot can use |
| **hook** | An automatic guard that stops dangerous things |
| **CLAUDE.md** | The instruction manual of a project |
| **memory** | The computer's notebook |
| **terminal** | The black window where you type commands |
| **prompt** | What you type to the Claude-friend |
| **Git** | A system that saves all versions of your code (like "save as" on a huge scale) |
| **commit** | Saving a version of the code in Git |
| **branch** | A "parallel version" of the code, where you can experiment without breaking the main one |
| **main branch** | The "official" version of the code |
| **feature branch** | A trial version where you do new things |
| **PR (Pull Request)** | A request to merge your branch with main |
| **ADR** | Architecture Decision Record — a document that explains WHY we decided something in a certain way |
| **SPEC** | Specification — what the program must do (the recipe) |
| **ARCH** | Architecture — how the program is organized (the building plan) |
| **TDD** | Test-Driven Development — write tests first, then the code. It works better than any other method |
| **plan** | The list of steps to follow (the to-do list) |
| **harness** | An automatic system that checks things are still working |
| **anchor** | A kind of "bookmark" in the code that lets automatic tests find things |
| **bash** | The language of terminal commands (Mac/Linux) |
| **Python** | A simple and powerful programming language |
| **MCP** | A connection to external services (e.g., GitHub, Slack) |
| **fresh session** | Opening a new chat with the Claude-friend from scratch |
| **HITL gate** | "Human In The Loop" — a point where your approval is needed |
| **dispatch** | Sending a robot onto the field |
| **manifest** | A list (in YAML format) that says what a project contains and where it is |

---

## 10. Summary in 5 sentences

1. **Claude Code** is a programmer friend that lives in the terminal.
2. It works with a **team of 8 specialized robots**.
3. Each one uses **magic tools (skills)** to do their job.
4. When you want a new project, launch **`/concept-to-code`** and follow the instructions.
5. **Never delete things without thinking** and **always ask** if you are not sure.

---

## 11. Fun things to know

- Our system knows that **bash scripts run on a 2007 version** (Mac's bash 3.2), so when it writes bash code it is careful not to use new features. It is like writing to a grandparent in dialect.
- The robots work **in parallel** (up to 4 at the same time): the orchestrator can send 4 robots to 4 different windows to do 4 different things, and then collects all the results. It is like having 4 cooks making 4 different dishes in the same kitchen.
- When a robot makes a mistake, **it does not hide it**: it tells you. For example if you ask it to delete an important file, it says "no, let me know if you are sure".
- Every now and then **Anthropic** (the company that makes Claude) updates the robots and they get better. The system underneath is designed not to break with updates.

---

## 12. What to do tomorrow

If this is your first time:

1. **Open the terminal** and type `claude` to call the Claude-friend
2. Ask it "**help me make a small Python program that tells me if a number is even or odd**"
3. Watch what it does
4. When you have finished that program, try **/concept-to-code** for something more complicated

And remember: **there is nothing magic about it**. It is all code and files. If you break something, you can usually fix it. The important thing is to **ask**, **check**, and **have fun**.

---

*This guide is the "easy" version of the technical document `vibe-coding-system.md`. If you ever want the full details, that is the file to read — but not before you are 16, it gives adults headaches too.*
