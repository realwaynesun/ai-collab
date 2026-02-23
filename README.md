# AI-Collab: Dual-AI Collaboration Workflow

[English](#english) | [中文](#中文)

---

<a name="english"></a>
## English

### Overview

AI-Collab enables collaboration between **Claude Code (CC)** and **OpenAI Codex CLI** for software development tasks. The two AIs review each other's work, ensuring higher quality output than either could achieve alone. **Now with integrated ticket tracking via `tk` CLI.**

**Workflow:**
```
Planning Phase:
CC drafts plan → Codex reviews → iterate until "No objections" → create execution steps

Step Ticketing:
Epic ticket created → Step tickets with dependencies → Track progress via tk

Execution Phase:
tk start → Codex writes code → CC executes & validates → tk close → repeat until success
```

### Prerequisites

1. **Claude Code** - Anthropic's CLI tool
2. **OpenAI Codex CLI** - Install and login with ChatGPT subscription:
   ```bash
   npm install -g @openai/codex
   codex login
   ```
3. **tk CLI** (optional but recommended) - Git-native ticket tracking:
   - If `tk` is available, each execution step becomes a trackable ticket
   - If not installed, the workflow proceeds without ticket tracking

### Installation

1. Copy the `ai-collab` folder to your Claude Code skills directory:
   ```bash
   cp -r ai-collab ~/.claude/skills/
   ```

2. Make scripts executable:
   ```bash
   chmod +x ~/.claude/skills/ai-collab/scripts/*.sh
   chmod +x ~/.claude/skills/ai-collab/hooks/*.sh
   ```

3. Add permissions to your global settings (`~/.claude/settings.json`):
   ```json
   {
     "permissions": {
       "allow": [
         "Bash(~/.claude/skills/ai-collab/scripts/*)",
         "Bash(~/.claude/skills/ai-collab/hooks/*)"
       ]
     }
   }
   ```

4. **(Optional) Add hooks based on your needs.** The `hooks/` directory provides several safety hooks — pick and choose what fits your workflow:

   | Hook | What it does | When to use |
   |------|-------------|-------------|
   | `collab-continue.sh` | Prevents Claude Code from exiting mid-collaboration | You want to ensure workflows run to completion |
   | `pre-deploy-check.sh` | Blocks `deploy`/`git push`/`npm publish` without Codex review | You want deployment gating |
   | `enforce-plan-approval.sh` | Requires explicit plan approval before execution | You want stricter planning control |
   | `enforce-codex-writes.sh` | Ensures only Codex writes code during execution phase | You want strict role separation |

   Example — adding the stop guard and deploy gate:
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "matcher": "*",
           "hooks": [{"type": "command", "command": "~/.claude/skills/ai-collab/hooks/collab-continue.sh"}],
           "description": "[AI-Collab] Prevent exit until workflow completes"
         }
       ],
       "PreToolUse": [
         {
           "matcher": "tool == \"Bash\" && tool_input.command matches \"(deploy|git push|npm publish)\"",
           "hooks": [{"type": "command", "command": "~/.claude/skills/ai-collab/hooks/pre-deploy-check.sh"}],
           "description": "[AI-Collab] Block deployment without Codex review"
         }
       ]
     }
   }
   ```

   > **Permission note:** Adding hooks to `~/.claude/settings.json` means they apply to **all** your projects globally. If you only want hooks active for specific projects, add them to `<project>/.claude/settings.json` instead. The `permissions.allow` entries grant the scripts the right to execute without prompting — review them and only allow what you're comfortable with.

### Usage

#### First Time in a Project

```bash
# 1. Navigate to your project
cd /path/to/your/project

# 2. Grant permissions (creates .claude/settings.json)
~/.claude/skills/ai-collab/scripts/grant-permissions.sh

# 3. RESTART your Claude Code session (required for permissions to load)

# 4. Start collaboration
/collab:start "Implement user authentication with JWT"
```

#### Subsequent Uses (Same Project)

```bash
cd /path/to/your/project
/collab:start "Add password reset feature"
```

#### Commands

| Command | Description |
|---------|-------------|
| `/collab:start "task"` | Start new collaboration |
| `/collab:status` | Check current progress (includes ticket status) |
| `/collab:tickets` | View ticket dependency tree |
| `/collab:resume` | Resume after interruption |
| `/collab:cancel` | Cancel active collaboration |

#### Options

```bash
/collab:start "task" --max-align 10 --max-retry 5 --project /path/to/project
```

| Option | Default | Description |
|--------|---------|-------------|
| `--max-align` | 5 | Max planning alignment iterations |
| `--max-retry` | 3 | Max code fix retries per step |
| `--project` | Current dir | Target project directory |

### Default Settings

#### Global Settings (`~/.claude/settings.json`)

Only ai-collab scripts are pre-approved globally:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/skills/ai-collab/scripts/*)",
      "Bash(~/.claude/skills/ai-collab/hooks/*)"
    ]
  }
}
```

#### Project Settings (`<project>/.claude/settings.json`)

Created by `grant-permissions.sh`, allows all operations within the project:

```json
{
  "permissions": {
    "allow": ["Edit", "Write", "Bash"]
  }
}
```

### Customization

After importing, you can ask Claude Code to modify settings. Examples:

#### Example 1: Restrict Bash to specific commands only

```
"Please modify my project's .claude/settings.json to only allow git and python commands"
```

Result:
```json
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash(git *)",
      "Bash(python *)",
      "Bash(pip *)"
    ]
  }
}
```

#### Example 2: Add deployment protection globally

```
"Add a hook to require confirmation before any deployment command"
```

#### Example 3: Change default iteration limits

```
"Modify SKILL.md to set default max-align to 10 and max-retry to 5"
```

#### Example 4: Add custom review criteria

```
"Update the Codex review prompt to also check for security vulnerabilities"
```

### File Structure

```
~/.claude/skills/ai-collab/
├── SKILL.md                 # Main skill definition
├── README.md                # This file
├── scripts/
│   ├── call-codex.sh        # Codex CLI wrapper with retry
│   ├── grant-permissions.sh # Project permission setup
│   ├── check-permissions.sh # Permission verification
│   └── init-session.sh      # Session initialization
└── hooks/
    ├── collab-continue.sh         # Prevent premature exit
    ├── pre-deploy-check.sh  # Deployment gate
    ├── enforce-plan-approval.sh
    └── enforce-codex-writes.sh

<project>/.ai-collab/        # Session data (per-project)
├── state.md                 # Current state
├── task.md                  # Original task
├── plan.md                  # Current plan
├── review.md                # Codex reviews
├── steps.md                 # Execution steps
├── codex-session-id         # Codex session for context
└── code/                    # Generated code
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Permission prompts appear | Restart session after running `grant-permissions.sh` |
| Codex rate limited | Script auto-retries with exponential backoff |
| Context lost mid-task | Run `/collab:resume` |
| Workflow won't exit | Check `.ai-collab/state.md`, set `phase: done` or delete file |

---

<a name="中文"></a>
## 中文

### 概述

AI-Collab 实现 **Claude Code (CC)** 与 **OpenAI Codex CLI** 的双 AI 协作开发。两个 AI 互相审查对方的工作，确保比单独使用任一 AI 更高质量的输出。**现已集成 `tk` CLI 工单追踪功能。**

**工作流程：**
```
规划阶段：
CC 制定计划 → Codex 审查 → 迭代直到 "No objections" → 创建执行步骤

工单创建：
创建 Epic 工单 → 为每个步骤创建子工单 → 设置依赖关系 → 通过 tk 追踪进度

执行阶段：
tk start → Codex 写代码 → CC 执行验证 → tk close → 重复直到成功
```

### 前置条件

1. **Claude Code** - Anthropic 的 CLI 工具
2. **OpenAI Codex CLI** - 安装并用 ChatGPT 订阅登录：
   ```bash
   npm install -g @openai/codex
   codex login
   ```
3. **tk CLI**（可选但推荐）- Git 原生工单追踪：
   - 如果 `tk` 可用，每个执行步骤都会成为可追踪的工单
   - 如果未安装，工作流将在没有工单追踪的情况下继续

### 安装

1. 复制 `ai-collab` 文件夹到 Claude Code skills 目录：
   ```bash
   cp -r ai-collab ~/.claude/skills/
   ```

2. 设置脚本可执行权限：
   ```bash
   chmod +x ~/.claude/skills/ai-collab/scripts/*.sh
   chmod +x ~/.claude/skills/ai-collab/hooks/*.sh
   ```

3. 在全局设置 (`~/.claude/settings.json`) 中添加权限：
   ```json
   {
     "permissions": {
       "allow": [
         "Bash(~/.claude/skills/ai-collab/scripts/*)",
         "Bash(~/.claude/skills/ai-collab/hooks/*)"
       ]
     }
   }
   ```

4. **（可选）根据需要添加 hooks。** `hooks/` 目录提供了多个安全钩子——按需选用：

   | Hook | 功能 | 适用场景 |
   |------|------|----------|
   | `collab-continue.sh` | 阻止 Claude Code 在协作中途退出 | 你希望确保工作流完整执行 |
   | `pre-deploy-check.sh` | 拦截 `deploy`/`git push`/`npm publish` 直到 Codex 审查通过 | 你需要部署门禁 |
   | `enforce-plan-approval.sh` | 要求执行前必须明确批准计划 | 你需要更严格的规划控制 |
   | `enforce-codex-writes.sh` | 确保执行阶段只有 Codex 写代码 | 你需要严格的角色分离 |

   示例 — 添加退出保护和部署门禁：
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "matcher": "*",
           "hooks": [{"type": "command", "command": "~/.claude/skills/ai-collab/hooks/collab-continue.sh"}],
           "description": "[AI-Collab] 工作流完成前阻止退出"
         }
       ],
       "PreToolUse": [
         {
           "matcher": "tool == \"Bash\" && tool_input.command matches \"(deploy|git push|npm publish)\"",
           "hooks": [{"type": "command", "command": "~/.claude/skills/ai-collab/hooks/pre-deploy-check.sh"}],
           "description": "[AI-Collab] 未经 Codex 审查不允许部署"
         }
       ]
     }
   }
   ```

   > **权限说明：** 将 hooks 添加到 `~/.claude/settings.json` 意味着它们会**全局生效**于所有项目。如果你只希望特定项目启用 hooks，请添加到 `<project>/.claude/settings.json`。`permissions.allow` 条目授予脚本免提示执行的权限——请审查这些条目，只允许你确认安全的操作。

### 使用方法

#### 首次在某项目使用

```bash
# 1. 进入项目目录
cd /path/to/your/project

# 2. 授予权限（创建 .claude/settings.json）
~/.claude/skills/ai-collab/scripts/grant-permissions.sh

# 3. 重启 Claude Code 会话（权限需要重启才能加载）

# 4. 开始协作
/collab:start "实现用户认证功能，使用 JWT"
```

#### 再次使用（同一项目）

```bash
cd /path/to/your/project
/collab:start "添加密码重置功能"
```

#### 命令列表

| 命令 | 说明 |
|------|------|
| `/collab:start "任务"` | 开始新的协作 |
| `/collab:status` | 查看当前进度（含工单状态） |
| `/collab:tickets` | 查看工单依赖树 |
| `/collab:resume` | 中断后恢复 |
| `/collab:cancel` | 取消当前协作 |

#### 参数选项

```bash
/collab:start "任务" --max-align 10 --max-retry 5 --project /path/to/project
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--max-align` | 5 | 规划阶段最大对齐迭代次数 |
| `--max-retry` | 3 | 每步代码修复最大重试次数 |
| `--project` | 当前目录 | 目标项目目录 |

### 默认设置

#### 全局设置 (`~/.claude/settings.json`)

只有 ai-collab 脚本被全局预授权：

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/skills/ai-collab/scripts/*)",
      "Bash(~/.claude/skills/ai-collab/hooks/*)"
    ]
  }
}
```

#### 项目设置 (`<project>/.claude/settings.json`)

由 `grant-permissions.sh` 创建，允许项目内所有操作：

```json
{
  "permissions": {
    "allow": ["Edit", "Write", "Bash"]
  }
}
```

### 定制化

导入后，你可以让 Claude Code 帮你修改设置。示例：

#### 示例 1：限制 Bash 只允许特定命令

```
"请修改我项目的 .claude/settings.json，只允许 git 和 python 命令"
```

结果：
```json
{
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "Bash(git *)",
      "Bash(python *)",
      "Bash(pip *)"
    ]
  }
}
```

#### 示例 2：全局添加部署保护

```
"添加一个 hook，在任何部署命令前要求确认"
```

#### 示例 3：修改默认迭代次数

```
"修改 SKILL.md，把默认的 max-align 改成 10，max-retry 改成 5"
```

#### 示例 4：添加自定义审查标准

```
"更新 Codex 审查的 prompt，让它也检查安全漏洞"
```

### 文件结构

```
~/.claude/skills/ai-collab/
├── SKILL.md                 # 主技能定义
├── README.md                # 本文件
├── scripts/
│   ├── call-codex.sh        # Codex CLI 封装（含重试）
│   ├── grant-permissions.sh # 项目权限设置
│   ├── check-permissions.sh # 权限检查
│   └── init-session.sh      # 会话初始化
└── hooks/
    ├── collab-continue.sh         # 阻止提前退出
    ├── pre-deploy-check.sh  # 部署门禁
    ├── enforce-plan-approval.sh
    └── enforce-codex-writes.sh

<project>/.ai-collab/        # 会话数据（每项目）
├── state.md                 # 当前状态
├── task.md                  # 原始任务
├── plan.md                  # 当前计划
├── review.md                # Codex 审查
├── steps.md                 # 执行步骤
├── codex-session-id         # Codex 会话 ID（保持上下文）
└── code/                    # 生成的代码
```

### 常见问题

| 问题 | 解决方案 |
|------|----------|
| 出现权限确认提示 | 运行 `grant-permissions.sh` 后重启会话 |
| Codex 被限流 | 脚本自动重试（指数退避） |
| 任务中途上下文丢失 | 运行 `/collab:resume` |
| 工作流无法退出 | 检查 `.ai-collab/state.md`，设置 `phase: done` 或删除文件 |

---

## License

MIT License - Feel free to modify and share.

## Author

Created with Claude Code + Codex collaboration.
