#!/usr/bin/env python3
"""Display collaboration progress."""

import re
from pathlib import Path

SESSION_DIR = Path.home() / ".ai-collab" / "session"
STATE_FILE = SESSION_DIR / "state.md"

def parse_frontmatter(content: str) -> dict:
    """Parse YAML frontmatter from markdown."""
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return {}

    state = {}
    for line in match.group(1).strip().split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip().strip('"')
            if value.isdigit():
                value = int(value)
            elif value == 'true':
                value = True
            elif value == 'false':
                value = False
            state[key] = value
    return state

def main():
    if not STATE_FILE.exists():
        print("No active session")
        return

    state = parse_frontmatter(STATE_FILE.read_text())

    # Read task summary
    task_file = SESSION_DIR / "task.md"
    task = ""
    if task_file.exists():
        task = task_file.read_text().strip()[:50]
        if len(task_file.read_text().strip()) > 50:
            task += "..."

    phase = state.get('phase', 'unknown')

    print("╔═══════════════════════════════════════════════════════════════╗")
    print(f"║  AI-Collab: {task:<50} ║")
    print("╠═══════════════════════════════════════════════════════════════╣")

    if phase == 'planning':
        plan_v = state.get('plan_version', 0)
        align_iter = state.get('align_iteration', 0)
        max_align = state.get('max_align_iterations', 5)
        print(f"║  Phase:     PLANNING                                          ║")
        print(f"║  Plan:      v{plan_v}                                              ║")
        print(f"║  Alignment: {align_iter}/{max_align} iterations                                    ║")

    elif phase == 'executing':
        current = state.get('current_step', 0)
        total = state.get('total_steps', 0)
        retry = state.get('retry_count', 0)
        max_retry = state.get('max_retries', 3)

        if total > 0:
            pct = int(current / total * 100)
            filled = int(pct / 5)
            bar = '█' * filled + '░' * (20 - filled)
        else:
            pct = 0
            bar = '░' * 20

        print(f"║  Phase:     EXECUTING                                         ║")
        print(f"║  Step:      {current}/{total}                                             ║")
        print(f"║  Progress:  {bar} {pct:>3}%                         ║")
        print(f"║  Retries:   {retry}/{max_retry}                                               ║")

    elif phase == 'done':
        print(f"║  Phase:     ✅ DONE                                            ║")

    print("╚═══════════════════════════════════════════════════════════════╝")

if __name__ == "__main__":
    main()
