Read the file at [claude-code-architecture-guide.md] carefully.

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
