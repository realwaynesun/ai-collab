#!/bin/bash
# AI-Collab Enforce Codex Writes
# During execution phase, warns if CC is writing code directly instead of using Codex
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
CODEX_WRITING_MARKER="$SESSION_DIR/.codex-writing"

# No active ai-collab session - allow
if [[ ! -f "$STATE_FILE" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Parse state
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//')

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

# Not active or not in executing phase - allow
if [[ "$ACTIVE" != "true" ]] || [[ "$PHASE" != "executing" ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Get the file being edited
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // ""')

# Skip non-code files (allow editing configs, docs, etc.)
if [[ ! "$FILE_PATH" =~ \.(py|js|ts|tsx|jsx|go|rs|java|c|cpp|h|hpp|rb|php|swift|kt)$ ]]; then
  echo "$HOOK_INPUT"
  exit 0
fi

# Check if Codex is currently writing (marker set by call-codex.sh)
if [[ -f "$CODEX_WRITING_MARKER" ]]; then
  # Codex initiated this write - allow
  echo "$HOOK_INPUT"
  exit 0
fi

# CC is writing code directly during execution phase - warn
echo "⚠️ [AI-Collab] WARNING: 在执行阶段直接编写代码" >&2
echo "" >&2
echo "   项目: $PROJECT_DIR" >&2
echo "   AI-Collab 流程要求:" >&2
echo "   - 执行阶段的代码应该由 Codex 编写" >&2
echo "   - CC 负责执行和验证" >&2
echo "" >&2
echo "   如果这是在应用 Codex 生成的代码，请忽略此警告。" >&2
echo "   如果你在自己写代码，请改用:" >&2
echo "   ~/.claude/skills/ai-collab/scripts/call-codex.sh \"Write code for...\"" >&2
echo "" >&2

# Still allow (just warn, don't block)
echo "$HOOK_INPUT"
exit 0
