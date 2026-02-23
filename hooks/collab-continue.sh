#!/bin/bash
# AI-Collab Stop Hook
# Prevents session exit when ai-collab workflow is active
# Feeds recovery prompt to continue from current state
#
# State is now stored in project directory: <project>/.ai-collab/

set -euo pipefail

# Find project with active ai-collab session
# Check current directory and parent directories
find_session() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.ai-collab/state.md" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_DIR=$(find_session) || exit 0
SESSION_DIR="$PROJECT_DIR/.ai-collab"
STATE_FILE="$SESSION_DIR/state.md"

# No active session - allow exit
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse YAML frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')

# Session isolation: only enforce for the session that started the collab
SESSION_TTY=$(echo "$FRONTMATTER" | grep '^session_tty:' | sed 's/session_tty: *"//' | sed 's/"$//' || true)
CURRENT_TTY=$(tty 2>/dev/null || echo "unknown")

# If session_tty is missing or empty, assume orphaned collab - skip enforcement
if [[ -z "$SESSION_TTY" ]]; then
  exit 0
fi

# If current TTY is different from stored TTY, skip enforcement
if [[ "$SESSION_TTY" != "unknown" ]] && [[ "$CURRENT_TTY" != "$SESSION_TTY" ]]; then
  exit 0
fi
CURRENT_STEP=$(echo "$FRONTMATTER" | grep '^current_step:' | sed 's/current_step: *//' || true)
CURRENT_STEP=${CURRENT_STEP:-0}
TOTAL_STEPS=$(echo "$FRONTMATTER" | grep '^total_steps:' | sed 's/total_steps: *//' || true)
TOTAL_STEPS=${TOTAL_STEPS:-0}
ALIGN_ITERATION=$(echo "$FRONTMATTER" | grep '^align_iteration:' | sed 's/align_iteration: *//' || true)
ALIGN_ITERATION=${ALIGN_ITERATION:-0}
MAX_ALIGN=$(echo "$FRONTMATTER" | grep '^max_align_iterations:' | sed 's/max_align_iterations: *//' || true)
MAX_ALIGN=${MAX_ALIGN:-5}
RETRY_COUNT=$(echo "$FRONTMATTER" | grep '^retry_count:' | sed 's/retry_count: *//' || true)
RETRY_COUNT=${RETRY_COUNT:-0}
MAX_RETRIES=$(echo "$FRONTMATTER" | grep '^max_retries:' | sed 's/max_retries: *//' || true)
MAX_RETRIES=${MAX_RETRIES:-3}

# Not active or completed - allow exit
if [[ "$ACTIVE" != "true" ]] || [[ "$PHASE" == "done" ]]; then
  exit 0
fi

# Check for max iterations in planning phase
if [[ "$PHASE" == "planning" ]] && [[ "$ALIGN_ITERATION" -ge "$MAX_ALIGN" ]]; then
  echo "⚠️ AI-Collab: Max alignment iterations ($MAX_ALIGN) reached" >&2
  echo "   Project: $PROJECT_DIR" >&2
  echo "   Run /collab:resume to continue or /collab:cancel to abort" >&2
  exit 0
fi

# Check for max retries in execution phase
if [[ "$PHASE" == "executing" ]] && [[ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]]; then
  echo "⚠️ AI-Collab: Max retries ($MAX_RETRIES) for current step" >&2
  echo "   Project: $PROJECT_DIR" >&2
  echo "   Run /collab:resume to continue or /collab:cancel to abort" >&2
  exit 0
fi

# Build recovery prompt based on current phase
if [[ "$PHASE" == "planning" ]]; then
  RECOVERY_PROMPT="Continue AI-Collab workflow.

Project: $PROJECT_DIR
Status: PLANNING phase, alignment iteration ${ALIGN_ITERATION}/${MAX_ALIGN}

Read these files to restore context:
1. $SESSION_DIR/state.md - Current state
2. $SESSION_DIR/task.md - Original task
3. $SESSION_DIR/plan.md - Current plan
4. $SESSION_DIR/review.md - Latest Codex review

Then continue the Planning Loop:
- If review.md contains 'No objections' -> Create execution steps, enter EXECUTING phase
- Otherwise -> Revise plan based on review, call Codex for another review

Use ~/.claude/skills/ai-collab/scripts/call-codex.sh to call Codex."

elif [[ "$PHASE" == "executing" ]]; then
  RECOVERY_PROMPT="Continue AI-Collab workflow.

Project: $PROJECT_DIR
Status: EXECUTING phase, Step ${CURRENT_STEP}/${TOTAL_STEPS}, retry ${RETRY_COUNT}/${MAX_RETRIES}

Read these files to restore context:
1. $SESSION_DIR/state.md - Current state
2. $SESSION_DIR/task.md - Original task
3. $SESSION_DIR/plan.md - Plan
4. $SESSION_DIR/steps.md - Execution steps
5. $SESSION_DIR/code/ - Generated code

Then continue the Execution Loop:
1. Call Codex to write code for Step ${CURRENT_STEP}
2. Execute and validate the code
3. Success -> Next step; Failure -> Send feedback to Codex for fix

Use ~/.claude/skills/ai-collab/scripts/call-codex.sh to call Codex."

else
  RECOVERY_PROMPT="Continue AI-Collab workflow.
Project: $PROJECT_DIR
Read $SESSION_DIR/state.md to determine current state and continue."
fi

# Build system message
SYSTEM_MSG="🔄 AI-Collab Resume | Project: $(basename "$PROJECT_DIR") | Phase: $PHASE | Step: $CURRENT_STEP/$TOTAL_STEPS"

# Block exit and feed recovery prompt
jq -n \
  --arg prompt "$RECOVERY_PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
