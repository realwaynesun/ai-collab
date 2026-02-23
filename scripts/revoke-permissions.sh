#!/bin/bash
# Revoke ai-collab permissions for a project directory
# Usage: revoke-permissions.sh [project_dir]

PROJECT_DIR="${1:-$(pwd)}"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    rm "$SETTINGS_FILE"
    echo "✓ Permissions revoked for: $PROJECT_DIR"
else
    echo "No permissions file found at: $SETTINGS_FILE"
fi
