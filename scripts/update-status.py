#!/usr/bin/env python3
"""Update collaboration session status."""

import json
import sys
from datetime import datetime
from pathlib import Path

STATUS_FILE = Path.home() / ".ai-collab" / "session" / "status.json"

def load_status():
    if STATUS_FILE.exists():
        return json.loads(STATUS_FILE.read_text())
    return {
        "phase": "idle",
        "planVersion": 0,
        "currentStep": 0,
        "totalSteps": 0,
        "startedAt": None,
        "lastUpdated": None
    }

def save_status(status):
    status["lastUpdated"] = datetime.now().isoformat()
    STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATUS_FILE.write_text(json.dumps(status, indent=2))

def main():
    if len(sys.argv) < 2:
        print("Usage: update-status.py <key>=<value> [<key>=<value> ...]")
        sys.exit(1)

    status = load_status()

    for arg in sys.argv[1:]:
        if "=" not in arg:
            continue
        key, value = arg.split("=", 1)

        # Type conversion
        if value.isdigit():
            value = int(value)
        elif value == "true":
            value = True
        elif value == "false":
            value = False

        status[key] = value

    # Set startedAt on first update
    if status.get("startedAt") is None and status.get("phase") != "idle":
        status["startedAt"] = datetime.now().isoformat()

    save_status(status)
    print(json.dumps(status, indent=2))

if __name__ == "__main__":
    main()
