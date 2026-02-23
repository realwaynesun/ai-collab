#!/bin/bash
# Check if project has ai-collab permissions set up
# Usage: check-permissions.sh [project_dir]
# Exit code: 0 = ready, 1 = needs setup

PROJECT_DIR="${1:-$PWD}"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Check if it has Bash permission
    if grep -q '"Bash"' "$SETTINGS_FILE"; then
        echo "✅ 权限已配置: $SETTINGS_FILE"
        exit 0
    else
        echo "⚠️ 权限文件存在但缺少 Bash 权限"
        exit 1
    fi
else
    echo "❌ 权限未配置"
    echo ""
    echo "此项目首次使用 ai-collab，需要设置权限。"
    echo ""
    echo "请运行以下命令创建权限文件："
    echo "  ~/.claude/skills/ai-collab/scripts/grant-permissions.sh $PROJECT_DIR"
    echo ""
    echo "然后【重启会话】后再运行 /collab:start"
    exit 1
fi
