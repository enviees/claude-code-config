#!/bin/bash
# claude-setup.sh
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/enviees/claude-code-config/refs/heads/master/architecture-guide/claude-setup.sh | bash

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ── Config ────────────────────────────────────────────────────────────────────
GITHUB_RAW="https://raw.githubusercontent.com/enviees/claude-code-config/master"
GUIDE_PATH="architecture-guide/claude-code-architecture-guide.md"
LOG_FILE=".claude/setup.log"


# ── Logging helpers ───────────────────────────────────────────────────────────
mkdir -p .claude

log()  { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; log "OK: $1"; }
fail() { echo -e "${RED}✗ $1${NC}"; log "ERROR: $1"; echo -e "${YELLOW}→ Check log: $LOG_FILE${NC}"; exit 1; }
info() { echo -e "${CYAN}→${NC} $1"; log "INFO: $1"; }

# ── Start ─────────────────────────────────────────────────────────────────────
echo "" > "$LOG_FILE"
log "=== claude-setup.sh started at $(date) ==="
log "Dir: $(pwd)"

echo -e "\n${CYAN}Setting up Claude Code architecture...${NC}\n"

# ── 1. Validate claude CLI ────────────────────────────────────────────────────
info "Checking claude CLI..."
command -v claude &> /dev/null || fail "claude CLI not found. Install: https://claude.ai/code"
log "claude CLI: $(command -v claude)"
ok "claude CLI found"

# ── 2. Folders ────────────────────────────────────────────────────────────────
info "Creating folders..."
mkdir -p .claude/agents .claude/commands .claude/checkpoint-history scripts plans LOGS \
  || fail "Failed to create folders"
ok "Folders created"

# ── 3. Download guide ─────────────────────────────────────────────────────────
info "Downloading architecture guide..."
log "URL: $GITHUB_RAW/$GUIDE_PATH"

mkdir -p "$(dirname "$GUIDE_PATH")"
HTTP_STATUS=$(curl -fsSL -w "%{http_code}" -o "$GUIDE_PATH" "$GITHUB_RAW/$GUIDE_PATH" 2>> "$LOG_FILE")
[ "$HTTP_STATUS" = "200" ] || fail "Download failed (HTTP $HTTP_STATUS). URL: $GITHUB_RAW/$GUIDE_PATH"
[ -s "$GUIDE_PATH" ]       || fail "Downloaded guide is empty"

log "Guide: $(wc -l < "$GUIDE_PATH") lines"
ok "Downloaded $GUIDE_PATH"

# ── 4. Checkpoint + gitignore ─────────────────────────────────────────────────
info "Setting up checkpoint.json..."
[ ! -f ".claude/checkpoint.json" ] && { echo "{}" > .claude/checkpoint.json || fail "Failed to create checkpoint.json"; }

if [ -f ".gitignore" ] && ! grep -q "checkpoint-history" .gitignore; then
  printf "\n# Claude Code\n.claude/checkpoint-history/\n.claude/setup.log\n" >> .gitignore \
    || fail "Failed to update .gitignore"
  log ".gitignore updated"
fi
ok "checkpoint.json + .gitignore"

# ── 5. Run Claude headless ────────────────────────────────────────────────────
info "Running Claude Code to generate project files..."
log "Invoking claude -p..."

CLAUDE_OUTPUT=$(claude -p "
Read the file at $(pwd)/$GUIDE_PATH carefully.

Then set up this project for that architecture automatically:
1. Create all required folders: .claude/agents, .claude/commands, .claude/checkpoint-history, scripts, plans, LOGS
2. Create all 4 subagent files inside .claude/agents/ using the exact templates from section 11
3. Create .claude/commands/checkpoint.md using the template from section 12
4. Create scripts/save-checkpoint.sh using the template from section 12, then run: chmod +x scripts/save-checkpoint.sh
5. Create .claude/checkpoint.json with content: {}
6. Create CLAUDE.md using the template from section 10 exactly as written.
   - Current Checkpoint: No checkpoint yet. This is the start of the project.
7. Add .claude/checkpoint-history/ to .gitignore if .gitignore exists

After all files are created:
- List every file created with its path
- State any file that already existed and was skipped
- Say exactly: Setup complete. Run /clear to start fresh.

Do not ask for confirmation. Execute all steps now.
" --allowedTools "Read,Write,Bash" 2>> "$LOG_FILE") || {
  log "claude -p exited with error code $?"
  fail "Claude Code failed. See $LOG_FILE for details."
}

echo "$CLAUDE_OUTPUT" | tee -a "$LOG_FILE"

# ── 6. Verify files ───────────────────────────────────────────────────────────
info "Verifying generated files..."
MISSING=()
for f in "CLAUDE.md" \
         ".claude/agents/file-reader.md" \
         ".claude/agents/code-writer.md" \
         ".claude/agents/linter.md" \
         ".claude/agents/log-writer.md" \
         ".claude/commands/checkpoint.md" \
         "scripts/save-checkpoint.sh"; do
  if [ -f "$f" ]; then
    log "VERIFIED: $f"
  else
    MISSING+=("$f")
    log "MISSING: $f"
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo -e "\n${YELLOW}⚠ Files not created:${NC}"
  for f in "${MISSING[@]}"; do echo -e "  ${RED}✗${NC} $f"; done
  echo -e "${YELLOW}→ Check log: $LOG_FILE${NC}"
else
  ok "All files verified"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
log "=== Setup finished at $(date) ==="
echo ""
echo -e "${GREEN}Done.${NC} Open Claude Code and run ${CYAN}/clear${NC} to start."
echo -e "Full log: ${CYAN}$LOG_FILE${NC}\n"
