#!/usr/bin/env python3
"""Get and display collaboration session status."""

import json
from pathlib import Path

SESSION_DIR = Path.home() / ".ai-collab" / "session"
STATUS_FILE = SESSION_DIR / "status.json"

def main():
    if not STATUS_FILE.exists():
        print("No active session")
        return

    status = json.loads(STATUS_FILE.read_text())

    # Read task summary if exists
    task_file = SESSION_DIR / "task.md"
    task_summary = ""
    if task_file.exists():
        lines = task_file.read_text().strip().split("\n")
        task_summary = lines[0][:50] if lines else ""

    # Calculate progress
    current = status.get("currentStep", 0)
    total = status.get("totalSteps", 0)
    progress = f"{current}/{total}" if total > 0 else "N/A"
    percent = f"({int(current/total*100)}%)" if total > 0 else ""

    print(f"""
=== AI Collaboration Status ===
Phase:        {status.get('phase', 'idle')}
Task:         {task_summary or 'None'}
Plan Version: v{status.get('planVersion', 0)}
Progress:     {progress} {percent}
Started:      {status.get('startedAt', 'N/A')}
Last Updated: {status.get('lastUpdated', 'N/A')}
================================
""")

if __name__ == "__main__":
    main()
