#!/usr/bin/env python3
"""Update collaboration session state (YAML frontmatter in state.md)."""

import re
import sys
from datetime import datetime
from pathlib import Path

STATE_FILE = Path.home() / ".ai-collab" / "session" / "state.md"

def parse_frontmatter(content: str) -> tuple[dict, str]:
    """Parse YAML frontmatter and body from markdown."""
    match = re.match(r'^---\n(.*?)\n---\n?(.*)', content, re.DOTALL)
    if not match:
        return {}, content

    yaml_str, body = match.groups()
    state = {}
    for line in yaml_str.strip().split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip().strip('"')
            # Type conversion
            if value.isdigit():
                value = int(value)
            elif value == 'true':
                value = True
            elif value == 'false':
                value = False
            state[key] = value
    return state, body

def serialize_frontmatter(state: dict, body: str) -> str:
    """Serialize state to YAML frontmatter markdown."""
    lines = ['---']
    for key, value in state.items():
        if isinstance(value, bool):
            lines.append(f'{key}: {str(value).lower()}')
        elif isinstance(value, str) and (' ' in value or ':' in value):
            lines.append(f'{key}: "{value}"')
        else:
            lines.append(f'{key}: {value}')
    lines.append('---')
    lines.append('')
    lines.append(body)
    return '\n'.join(lines)

def main():
    if len(sys.argv) < 2:
        print("Usage: update-state.py <key>=<value> [<key>=<value> ...]")
        print("       update-state.py --get <key>")
        print("       update-state.py --show")
        sys.exit(1)

    if not STATE_FILE.exists():
        print("No active session")
        sys.exit(1)

    content = STATE_FILE.read_text()
    state, body = parse_frontmatter(content)

    # Handle --show
    if sys.argv[1] == '--show':
        for key, value in state.items():
            print(f"{key}: {value}")
        return

    # Handle --get
    if sys.argv[1] == '--get' and len(sys.argv) >= 3:
        key = sys.argv[2]
        print(state.get(key, ''))
        return

    # Handle updates
    for arg in sys.argv[1:]:
        if '=' not in arg:
            continue
        key, value = arg.split('=', 1)

        # Type conversion
        if value.isdigit():
            value = int(value)
        elif value == 'true':
            value = True
        elif value == 'false':
            value = False

        state[key] = value

    # Write back
    STATE_FILE.write_text(serialize_frontmatter(state, body))
    print(f"Updated: {', '.join(sys.argv[1:])}")

if __name__ == "__main__":
    main()
