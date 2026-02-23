#!/bin/bash
# Grant ai-collab permissions for a project
# Usage: grant-permissions.sh [project_dir]
#
# Creates project-level settings.json with Edit, Write, Bash permissions
# NOTE: Permissions only take effect in NEW sessions!

PROJECT_DIR="${1:-$(pwd)}"
SETTINGS_DIR="$PROJECT_DIR/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

# Create .claude directory
mkdir -p "$SETTINGS_DIR"

# Create settings.json
cat > "$SETTINGS_FILE" << 'EOF'
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash"
    ]
  }
}
EOF

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  ✅ AI-Collab 权限已配置                                       ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  项目: $PROJECT_DIR"
echo "║  文件: $SETTINGS_FILE"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  ⚠️  重要：权限在【新会话】才会生效！                          ║"
echo "║                                                                ║"
echo "║  请执行以下步骤：                                              ║"
echo "║  1. 退出当前会话 (输入 /exit 或按 Ctrl+C)                      ║"
echo "║  2. 重新启动 Claude Code                                       ║"
echo "║  3. cd 到此项目目录                                            ║"
echo "║  4. 运行 /collab:start \"你的任务\"                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
