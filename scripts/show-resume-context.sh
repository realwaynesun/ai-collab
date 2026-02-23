#!/bin/bash
# Display context needed for resuming a session

SESSION_DIR="$HOME/.ai-collab/session"
STATE_FILE="$SESSION_DIR/state.md"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "No session to resume"
    exit 1
fi

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  AI-Collab Resume Context                                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

echo "=== STATE ==="
head -20 "$STATE_FILE"
echo ""

if [[ -f "$SESSION_DIR/task.md" ]]; then
    echo "=== TASK ==="
    cat "$SESSION_DIR/task.md"
    echo ""
fi

if [[ -f "$SESSION_DIR/plan.md" ]]; then
    echo "=== PLAN (last 50 lines) ==="
    tail -50 "$SESSION_DIR/plan.md"
    echo ""
fi

if [[ -f "$SESSION_DIR/steps.md" ]]; then
    echo "=== STEPS ==="
    cat "$SESSION_DIR/steps.md"
    echo ""
fi

if [[ -f "$SESSION_DIR/review.md" ]]; then
    echo "=== LATEST REVIEW (last 30 lines) ==="
    tail -30 "$SESSION_DIR/review.md"
    echo ""
fi

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  Ready to resume. Continue the automatic workflow.           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
