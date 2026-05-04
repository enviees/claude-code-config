#!/bin/bash
# claude-setup.sh
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/enviees/claude-code-config/refs/heads/master/architecture-guide/claude-setup.sh?token=GHSAT0AAAAAADZFEHEIZTPDF3V3QDX5DSAO2PYIF3A| bash -s -- 

set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

GITHUB_RAW="https://raw.githubusercontent.com/enviees/claude-code-config/master"
GUIDE_FILENAME="claude-code-architecture-guide.md?token=GHSAT0AAAAAADZFEHEIZTPDF3V3QDX5DSAO2PYIF3A"

STACK="[Edit — your stack]"
GOAL="[Edit — your project goal]"

echo -e "\n${CYAN}Setting up Claude Code architecture...${NC}\n"

# 1. Folders
mkdir -p .claude/agents .claude/commands .claude/checkpoint-history scripts plans LOGS
echo -e "${GREEN}✓${NC} Folders"

# 2. Download guide
curl -fsSL "$GITHUB_RAW/$GUIDE_FILENAME" -o "$GUIDE_FILENAME"
echo -e "${GREEN}✓${NC} Downloaded $GUIDE_FILENAME"

# 3. Checkpoint + gitignore
[ ! -f ".claude/checkpoint.json" ] && echo "{}" > .claude/checkpoint.json
if [ -f ".gitignore" ] && ! grep -q "checkpoint-history" .gitignore; then
  printf "\n# Claude Code\n.claude/checkpoint-history/\n" >> .gitignore
fi
echo -e "${GREEN}✓${NC} checkpoint.json + .gitignore"

# 4. Run Claude Code headless to generate all files from the guide
echo -e "${GREEN}✓${NC} Running Claude Code to generate files...\n"

claude -p "

Read the file at $(pwd)/$GUIDE_FILENAME carefully.

Then set up this project for that architecture automatically:

1. Create all required folders: .claude/agents, .claude/commands, .claude/checkpoint-history, scripts, plans, LOGS
2. Create all 4 subagent files inside .claude/agents/ using the exact templates from section 11
3. Create .claude/commands/checkpoint.md using the template from section 12
4. Create scripts/save-checkpoint.sh using the template from section 12, then run: chmod +x scripts/save-checkpoint.sh
5. Create .claude/checkpoint.json with content: {}
6. Create CLAUDE.md using the template from section 10.
7. Add .claude/checkpoint-history/ to .gitignore if .gitignore exists

After all files are created, confirm:
- List every file created with its path
- State any file that already existed and was skipped
- Say "Setup complete. Run /clear to start fresh."

Do not ask for confirmation. Execute all steps now.
"
