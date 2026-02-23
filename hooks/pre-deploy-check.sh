#!/bin/bash
# AI-Collab Pre-Deploy Check
# Blocks deployment operations unless Codex has reviewed the code
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
REVIEW_MARKER="$SESSION_DIR/codex-review-passed"

# No active ai-collab session - allow
if [[ ! -f "$STATE_FILE" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Parse state
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')

# Session isolation: only enforce for the session that started the collab
SESSION_TTY=$(echo "$FRONTMATTER" | grep '^session_tty:' | sed 's/session_tty: *"//' | sed 's/"$//' || true)
CURRENT_TTY=$(tty 2>/dev/null || echo "unknown")

# If session_tty is missing or empty, assume orphaned collab - skip enforcement
if [[ -z "$SESSION_TTY" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# If current TTY is different from stored TTY, skip enforcement
if [[ "$SESSION_TTY" != "unknown" ]] && [[ "$CURRENT_TTY" != "$SESSION_TTY" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Not active - allow
if [[ "$ACTIVE" != "true" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Check if Codex review passed
if [[ ! -f "$REVIEW_MARKER" ]]; then
  echo "❌ [AI-Collab] BLOCKED: 部署操作被阻止" >&2
  echo "" >&2
  echo "   项目: $PROJECT_DIR" >&2
  echo "   原因: 代码尚未经过 Codex 审查" >&2
  echo "" >&2
  echo "   正确流程:" >&2
  echo "   1. Codex 写代码" >&2
  echo "   2. CC 执行并验证" >&2
  echo "   3. 如有问题 → 反馈给 Codex 修复" >&2
  echo "   4. 所有步骤完成 → 才能部署" >&2
  echo "" >&2
  echo "   请使用 call-codex.sh 让 Codex 审查代码" >&2
  exit 1
fi

# Review passed - check timestamp (must be recent, within 1 hour)
REVIEW_TIME=$(stat -f %m "$REVIEW_MARKER" 2>/dev/null || stat -c %Y "$REVIEW_MARKER" 2>/dev/null)
CURRENT_TIME=$(date +%s)
AGE=$((CURRENT_TIME - REVIEW_TIME))

if [[ $AGE -gt 3600 ]]; then
  echo "⚠️ [AI-Collab] WARNING: Codex 审查已过期 (${AGE}秒前)" >&2
  echo "   建议重新审查后再部署" >&2
fi

# Allow deployment
echo "$HOOK_INPUT"
exit 0
