#!/bin/bash
# AI-Collab Enforce Plan Approval
# Blocks execution phase unless Codex has approved the plan
#
# State is now stored in project directory: <project>/.ai-collab/

set -euo pipefail

# Read hook input
HOOK_INPUT=$(cat)

# Find project with active ai-collab session
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

PROJECT_DIR=$(find_session) || { echo "$HOOK_INPUT"; exit 0; }
SESSION_DIR="$PROJECT_DIR/.ai-collab"
STATE_FILE="$SESSION_DIR/state.md"
REVIEW_FILE="$SESSION_DIR/review.md"
PLAN_APPROVED_MARKER="$SESSION_DIR/plan-approved"

# No active ai-collab session - allow
if [[ ! -f "$STATE_FILE" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Parse state
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')

# Not active - allow
if [[ "$ACTIVE" != "true" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Only check when in executing phase
if [[ "$PHASE" != "executing" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Check if plan was approved by Codex
if [[ ! -f "$PLAN_APPROVED_MARKER" ]]; then
  # Check review.md for approval
  if [[ -f "$REVIEW_FILE" ]]; then
    if grep -qiE "(no objections|no issues|approved|lgtm|looks good)" "$REVIEW_FILE"; then
      # Codex approved - create marker
      touch "$PLAN_APPROVED_MARKER"
      echo "✅ Plan approved by Codex" >&2
      echo "$HOOK_INPUT"
      exit 0
    fi
  fi

  # No approval found
  echo "❌ [AI-Collab] BLOCKED: 执行阶段被阻止" >&2
  echo "" >&2
  echo "   项目: $PROJECT_DIR" >&2
  echo "   原因: 计划尚未经过 Codex 审批" >&2
  echo "" >&2
  echo "   正确流程:" >&2
  echo "   1. CC 制定计划 (plan.md)" >&2
  echo "   2. Codex 审核计划" >&2
  echo "   3. Codex 回复 'No objections'" >&2
  echo "   4. 然后才能进入执行阶段" >&2
  echo "" >&2
  echo "   请先完成 Planning 阶段的对齐。" >&2
  exit 1
fi

# Plan approved - allow
echo "$HOOK_INPUT"
exit 0
