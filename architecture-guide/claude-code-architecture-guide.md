# Claude Code Architecture Guide
> Token-efficient, orchestrated development using Opus + subagents + checkpoints.
> Apply this to every project from day one.

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Token Cost Model](#2-token-cost-model)
3. [Architecture Overview](#3-architecture-overview)
4. [Checkpoint System](#4-checkpoint-system)
5. [Subagents](#5-subagents)
6. [Opus Orchestration + Blueprint Format](#6-opus-orchestration--blueprint-format)
7. [Claude Code Configuration](#7-claude-code-configuration)
8. [Project Setup Checklist](#8-project-setup-checklist)
9. [File Structure](#9-file-structure)
10. [CLAUDE.md Template](#10-claudemd-template)
11. [Subagent Templates](#11-subagent-templates)
12. [Scripts](#12-scripts)

---

## 1. Core Concepts

### Agent
The main Claude instance running in your Claude Code session. This is the model you talk to directly. It has one context window — everything it reads, writes, and does accumulates there. This is the most expensive layer.

### Subagent
A separate Claude instance spawned by the main agent to handle a specific isolated task. It has its own fresh context window that disappears after the task. The main agent only receives the final output — all intermediate work (file reads, tool calls, errors) stays invisible inside the subagent.

### MCP (Model Context Protocol)
A protocol that lets Claude call external tools — like a plugin system. Behind an MCP tool can be anything: a bash command, a database, or another LLM (e.g. Gemini). The model calling the tool has no idea what runs behind it.

### Relationship

```
Main Agent (Opus)
  └── spawns Subagent (Haiku) for isolated tasks
        └── calls MCP tool (optional, e.g. Gemini behind it)
```

---

## 2. Token Cost Model

### How Tokens Accumulate

Every time the main agent responds, the **entire previous conversation is re-sent** to the model. You pay for all previous tokens plus new ones on every single turn.

```
Turn 1:   5k tokens
Turn 2:   5k + 5k  = 10k
Turn 3:   15k + 5k = 20k
Turn 10:  50k + 5k = 55k
```

### Context Window vs Quota

| | Quota | Context Window (200k) |
|---|---|---|
| Main agent turns | ✓ counted | Accumulates — shrinks free space |
| Subagent internal work | ✓ counted | Does NOT affect main window |
| Subagent output to main | ✓ counted | Only the output enters main window |
| MCP (external LLM) | ✗ not counted | Never enters any Claude window |

### Why Subagents Save Tokens

```
Without subagent:
  Main agent reads 50k of files directly
  → 50k enters main context window at Sonnet/Opus price
  → stays in context forever, re-paid every turn

With subagent:
  Haiku reads 50k internally (Haiku price, 3x cheaper)
  → main agent receives only 1k summary
  → main window never sees the 50k
```

### Cost Comparison: 10-Step Feature Without vs With Checkpoint

```
Without checkpoint (context multiplies):
  Step 1:  30k    Step 6:  80k
  Step 2:  37k    Step 7:  87k
  Step 3:  44k    Step 8:  94k
  Step 4:  51k    Step 9:  101k
  Step 5:  58k    Step 10: 108k
  Total: ~670k tokens

With checkpoint (context resets each step):
  Step 1:  30k (first step costs more, includes summarization)
  Step 2-10: ~15k each (5k checkpoint + new work only)
  Total: ~165k tokens  ← 75% reduction
```

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│              Main Agent — Opus 4.7              │
│                                                 │
│  Role: Orchestrator only                        │
│  Does: Plan, decide, produce blueprints         │
│  Never: Writes code, reads files, runs lint     │
│                                                 │
│  Context: CLAUDE.md + checkpoint + your query   │
└───────┬─────────────┬──────────────┬────────────┘
        │             │              │
        ▼             ▼              ▼
  file-reader    code-writer      linter
   (Haiku)        (Haiku)         (Haiku)
   reads files   writes code    runs checks
   returns 1k    from blueprint  fixes errors
   summary       no decisions    log-writer
                                 (Haiku)
                                 writes LOGS/
```

### Delegation Map

| Task | Delegate to |
|---|---|
| Read / scan / search files | `file-reader` |
| Write / edit code | `code-writer` |
| Run lint, fix errors | `linter` |
| Write log entries | `log-writer` |
| Everything else | Main agent stays |

---

## 4. Checkpoint System

### The Problem It Solves

Without checkpoints, token cost grows unboundedly across steps. With checkpoints, each step starts from a fixed small context (~5k) regardless of project history.

### Workflow

```
Complete a group of steps
        ↓
Auto-generate checkpoint JSON
        ↓
Paste JSON into .claude/checkpoint.json
        ↓
Run ./scripts/save-checkpoint.sh
        ↓
CLAUDE.md rebuilt with checkpoint injected
        ↓
/clear in Claude Code
        ↓
Next step starts fresh with only ~5k checkpoint context
```

### Checkpoint JSON Schema

```json
{
  "last_completed": "Group name and short description",
  "session_date": "YYYY-MM-DD",
  "files_modified": [
    { "path": "relative/path", "what_changed": "one line" }
  ],
  "files_created": [
    { "path": "relative/path", "purpose": "one line" }
  ],
  "files_to_read_next": ["relative/path"],
  "decisions_made": ["decision and reason"],
  "known_issues": ["issue and affected file"],
  "env_vars_added": ["VAR_NAME: purpose"],
  "next_step_context": "exact description of what next session needs"
}
```

### Key Fields

- `files_to_read_next` — the most important field. Keeps next step lean by specifying only necessary files.
- `next_step_context` — must be specific enough that next session never needs to re-read the conversation.
- `decisions_made` — preserves architectural reasoning across sessions.

---

## 5. Subagents

### How They Work

Subagents are defined as `.md` files in `.claude/agents/`. Claude Code automatically makes them available. Each one has:

```markdown
---
name: agent-name
description: When to use this agent (Claude reads this to decide)
tools: Read, Write, Edit, Bash, Glob, Grep
model: haiku
---

System prompt for the agent...
```

### The Four Core Agents

#### `file-reader` — Context Gatherer
- Model: Haiku
- Tools: Read, Grep, Glob, LS
- Output: Dense per-file summaries (purpose, exports, deps, issues)
- Never modifies files

#### `code-writer` — Blueprint Implementer
- Model: Haiku
- Tools: Read, Write, Edit
- Input: Compressed blueprint from main agent
- Never makes architectural decisions

#### `linter` — Validator + Fixer
- Model: Haiku
- Tools: Bash, Read, Write, Edit
- Runs: `yarn lint:fix` → `yarn lint` → `tsc --noEmit <changed files>`
- Fixes errors directly, up to 3 attempts

#### `log-writer` — Logger
- Model: Haiku
- Tools: Read, Write
- Reads LOG_INSTRUCTIONS.md, writes to LOGS/

### Token Flow With Subagents

```
Main agent sends task:        ~200 tokens   (task prompt)
Subagent does internal work:  ~50k tokens   (invisible to main)
Subagent returns result:      ~1k tokens    (only this enters main context)

Main agent cost:              ~1.2k tokens total from this exchange
vs. doing it directly:        ~50k tokens entering main context
```

---

## 6. Opus Orchestration + Blueprint Format

### The Principle

Opus is expensive because of reasoning depth — not its ability to type boilerplate. Use Opus only for what requires intelligence. Delegate everything else to Haiku.

```
Opus job:   architecture, decisions, patterns, edge cases
Haiku job:  translate blueprint into code — no thinking required
```

### Blueprint Format Rules

**Remove all of:**
- Articles: a, an, the
- Filler: "you should", "this will", "make sure to", "note that"
- Full sentences — use notation only
- Redundant whitespace

**Use this notation:**

| Notation | Meaning |
|---|---|
| `file:<path>` | File to create or edit |
| `func <name>(<p>:<T>):<R>` | Function signature |
| `!<step>` | Implementation step (ordered) |
| `throws:<E>\|<E>` | Errors to handle |
| `{k:T, k:T}` | Object shape / interface |
| `T[]` | Array type |
| `T?` | Optional field |
| `A\|B` | Union / alternative |
| `deps:<x>\|<x>` | Imports needed |
| `calls:<svc>.<method>` | External call required |

### Blueprint Example

```
file:src/checkout/checkout.service.ts
types:
  CheckoutInput{cartId:string,userId:string,paymentMethodId:string}
  CheckoutResult{orderId:string,status:'success'|'failed',message:string}
funcs:
  initiateCheckout(input:CheckoutInput):Promise<CheckoutResult>
    !validate cart !verify payment ownership !call payment gateway
    !create order on success !clear cart on success
    throws:PaymentFailedError|CartEmptyError
  validateCart(cartId:string):Promise<Cart>
    !fetch cart !check items>0 !check age<24h
    throws:CartEmptyError|CartExpiredError
deps:CartService|PaymentService|OrderRepository|logger
```

### Token Saving from Blueprint Compression

```
Verbose blueprint:    ~800 tokens
Compressed blueprint: ~150 tokens
Savings per step:     ~650 tokens at Opus price
Across 10 steps:      ~6,500 tokens saved on blueprints alone
```

---

## 7. Claude Code Configuration

### Model Setting (Permanent)

`~/.claude/settings.json`:
```json
{
  "model": "opus",
  "permissions": {}
}
```

### Effort Level

Opus 4.7 defaults to `xhigh` in Claude Code — no action needed for most sessions.

| Level | Use when |
|---|---|
| `low` | Classification, formatting, simple extraction |
| `medium` | Routine tasks, short summaries |
| `high` | Standard coding tasks |
| `xhigh` | Complex multi-file work (default, recommended) |
| `max` | Formal verification, security audits, exhaustive reasoning |

```bash
/effort xhigh      # set for session (already default)
/effort max        # only for specific hard problems
```

Persist via environment variable:
```bash
export CLAUDE_CODE_EFFORT_LEVEL=xhigh    # in .bashrc / .zshrc
```

### Session Commands

```bash
/model     # confirm active model
/effort    # confirm effort level
/context   # see token breakdown by component
/usage     # session total + estimated cost
/clear     # clear context (use after every checkpoint)
/agents    # list available subagents
```

### Add to CLAUDE.md for Opus 4.7 Compatibility

Opus 4.7 is more literal than 4.6. Vague prompts produce narrow results. Your CLAUDE.md must be explicit — exact formats, exact delegation rules, exact output expectations. Never rely on the model to infer intent.

---

## 8. Project Setup Checklist

```
□ Copy CLAUDE.md template → edit Stack + Project Goal sections
□ Copy .claude/agents/ folder (4 agent files)
□ Copy .claude/commands/checkpoint.md
□ Copy scripts/save-checkpoint.sh → chmod +x
□ Create .claude/checkpoint.json (empty file)
□ Verify package.json has: lint, lint:fix scripts
□ Set ~/.claude/settings.json → "model": "opus"
□ Run /effort xhigh on first session start
□ Run /context to verify CLAUDE.md loaded correctly
```

---

## 9. File Structure

```
your-project/
├── CLAUDE.md                          ← auto-loaded, rebuilt by checkpoint script
├── plans/                             ← plan files (never edited, only created)
│   └── YYYYMMDD_HHMM_short-title.md
├── LOGS/                              ← log files written by log-writer subagent
├── .claude/
│   ├── checkpoint.json                ← paste checkpoint JSON here
│   ├── checkpoint-history/            ← auto-backups (add to .gitignore)
│   ├── agents/
│   │   ├── file-reader.md
│   │   ├── code-writer.md
│   │   ├── linter.md
│   │   └── log-writer.md
│   └── commands/
│       └── checkpoint.md             ← /checkpoint slash command
└── scripts/
    └── save-checkpoint.sh            ← rebuilds CLAUDE.md from checkpoint.json
```

---

## 10. CLAUDE.md Template

```markdown
# Claude Code Session Rules

> This file is auto-loaded by Claude Code at the start of every session.
> Follow ALL sections in order before doing anything else.

---

## On Every Session Start

1. Read [your architecture/conventions file]
2. Read the latest plan file in `plans/` directory
3. Read the **Current Checkpoint** section at the bottom of this file
4. Briefly confirm:
   - What files you've read
   - What the last checkpoint's next step was
5. Wait for the user's instruction — do not start making changes yet

---

## On Every New Feature, Change, or Bug Fix

> Every task — no matter how small — must be planned before touched.
> You are the architect. You think, decide, and direct. You do not write code.

### Step 1 — Break Down Into Groups and Steps

Format:
Group 1: <name> — <one line purpose>
  Step 1.1 — <what changes, which file>
  Step 1.2 — <what changes, which file>

Rules:
- Single responsibility per group
- Minimum files per step
- Ordered by dependency
- Bug fixes, config, and features never in same group

### Step 2 — Write the Plan File

Write to plans/YYYYMMDD_HHMM_short-title.md
Include: goal, all groups/steps, files per step, risks/unknowns
Never update existing plan files — always create new ones

### Step 3 — Present the Plan

Present in chat then say exactly:
"Plan written to plans/[filename]. Ready to execute Group 1 on your approval. Waiting."

### Step 4 — Wait for Explicit Approval

Do not produce any blueprint until user approves.
Accepted: "go", "proceed", "yes", "approved", "execute", or group name.

### Step 5 — Execute One Group at a Time

Per step sequence:
1. Delegate file-reader subagent to gather context
2. Produce compressed blueprint
3. Delegate code-writer subagent with blueprint
4. Delegate linter subagent with list of changed files
5. Linter runs: yarn lint:fix → yarn lint → tsc <changed files>
6. If errors remain → linter fixes → re-runs checks
7. Only move to next step when all three checks are clean

Never write code. Always delegate to code-writer.
Never skip lint. Every code change must be validated.

### Step 6 — After Each Group Completes

1. Write log file via log-writer subagent
2. Auto-generate checkpoint (same format as /checkpoint)
3. Tell user what next group is
4. Say exactly: "Group [N] complete. Checkpoint generated above.
   Run ./scripts/save-checkpoint.sh then /clear before Group [N+1]."
5. Stop and wait — never auto-proceed

---

## Blueprint Format

Remove: articles, filler phrases, full sentences, redundant whitespace
Use notation:
  file:<path>              → file to create/edit
  func <n>(<p>:<T>):<R>   → function signature
  !<step>                  → implementation step (ordered)
  throws:<E>|<E>           → errors to handle
  {k:T}                    → object shape
  T?                       → optional field
  A|B                      → union type
  deps:<x>|<x>             → imports
  calls:<svc>.<method>     → external calls

---

## Subagent Delegation Map

Context needed    → file-reader
Code to write     → code-writer (with blueprint)
Lint/type errors  → linter
Log to write      → log-writer

---

## On Every Checkpoint

Generate JSON only — no extra text:
{
  "last_completed": "",
  "session_date": "YYYY-MM-DD",
  "files_modified": [{"path": "", "what_changed": ""}],
  "files_created": [{"path": "", "purpose": ""}],
  "files_to_read_next": [],
  "decisions_made": [],
  "known_issues": [],
  "env_vars_added": [],
  "next_step_context": ""
}

Then say: "Checkpoint ready. Run ./scripts/save-checkpoint.sh then /clear."

---

## Hard Rules

- Never write code — produce blueprints, delegate to code-writer
- Never skip lint validation — yarn lint:fix, yarn lint, tsc must pass
- Never install packages without user confirmation
- Never run destructive commands without explicit approval
- Always write plan first — never jump to blueprints
- Never update plan files — create new ones
- Never execute next group automatically — always stop and wait
- Never skip checkpointing — every completed group must checkpoint
- Never hallucinate file paths — ask or state UNKNOWN
- If unsure about scope — ask, do not assume

---

## Stack
[your stack here]

## Project Goal
[your project goal here]

---

## Current Checkpoint
No checkpoint yet. This is the start of the project.
```

---

## 11. Subagent Templates

### `.claude/agents/file-reader.md`

```markdown
---
name: file-reader
description: >
  Read, scan, and summarize files before any coding task.
  Use when context about existing code is needed before producing a blueprint.
  Returns dense summaries only — never writes or modifies files.
tools: Read, Grep, Glob, LS
model: haiku
---

You are a fast file reader. Read requested files and return dense summaries.

Output format per file:
<path>
  purpose:<one line>
  exports:<func|type|class, ...>
  key_vars:<name:type, ...>
  deps:<import, ...>
  issues:<TODOs, hacks, known problems>

Rules:
- Never modify files
- One block per file, no prose between them
- If not found: <path> NOT_FOUND
- If empty: <path> EMPTY
- Omit empty fields

End with: Read <N> files. Ready.
```

### `.claude/agents/code-writer.md`

```markdown
---
name: code-writer
description: >
  Implement code from a compressed blueprint. Use when main agent has produced
  a blueprint with file paths, function signatures, types, and steps.
  Never makes architectural decisions. Implements blueprint exactly.
tools: Read, Write, Edit
model: haiku
---

You are a code writer. You receive a compressed blueprint and implement it exactly.

Blueprint notation:
  file:<path>          → file to create or edit
  func <n>(p:T):R      → function signature to implement
  !<step>              → implementation step, follow in order
  throws:<E>|<E>       → errors to catch and handle
  {k:T}                → interface/type shape
  T?                   → optional field
  A|B                  → union type
  deps:<x>|<x>         → imports to add
  calls:<svc>.<method> → external call to make

Rules:
- Implement every function listed
- Follow ! steps in exact order
- Handle every error in throws:
- Add every import in deps:
- Match existing code style
- Never add functions not in blueprint
- Never make architectural decisions
- Ambiguous blueprint → write comment: // UNCLEAR: <what>
- No placeholders, no TODOs
- Never remove existing code unless blueprint says to

Return:
Done. Files written:
- <path> — <what was implemented>
```

### `.claude/agents/linter.md`

```markdown
---
name: linter
description: >
  Run lint and type checks after every code change. Use after every step
  that modifies or creates files. Fixes errors directly.
  Never writes new features — only fixes lint and type errors.
tools: Bash, Read, Write, Edit
model: haiku
---

You are a lint validator and fixer.

Workflow:
1. Run yarn lint:fix — auto-fix what ESLint can handle
2. Run yarn lint — check remaining errors
3. Run tsc --noEmit <changed_files> — type check changed files only
4. If all clean → report CLEAN and stop
5. If errors remain → read affected file, fix using Edit tool
6. Re-run steps 1-3 to verify
7. Repeat up to 3 attempts — if still failing, report FAILED

Running tsc on changed files only:
  tsc --noEmit file1.ts file2.ts ...

Fixing rules:
- Fix only lint and type errors — no refactoring
- Never change signatures unless required to fix type error
- Missing imports: add correct import, do not guess
- Unused variables: prefix with _ if removal breaks signature
- Architectural change required → flag NEEDS_REVIEW: <error> and skip

Output:
CLEAN
or
FIXED: <N> errors across <N> files
- <file>: <what was fixed>
or
FAILED: <N> errors remain
- <file>:<line> <error>
NEEDS_REVIEW:
- <file>:<line> <reason>
```

### `.claude/agents/log-writer.md`

```markdown
---
name: log-writer
description: >
  Write log files to LOGS/ directory after every completed group.
  Reads LOG_INSTRUCTIONS.md and writes a properly formatted log entry.
tools: Read, Write
model: haiku
---

Workflow:
1. Read LOG_INSTRUCTIONS.md for format rules
2. Write log file to LOGS/ following format exactly
3. Confirm file path

Rules:
- Never skip logging
- Follow LOG_INSTRUCTIONS.md exactly
- Specific about what changed and why — never vague
- One log file per group

Output: Log written: LOGS/<filename>
```

---

## 12. Scripts

### `scripts/save-checkpoint.sh`

```bash
#!/bin/bash
# Reads .claude/checkpoint.json and rebuilds CLAUDE.md
# Usage: paste JSON into .claude/checkpoint.json then run this script

set -e

CHECKPOINT_FILE=".claude/checkpoint.json"
CLAUDE_MD="CLAUDE.md"
BACKUP_DIR=".claude/checkpoint-history"

if [ ! -f "$CHECKPOINT_FILE" ]; then
  echo "❌ $CHECKPOINT_FILE not found."
  exit 1
fi

if ! python3 -m json.tool "$CHECKPOINT_FILE" > /dev/null 2>&1; then
  echo "❌ Invalid JSON in $CHECKPOINT_FILE."
  exit 1
fi

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
cp "$CHECKPOINT_FILE" "$BACKUP_DIR/checkpoint_$TIMESTAMP.json"
echo "📦 Backup: $BACKUP_DIR/checkpoint_$TIMESTAMP.json"

LAST_COMPLETED=$(python3 -c "import json; d=json.load(open('$CHECKPOINT_FILE')); print(d.get('last_completed',''))")
SESSION_DATE=$(python3 -c "import json; d=json.load(open('$CHECKPOINT_FILE')); print(d.get('session_date',''))")
NEXT_STEP=$(python3 -c "import json; d=json.load(open('$CHECKPOINT_FILE')); print(d.get('next_step_context',''))")
CHECKPOINT_JSON=$(cat "$CHECKPOINT_FILE")

STATIC_RULES=$(awk '/^## Stack/{exit} {print}' "$CLAUDE_MD")
STACK=$(awk '/^## Stack/{found=1;next} found && /^## /{found=0} found{print}' "$CLAUDE_MD" | grep -v '<!--' | sed '/^$/d')
GOAL=$(awk '/^## Project Goal/{found=1;next} found && /^## /{found=0} found{print}' "$CLAUDE_MD" | grep -v '<!--' | sed '/^$/d')

cat > "$CLAUDE_MD" << EOF
$STATIC_RULES
## Stack
$STACK

## Project Goal
$GOAL

---

## Current Checkpoint

**Last completed:** $LAST_COMPLETED ($SESSION_DATE)
**Next step:** $NEXT_STEP

\`\`\`json
$CHECKPOINT_JSON
\`\`\`

<!-- Auto-rebuilt by scripts/save-checkpoint.sh -->
EOF

echo "✅ CLAUDE.md rebuilt."
echo "📋 Last: $LAST_COMPLETED"
echo "➡️  Next: $NEXT_STEP"
echo "Now run /clear in Claude Code."
```

### `.claude/commands/checkpoint.md`

```markdown
# /checkpoint

Generate checkpoint summary of everything completed this session.

Rules:
- Dense notation only — no prose, no filler
- All file paths exact and relative to project root
- next_step_context must allow next session to continue without reading this conversation
- files_to_read_next: only files strictly needed for next step
- Output ONLY raw JSON block — no text before or after

{
  "last_completed": "",
  "session_date": "YYYY-MM-DD",
  "files_modified": [{"path": "", "what_changed": ""}],
  "files_created": [{"path": "", "purpose": ""}],
  "files_to_read_next": [],
  "decisions_made": [],
  "known_issues": [],
  "env_vars_added": [],
  "next_step_context": ""
}

After JSON, say exactly:
"Checkpoint ready. Run ./scripts/save-checkpoint.sh then /clear."
```

---

## Quick Reference Card

```
START SESSION
  /model → confirm opus
  /effort → confirm xhigh
  /context → check window state

FEATURE WORKFLOW
  You ask → Opus plans (groups + steps) → you approve
  Per step:
    file-reader gathers context
    Opus produces blueprint (compressed notation)
    code-writer implements blueprint
    linter validates: yarn lint:fix → yarn lint → tsc
  Per group:
    log-writer writes log
    Opus auto-generates checkpoint
    You: save JSON → run script → /clear

EFFORT LEVELS
  xhigh  = default, use always
  max    = specific hard problems only (resets after session)

SUBAGENT COSTS
  All count toward Anthropic quota
  Haiku = 3x cheaper than Sonnet, context stays isolated
  MCP (Gemini) = moves cost to Google quota entirely

TOKEN LEVERS (highest to lowest impact)
  1. Checkpoint + /clear between groups   → prevents unbounded growth
  2. Subagent context shielding           → heavy work stays isolated
  3. Opus blueprints only, Haiku codes    → expensive tokens on decisions only
  4. Compressed blueprint format          → reduces Opus output tokens
```
