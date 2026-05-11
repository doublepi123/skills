# Claude Code Skills

Custom skills for Claude Code.

## Skills

### review-fix-loop

Iterative code review and fix loop. Main agent orchestrates: review → fix → review → fix until code is clean or a cycle is detected.

Supports reviewing:
- Single/multiple files
- Git staged changes
- Diff from master or any branch
- Recent N commits

Built-in cycle detection prevents A→B→A ping-pong changes. Produces a full review and fix report.
