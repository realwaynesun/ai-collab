---
name: ai-collab
description: |
  Dual-AI collaboration workflow between CC (Claude Code) and Codex with integrated ticket tracking. Planning phase: CC drafts plan, Codex reviews, iterate until aligned, then CC creates execution steps as tickets. Execution phase: Codex writes code, CC executes and validates, rejects back to Codex if issues found. All steps are tracked via `tk` CLI.
  Commands:
  - /collab:start - Start new collaboration task
  - /collab:review - Have Codex review current plan
  - /collab:align - CC responds to review, continue alignment
  - /collab:proceed - Confirm alignment, enter execution phase
  - /collab:code - Have Codex write code for current step
  - /collab:exec - CC executes the code
  - /collab:reject - Reject code, send back to Codex
  - /collab:status - View current status (includes ticket status)
  - /collab:cancel - Cancel active collaboration
  - /collab:resume - Resume from last checkpoint (after context reset)
  - /collab:tickets - Show ticket tree for current collaboration
  - /collab:help - Show usage and options
---

# AI Collaboration Workflow

Dual-AI collaboration between CC (Claude Code) and Codex.

## Language Rules

| Context | Language |
|---------|----------|
| CC ↔ Codex communication | English |
| Internal files (plan.md, review.md, steps.md) | English |
| Progress display to user | Chinese |
| Final summary to user | Chinese |
| Error messages to user | Chinese |

---

## CRITICAL: Zero User Intervention

**User wants ZERO interruption. The entire workflow must complete without asking user ANYTHING.**

Rules:
1. **NEVER** ask user to run a command
2. **NEVER** ask user for confirmation
3. **NEVER** pause for user input (unless max retries exceeded)
4. **ALWAYS** proceed to next step automatically
5. **ALWAYS** retry on errors before giving up
6. **ALWAYS** save state so workflow can resume if crashed

### ⛔ FORBIDDEN PHRASES (Never output these)

These phrases will break automation. **ABSOLUTELY FORBIDDEN:**

```
❌ "是否需要我..."        → 直接做
❌ "要我继续吗..."        → 直接继续
❌ "请确认..."           → 不需要确认，直接执行
❌ "你想要..."           → 按计划执行
❌ "需要我部署吗..."      → 如果是计划的一部分，直接部署
❌ "Should I..."         → Just do it
❌ "Do you want me to..." → Just do it
❌ "Please confirm..."    → No confirmation needed
```

### ✅ CORRECT BEHAVIOR

| 场景 | ❌ 错误 | ✅ 正确 |
|------|--------|--------|
| 步骤完成 | "要继续下一步吗？" | 直接执行下一步 |
| 代码写好 | "需要我执行吗？" | 直接执行 |
| 测试通过 | "可以部署了，要部署吗？" | 直接部署（如果在计划中） |
| 遇到问题 | "怎么处理？" | 反馈给 Codex 或自己决策 |
| 不确定 | "请指示" | 根据计划自行判断，或询问 Codex |

### Decision Making

When uncertain, follow this priority:
1. Check if it's in the plan → Execute
2. Ask Codex for decision → Follow Codex's suggestion
3. Make reasonable decision yourself → Log decision in state file
4. **LAST RESORT** (only after max_retries): Pause and inform user

### ⛔ NEVER BYPASS CODEX REVIEW

The core principle of ai-collab is **dual-AI mutual review**. CC cannot replace Codex's review.

**ABSOLUTELY FORBIDDEN bypass phrases:**

```
❌ "Codex review skipped due to rate limiting"
❌ "Manually verified as resolved"
❌ "I checked and it looks fine"
❌ "Skipping re-review because..."
❌ "Issues verified by CC"
❌ Any form of CC self-reviewing instead of Codex
```

**When rate limited:**
```
✅ Wait and retry (call-codex.sh handles this automatically)
✅ Exponential backoff: 60s → 120s → 240s → 480s → 960s
✅ If still failing after 5 retries, PAUSE and inform user
✅ NEVER skip Codex review - NEVER "manually verify"
```

**Why this matters:**
- CC writing code + CC reviewing = No real review
- The whole point is ANOTHER AI (Codex) catches CC's mistakes
- "Manually verified" is CC lying to itself

The user will only:
- Run `/collab:start` once at the beginning
- Observe the progress
- Run `/collab:resume` if session was interrupted

User runs ONE command, then observes:
```bash
/collab:start "task description" [OPTIONS]
```

### Permission Setup (BEFORE Starting)

**Claude Code loads permissions at session start.** Mid-session changes don't take effect.

**At the START of /collab:start, BEFORE any other action:**

1. **Check if project permissions exist:**
   ```bash
   if [ -f "<project>/.claude/settings.json" ]; then
     # Permissions exist, proceed with workflow
   else
     # First time in this project
   fi
   ```

2. **If permissions DON'T exist (first time):**
   - Run: `~/.claude/skills/ai-collab/scripts/grant-permissions.sh [project_dir]`
   - Display message:
     ```
     ⚠️ 首次在此项目使用 ai-collab

     已创建权限文件: <project>/.claude/settings.json

     由于 Claude Code 在会话启动时加载权限，
     请【重启会话】后再次运行 /collab:start

     步骤：
     1. 输入 /exit 或按 Ctrl+C 退出当前会话
     2. 重新进入此项目目录
     3. 运行 /collab:start "你的任务"
     ```
   - **STOP HERE** - Do not continue the workflow

3. **If permissions EXIST:**
   - Proceed directly with the workflow (no questions asked)
   - Permissions were loaded at session start, everything is pre-approved

This creates `[project]/.claude/settings.json`:
     ```json
     {
       "permissions": {
         "allow": ["Edit", "Write", "Bash"]
       }
     }
     ```
   - This grants ALL permissions (Edit, Write, all Bash commands including Codex)

3. If user selects "No, ask each time":
   - Proceed normally, Claude Code will ask for each operation

4. Continue with the rest of /collab:start workflow

OPTIONS:
- `--max-align N` : Max alignment iterations (default: 5)
- `--max-retry N` : Max code fix retries (default: 3)
- `--project PATH` : Target project directory

The loop continues until:
1. ✅ Task completed successfully
2. ⚠️ Max iterations reached (asks user)
3. ❌ Unrecoverable error (asks user)
4. 🛑 User interrupts (Ctrl+C or message)

---

## Automatic Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  /collab:start "task"                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  PLANNING PHASE (auto-loop)                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CC drafts plan v1                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Codex reviews → "No objections"?                    │   │
│  │       ↓ NO              ↓ YES                        │   │
│  │  CC modifies plan   ────────────→ EXIT LOOP          │   │
│  │       ↓                                              │   │
│  │  (repeat, max N iterations)                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  CC creates execution steps                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  EXECUTION PHASE (auto-loop per step)                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Codex writes code for step N                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CC executes → Success?                              │   │
│  │       ↓ NO              ↓ YES                        │   │
│  │  Codex fixes code   → Next step (or DONE)            │   │
│  │       ↓                                              │   │
│  │  (retry, max N times)                                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  ✅ DONE - Display summary                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## State File

Location: `<project>/.ai-collab/state.md` (in project directory)

```markdown
---
active: true
phase: planning|executing|done
plan_version: 1
align_iteration: 0
max_align_iterations: 5
current_step: 0
total_steps: 0
retry_count: 0
max_retries: 3
session_id: "UUID"
session_tty: "/dev/ttys001"
epic_ticket_id: ""
step_tickets: []
started_at: "2026-01-24T22:00:00Z"
---

[Original task prompt]
```

**Session Isolation:** The `session_id` and `session_tty` fields ensure hooks only enforce rules for the terminal session that started the collaboration. Other sessions in the same project folder are not affected.

**Note:** Add `.ai-collab/` to project's `.gitignore`.

---

## Ticket Integration

ai-collab uses the `tk` CLI for git-native ticket tracking. Each collaboration creates:
- **Epic ticket**: The overall task
- **Step tickets**: One per execution step, with dependencies

### Prerequisites

Ensure `tk` CLI is available. If not installed, skip ticket creation and proceed without it.

### Ticket Lifecycle

```
/collab:start "task"
        │
        ▼
┌─────────────────────────────────────┐
│  tk create "task" -t epic -p 1      │  ← Epic ticket created
│  epic_ticket_id saved to state.md   │
└─────────────────────────────────────┘
        │
        ▼ (after plan alignment)
┌─────────────────────────────────────┐
│  For each step:                     │
│  tk create "Step N: name"           │
│    -t task -p 2 --parent <epic>     │
│  tk dep <step-N> <step-N-1>         │  ← Dependencies set
└─────────────────────────────────────┘
        │
        ▼ (during execution)
┌─────────────────────────────────────┐
│  tk start <step-ticket-id>          │  ← Before step execution
│  ... Codex writes code ...          │
│  ... CC executes ...                │
│  tk add-note <id> "result/error"    │  ← Progress notes
│  tk close <step-ticket-id>          │  ← On success
└─────────────────────────────────────┘
        │
        ▼ (on completion)
┌─────────────────────────────────────┐
│  tk close <epic-ticket-id>          │
│  git commit -m "feat: ... [<epic>]" │  ← Ticket ID in commit
└─────────────────────────────────────┘
```

### Ticket Commands

| Action | Command |
|--------|---------|
| Create epic | `tk create "Task summary" -t epic -p 1` |
| Create step | `tk create "Step N: name" -t task -p 2 --parent <epic>` |
| Set dependency | `tk dep <step-N> <step-N-1>` |
| Start step | `tk start <ticket-id>` |
| Add note | `tk add-note <ticket-id> "Progress or error"` |
| Close step | `tk close <ticket-id>` |
| View tree | `tk dep tree <epic-id>` |

### State File with Tickets

```markdown
---
active: true
phase: executing
plan_version: 3
align_iteration: 2
max_align_iterations: 5
current_step: 2
total_steps: 5
retry_count: 0
max_retries: 3
epic_ticket_id: "tk-a3f2"
step_tickets:
  - step: 1
    ticket_id: "tk-b7c1"
    status: closed
  - step: 2
    ticket_id: "tk-c8d2"
    status: in_progress
  - step: 3
    ticket_id: "tk-d9e3"
    status: open
  - step: 4
    ticket_id: "tk-e0f4"
    status: open
  - step: 5
    ticket_id: "tk-f1g5"
    status: open
started_at: "2026-01-24T22:00:00Z"
---
```

### Commit Message Convention

Always include ticket ID in commit messages:

```bash
git commit -m "feat: implement auth middleware [tk-b7c1]"
git commit -m "feat: add login endpoint [tk-c8d2]"
# Final commit for epic:
git commit -m "feat: complete user authentication [tk-a3f2]"
```

### Graceful Degradation

If `tk` is not available:
1. Check: `command -v tk >/dev/null 2>&1`
2. If missing: Log warning, proceed without tickets
3. All other functionality works normally

---

## Command: /collab:start

### Parse Arguments

```
/collab:start "task" [--max-align N] [--max-retry N] [--project PATH]
```

### Execution

1. **Initialize**:
   ```bash
   ~/.claude/skills/ai-collab/scripts/init-session.sh
   ```

2. **Create state file** `<project>/.ai-collab/state.md`:

   **IMPORTANT:** The `init-session.sh` script already creates this file with proper `session_tty`. If creating manually, you MUST include `session_tty` for session isolation to work.

   ```markdown
   ---
   active: true
   phase: planning
   plan_version: 1
   align_iteration: 0
   max_align_iterations: 5
   current_step: 0
   total_steps: 0
   retry_count: 0
   max_retries: 3
   session_id: "[UUID from uuidgen]"
   session_tty: "[OUTPUT of tty command, e.g., /dev/ttys001]"
   project_dir: "[PROJECT_DIR]"
   started_at: "[TIMESTAMP]"
   ---

   [TASK PROMPT]
   ```

   To get session_tty, run: `tty` in the terminal (e.g., `/dev/ttys001`)

3. **Save task** to `<project>/.ai-collab/task.md`

4. **Enter PLANNING LOOP** (do not exit until aligned):

   ```
   WHILE align_iteration < max_align_iterations:

     # CC drafts/modifies plan
     IF plan_version == 1:
       CC creates initial plan
     ELSE:
       CC modifies plan based on review

     Write plan to <project>/.ai-collab/plan.md
     Increment plan_version

     # Display progress
     PRINT "═══ Plan v{N} - Sending to Codex for review... ═══"

     # Call Codex
     response = call_codex("Review this plan...{plan content}")
     Save to <project>/.ai-collab/review.md

     # Display review
     PRINT "═══ Codex Review ═══"
     PRINT response

     # Check completion
     IF response contains "No objections":
       PRINT "✅ Plan aligned!"
       BREAK
     ELSE:
       Increment align_iteration
       CONTINUE

   IF align_iteration >= max_align_iterations:
     ASK USER: "Alignment stuck. Continue or modify?"
   ```

5. **Create execution steps with tickets**:
   - CC breaks plan into concrete steps
   - Write to `<project>/.ai-collab/steps.md`
   - **Create tickets** (if `tk` available):
     ```bash
     # Create epic ticket for the task
     epic_id=$(tk create "Task summary" -t epic -p 1 --json | jq -r '.id')

     # Create step tickets with dependencies
     prev_ticket=""
     for step in steps:
       ticket_id=$(tk create "Step $N: $name" -t task -p 2 --parent $epic_id --json | jq -r '.id')
       if [ -n "$prev_ticket" ]; then
         tk dep $ticket_id $prev_ticket
       fi
       prev_ticket=$ticket_id
     done
     ```
   - Update state: phase=executing, current_step=1, total_steps=N, epic_ticket_id, step_tickets

6. **Enter EXECUTION LOOP** (do not exit until done):

   ```
   WHILE current_step <= total_steps:

     step = get_step(current_step)
     ticket_id = get_step_ticket(current_step)
     retry_count = 0

     # Start ticket (if tk available)
     IF ticket_id:
       tk start $ticket_id

     WHILE retry_count < max_retries:

       # Display progress
       PRINT "═══ Step {current_step}/{total_steps}: {step.name} [{ticket_id}] ═══"

       # Codex writes code
       code = call_codex("Write code for: {step details}")
       Save to <project>/.ai-collab/code/step-{N}/

       # CC executes
       result = execute_code(code)

       IF result.success:
         PRINT "✅ Step {current_step} complete"
         # Close ticket and add note
         IF ticket_id:
           tk add-note $ticket_id "Completed successfully"
           tk close $ticket_id
         Increment current_step
         BREAK
       ELSE:
         PRINT "❌ Execution failed: {result.error}"
         # Add failure note to ticket
         IF ticket_id:
           tk add-note $ticket_id "Retry {retry_count}: {result.error}"
         Increment retry_count
         IF retry_count < max_retries:
           PRINT "🔄 Sending error to Codex for fix..."
           # Next iteration will fix
         ELSE:
           ASK USER: "Step failed after {max_retries} retries. Skip or abort?"
   ```

7. **Complete**:
   - Close epic ticket (if `tk` available):
     ```bash
     tk add-note $epic_ticket_id "All steps completed successfully"
     tk close $epic_ticket_id
     ```
   - Update state: phase=done
   - Archive to `~/.ai-collab/history/`
   - Display summary with ticket reference:
     ```
     ✅ 任务完成！
     Epic: [tk-a3f2] Task summary
     完成步骤: 5/5
     提交时请引用: [tk-a3f2]
     ```

---

## Codex Call Helper

**⚠️ MANDATORY: ALWAYS use this script to call Codex. NEVER call `codex exec` directly.**

```bash
~/.claude/skills/ai-collab/scripts/call-codex.sh "prompt" "[project_dir]"
```

Why:
- Script uses `--dangerously-bypass-approvals-and-sandbox` (no confirmations)
- Script handles rate limit retry automatically
- Direct `codex exec --full-auto` will STILL ask for confirmation!

❌ WRONG:
```bash
codex exec --full-auto "prompt"
head -400 plan.md | codex exec --full-auto "..."
```

✅ CORRECT:
```bash
~/.claude/skills/ai-collab/scripts/call-codex.sh "Review this plan..." ~/.ai-collab/session
```

For review:
```
Review this plan. If acceptable, respond with exactly 'No objections'.
Otherwise, list specific issues to fix.

---
[Plan content]
---
```

For code:
```
Write complete, working code for this step:

Step: [name]
Details: [instructions]
Project: [directory]

Output code with file paths as comments. Example:
# File: src/main.py
[code]
```

---

## Progress Display

After each major action, show:

```
╔═══════════════════════════════════════════════════════════════╗
║  AI-Collab: [task summary...]                                 ║
╠═══════════════════════════════════════════════════════════════╣
║  Phase:     PLANNING                                          ║
║  Epic:      [tk-a3f2] (pending tickets)                       ║
║  Plan:      v3 → Codex reviewing...                           ║
║  Alignment: 2/5 iterations                                    ║
╚═══════════════════════════════════════════════════════════════╝
```

Or:

```
╔═══════════════════════════════════════════════════════════════╗
║  AI-Collab: [task summary...]                                 ║
╠═══════════════════════════════════════════════════════════════╣
║  Phase:     EXECUTING                                         ║
║  Epic:      [tk-a3f2] Implement user authentication           ║
║  Step:      2/5 - "Implement API endpoints" [tk-c8d2]         ║
║  Progress:  ████████░░░░░░░░░░░░ 40%                          ║
║  Tickets:   1 ✅ closed, 1 🔄 in_progress, 3 ⏳ open          ║
║  Retries:   0/3                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## Manual Commands (intervention only)

| Command | Use when |
|---------|----------|
| `/collab:status` | Check progress anytime (includes ticket status) |
| `/collab:tickets` | View ticket dependency tree |
| `/collab:cancel` | Abort the workflow |
| `/collab:proceed` | Force skip alignment phase |
| `/collab:help` | Show options and usage |

---

## Command: /collab:cancel

1. Check if `<project>/.ai-collab/state.md` exists
2. If not: "No active collaboration"
3. If yes:
   - Read current state
   - Remove state file or set active=false
   - Report: "Cancelled at phase={phase}, step={current_step}"

---

## Command: /collab:status

1. Read `<project>/.ai-collab/state.md`
2. Read task, plan, steps files
3. Read ticket status (if `tk` available and epic_ticket_id exists):
   ```bash
   tk show $epic_ticket_id
   tk dep tree $epic_ticket_id
   ```
4. Display progress box with ticket info:
   ```
   ╔═══════════════════════════════════════════════════════════════╗
   ║  AI-Collab: [task summary...]                                 ║
   ╠═══════════════════════════════════════════════════════════════╣
   ║  Phase:     EXECUTING                                         ║
   ║  Epic:      [tk-a3f2] Implement user authentication           ║
   ║  Step:      2/5 - "Implement API endpoints" [tk-c8d2]         ║
   ║  Progress:  ████████░░░░░░░░░░░░ 40%                          ║
   ║  Tickets:   2 closed, 1 in_progress, 2 open                   ║
   ╚═══════════════════════════════════════════════════════════════╝
   ```

---

## Command: /collab:tickets

Show ticket tree for current collaboration.

1. Read `<project>/.ai-collab/state.md` to get `epic_ticket_id`
2. If no epic ticket: "No tickets for current collaboration"
3. Display ticket tree:
   ```bash
   tk dep tree $epic_ticket_id
   ```
4. Show step-ticket mapping:
   ```
   Ticket Tree for [tk-a3f2] Implement user authentication
   ├── [tk-b7c1] Step 1: Set up auth middleware     ✅ closed
   ├── [tk-c8d2] Step 2: Add login endpoint         🔄 in_progress
   │   └── depends on: tk-b7c1 ✅
   ├── [tk-d9e3] Step 3: Add session management     ⏳ open (blocked)
   │   └── depends on: tk-c8d2 🔄
   ├── [tk-e0f4] Step 4: Add logout endpoint        ⏳ open (blocked)
   │   └── depends on: tk-d9e3 ⏳
   └── [tk-f1g5] Step 5: Add tests                  ⏳ open (blocked)
       └── depends on: tk-e0f4 ⏳
   ```

---

## Error Handling

| Situation | Action |
|-----------|--------|
| Codex empty response | Retry once, then report |
| Codex rate limited | Auto-retry with exponential backoff (handled by call-codex.sh) |
| Alignment > max iterations | Pause, ask user |
| Code fails > max retries | Pause, ask user |
| Any crash | Save state, can resume |

### CRITICAL: Never Give Up

**If ANY error occurs (rate limit, timeout, network error):**

1. **DO NOT exit** the workflow immediately
2. Save current state to `<project>/.ai-collab/state.md`
3. Wait 60 seconds
4. Retry the failed operation
5. If still failing after 3 retries, THEN pause and inform user:
   ```
   ⏸️ 协作暂停
   原因: [error description]
   状态已保存，可用 /collab:resume 恢复
   ```

**The goal is to survive temporary failures and continue automatically.**

---

## Files Structure

```
<project>/
├── .ai-collab/              # Session data (add to .gitignore)
│   ├── state.md             # State with YAML frontmatter
│   ├── task.md              # Original task
│   ├── plan.md              # Current plan
│   ├── review.md            # Latest Codex review
│   ├── steps.md             # Execution steps
│   ├── plan-approved        # Marker: Codex approved plan
│   ├── codex-review-passed  # Marker: Codex approved code
│   └── code/
│       ├── step-1/
│       ├── step-2/
│       └── ...
└── .gitignore               # Should include: .ai-collab/

~/.ai-collab/
└── history/
    └── [timestamp]/         # Archived sessions (global)
```

---

## Context Management (Large Projects)

### Problem
Long tasks may exhaust Claude's context window before completion.

### Solution: Checkpoint & Resume

**All state is persisted to files.** If context runs out:

1. User starts new session
2. Runs `/collab:resume`
3. CC reads state files and continues from last checkpoint

### Auto-checkpoint

After each major action, state is saved:
- After each plan version
- After each Codex review
- After each step execution

### Command: /collab:resume

Resume collaboration from last checkpoint.

#### Steps

1. Check if `<project>/.ai-collab/state.md` exists
2. If not: "No session to resume"
3. If yes:
   - Read state file (phase, current_step, etc.)
   - Read task.md, plan.md, steps.md
   - Display current progress
   - Continue from where it stopped:
     - If phase=planning → continue alignment loop
     - If phase=executing → continue from current_step

#### Resume Prompt

When resuming, CC should:
```
Read these files to restore context:
1. <project>/.ai-collab/state.md (current state)
2. <project>/.ai-collab/task.md (original task)
3. <project>/.ai-collab/plan.md (current plan)
4. <project>/.ai-collab/steps.md (if exists)
5. <project>/.ai-collab/review.md (latest review)

Then continue the automatic workflow from the current phase.
```

### Using Sub-agents for Large Tasks

For very large tasks, delegate to sub-agents using Task tool:

```
Task(
  subagent_type="general-purpose",
  prompt="Execute step 3: Implement the API endpoints...",
  description="Execute collab step 3"
)
```

Benefits:
- Sub-agent has fresh context
- Main session stays lean
- Results returned to main session

### When to Use Sub-agents

- Individual step is complex (>1000 lines of code)
- Step requires extensive codebase exploration
- Multiple independent steps can run in parallel

---

## Best Practices for Large Projects

1. **Break into phases**: Use smaller, focused tasks
2. **Use --project**: Keep context focused on target directory
3. **Monitor progress**: Check `/collab:status` periodically
4. **Resume when needed**: Context reset is normal, just `/collab:resume`
5. **Leverage sub-agents**: For complex individual steps

---

## Batch Processing with Codex (Lessons Learned)

When sending large volumes of data to Codex for batch processing:

### 1. Rate Limit is Per-Session (CRITICAL)

- **Rate limiting happens at the session level, not globally**
- Same session with many requests → gets throttled heavily (1300+ sec delays)
- Different sessions (separate working directories) → each has independent limits
- Test: A simple request from a new session completes in ~2 sec while parallel workers are stuck

**Solution**: Use separate working directories for each parallel worker:
```bash
WORKER_DIR="/tmp/codex_worker_$i"
mkdir -p "$WORKER_DIR"
cd "$WORKER_DIR" && codex exec ...
```

### 2. Prompt Size Matters

| Prompt Size | Response Time | Reliability |
|-------------|---------------|-------------|
| 4000 chars  | Timeout (180s+) | Poor |
| 1500 chars  | 30-60s | Good |
| 500-800 chars | 10-30s | Best |

**Recommendation**: Keep prompts under 1500 chars. Split large texts into smaller chunks.

### 3. Monitor Each Pass Timing

Track individual operation times to detect rate limiting early:
```
Normal: 30-60 seconds
Warning: 180 seconds (timeout)
Critical: 1000+ seconds (severe throttling)
```

If seeing 180s+ consistently, reduce parallelism or switch sessions.

### 4. Parallel Processing Guidelines

| Workers | Result |
|---------|--------|
| 5+ | Triggers rate limits, empty responses |
| 3 | Stable with separate sessions |
| 2 | Conservative, most reliable |

### 5. Retry Logic Can Backfire

When rate-limited, automatic retries make things worse:
- Each retry counts against rate limit
- Delays compound (60s → 180s → 1300s)

**Better approach**: Detect rate limiting (timeout or empty response), then:
1. Pause for 30-60 seconds
2. Reduce parallelism
3. Switch to fresh session
