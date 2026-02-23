#!/bin/bash
# Initialize a new collaboration session
# Usage: init-session.sh [--max-align N] [--max-retry N] [--project PATH] "task"
#
# State is now stored in project directory: <project>/.ai-collab/

set -euo pipefail

# Defaults
MAX_ALIGN=5
MAX_RETRY=3
PROJECT_DIR="$(pwd)"
TASK=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-align)
      MAX_ALIGN="$2"
      shift 2
      ;;
    --max-retry)
      MAX_RETRY="$2"
      shift 2
      ;;
    --project)
      PROJECT_DIR="$2"
      shift 2
      ;;
    *)
      TASK="$1"
      shift
      ;;
  esac
done

# Session directory is now in project
SESSION_DIR="$PROJECT_DIR/.ai-collab"

# Clean and recreate session directory
rm -rf "$SESSION_DIR"
mkdir -p "$SESSION_DIR/code"

# Add .ai-collab to .gitignore if not present
GITIGNORE="$PROJECT_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
    if ! grep -q "^\.ai-collab" "$GITIGNORE"; then
        echo ".ai-collab/" >> "$GITIGNORE"
        echo "📝 Added .ai-collab/ to .gitignore"
    fi
elif [[ -d "$PROJECT_DIR/.git" ]]; then
    echo ".ai-collab/" > "$GITIGNORE"
    echo "📝 Created .gitignore with .ai-collab/"
fi

# Generate session ID and capture TTY for session isolation
SESSION_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)
SESSION_TTY=$(tty 2>/dev/null || echo "unknown")

# Create state file with YAML frontmatter
cat > "$SESSION_DIR/state.md" << EOF
---
active: true
phase: planning
plan_version: 0
align_iteration: 0
max_align_iterations: $MAX_ALIGN
current_step: 0
total_steps: 0
retry_count: 0
max_retries: $MAX_RETRY
session_id: "$SESSION_ID"
session_tty: "$SESSION_TTY"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$TASK
EOF

# Create task file
if [[ -n "$TASK" ]]; then
  echo "$TASK" > "$SESSION_DIR/task.md"
fi

echo "🚀 AI-Collab session initialized"
echo ""
echo "  Project: $PROJECT_DIR"
echo "  Session: $SESSION_DIR"
echo "  Max alignment iterations: $MAX_ALIGN"
echo "  Max code retries: $MAX_RETRY"
echo ""
