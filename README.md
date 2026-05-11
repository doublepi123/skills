# Skills

Custom skills for AI coding agents.

## Quick Install

```bash
git clone git@github.com:doublepi123/skills.git
cd skills

# interactive mode
./install.sh

# or specify target directly
./install.sh --target claude
./install.sh --target codex --skill review-fix-loop
./install.sh --target cursor --level user
```

Supports installing to: **Generic** (`.agents/skills/`), **Claude Code**, **OpenCode**, **Codex** (OpenAI), **Cursor**, **Traycer**, **Aider**, **Windsurf**, **Continue**, **Amp**.

## Skills

### review-fix-loop

Iterative code review and fix loop. Main agent orchestrates: review → fix → review → fix until code is clean or a cycle is detected.

Supports reviewing:
- Single/multiple files
- Git staged changes
- Diff from master or any branch
- Recent N commits

Built-in cycle detection (SHA256 content hashing) prevents A→B→A ping-pong changes. Produces a full review and fix report.
